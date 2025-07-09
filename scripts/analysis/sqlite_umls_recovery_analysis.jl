#!/usr/bin/env julia

"""
Fast UMLS-based ICD-10 Recovery Analysis using SQLite database
"""

using JSON3
using CSV
using DataFrames
using SQLite

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

struct ICD10Mapping
    original_term::String
    cui::String
    preferred_name::String
    icd10_code::String
    icd10_source::String
    mapping_method::String
    confidence::Float64
    hierarchy_level::Int
end

function extract_icd10_chapter(code::String)
    if isempty(code)
        return ""
    end
    
    if length(code) >= 3
        return code[1:3]
    elseif length(code) >= 2
        return code[1:2]
    else
        return code
    end
end

function normalize_term(term::String)
    """Normalize medical term for consistent matching"""
    normalized = lowercase(strip(term))
    
    # Remove common descriptors
    normalized = replace(normalized, r"\\s*\\([^)]*\\)\\s*" => " ")
    normalized = replace(normalized, r"^(treatment of|therapy for|management of)\\s+" => "")
    normalized = replace(normalized, r"\\s+(therapy|treatment|management)\\s*$" => "")
    
    # Normalize whitespace
    normalized = replace(normalized, r"\\s+" => " ")
    normalized = strip(normalized)
    
    return normalized
end

function search_umls_sqlite(term::String, db)
    """Search for medical term in SQLite database"""
    
    normalized_term = normalize_term(term)
    
    # Try exact match first
    exact_query = """
        SELECT t.cui, c.preferred_name, m.icd10_source, m.icd10_code 
        FROM terms t 
        JOIN concepts c ON t.cui = c.cui 
        LEFT JOIN icd10_mappings m ON c.cui = m.cui
        WHERE t.term_lower = ? AND c.has_icd10 = 1
        ORDER BY t.is_preferred DESC
        LIMIT 5
    """
    
    results = []
    
    for row in SQLite.DBInterface.execute(db, exact_query, [normalized_term])
        push!(results, ICD10Mapping(
            term,
            row.cui,
            row.preferred_name,
            row.icd10_code,
            row.icd10_source,
            "direct",
            1.0,
            0
        ))
    end
    
    # If no exact match, try partial match
    if isempty(results)
        partial_query = """
            SELECT t.cui, c.preferred_name, m.icd10_source, m.icd10_code 
            FROM terms t 
            JOIN concepts c ON t.cui = c.cui 
            LEFT JOIN icd10_mappings m ON c.cui = m.cui
            WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
            ORDER BY t.is_preferred DESC
            LIMIT 5
        """
        
        for row in SQLite.DBInterface.execute(db, partial_query, ["%$normalized_term%"])
            push!(results, ICD10Mapping(
                term,
                row.cui,
                row.preferred_name,
                row.icd10_code,
                row.icd10_source,
                "partial",
                0.8,
                0
            ))
        end
    end
    
    # If still no results, try hierarchy traversal
    if isempty(results)
        # Find CUIs without direct ICD-10 codes that match the term
        cui_query = """
            SELECT DISTINCT t.cui, t.term_original
            FROM terms t 
            JOIN concepts c ON t.cui = c.cui
            WHERE t.term_lower LIKE ? AND c.has_icd10 = 0
            LIMIT 3
        """
        
        for row in SQLite.DBInterface.execute(db, cui_query, ["%$normalized_term%"])
            hierarchy_results = search_hierarchy_sqlite(row.cui, db)
            append!(results, hierarchy_results)
        end
    end
    
    return results[1:min(3, length(results))]
end

function search_hierarchy_sqlite(cui::String, db, max_depth::Int=3)
    """Search up hierarchy for ICD-10 codes"""
    
    visited = Set{String}()
    queue = [(cui, 0)]
    results = []
    
    while !isempty(queue) && length(results) == 0
        current_cui, depth = popfirst!(queue)
        
        if current_cui in visited || depth > max_depth
            continue
        end
        
        push!(visited, current_cui)
        
        # Check if current CUI has ICD-10 codes
        concept_query = """
            SELECT c.preferred_name, m.icd10_source, m.icd10_code 
            FROM concepts c
            LEFT JOIN icd10_mappings m ON c.cui = m.cui
            WHERE c.cui = ? AND c.has_icd10 = 1
            LIMIT 3
        """
        
        for row in SQLite.DBInterface.execute(db, concept_query, [current_cui])
            push!(results, ICD10Mapping(
                "hierarchy_search",
                current_cui,
                row.preferred_name,
                row.icd10_code,
                row.icd10_source,
                "parent_L$depth",
                0.7 - (depth * 0.1),
                depth
            ))
        end
        
        # If no ICD-10 codes, add parents to queue
        if isempty(results)
            parent_query = """
                SELECT parent_cui 
                FROM hierarchy 
                WHERE child_cui = ?
            """
            
            for row in SQLite.DBInterface.execute(db, parent_query, [current_cui])
                if row.parent_cui ∉ visited
                    push!(queue, (row.parent_cui, depth + 1))
                end
            end
        end
    end
    
    return results
end

function map_to_icd10_sqlite(indication::String, db)
    """Map indication to ICD-10 using SQLite database"""
    
    mappings = search_umls_sqlite(indication, db)
    return mappings
end

function load_drugbank_llm_icd10_mappings_sqlite(drug_name::String, db)
    """Load DrugBank LLM extracted indications and convert to ICD-10 (ground truth)"""
    drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/$(replace(drug_name, " " => "_"))_drugbank_extracted_indications.json"
    
    if !isfile(drugbank_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(drugbank_file, String))
        
        if haskey(data, "indications")
            confirmed_indications = filter(ind -> get(ind, "confirmed", false), data["indications"])
            
            all_codes = Set{String}()
            all_chapters = Set{String}()
            
            for indication in confirmed_indications
                condition = get(indication, "condition", "")
                if !isempty(condition)
                    mappings = map_to_icd10_sqlite(String(condition), db)
                    
                    for mapping in mappings
                        if !isempty(mapping.icd10_code)
                            push!(all_codes, mapping.icd10_code)
                            chapter = extract_icd10_chapter(mapping.icd10_code)
                            if !isempty(chapter)
                                push!(all_chapters, chapter)
                            end
                        end
                    end
                end
            end
            
            return all_codes, all_chapters
        end
    catch e
        println("Warning: Error processing DrugBank LLM data for $drug_name: $e")
    end
    
    return Set{String}(), Set{String}()
end

function load_mesh_icd10_mappings_sqlite(drug_name::String, db)
    """Load MeSH mappings and convert to ICD-10 using SQLite"""
    mesh_file = "/oscar/home/isarkar/sarkarcode/thera/drug_pubmed_refs/$(drug_name).json"
    
    if !isfile(mesh_file)
        return Set{String}(), Set{String}()
    end
    
    try
        if !@isdefined(MESH_T047_HEADINGS)
            include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
        end
        
        data = JSON3.read(read(mesh_file, String))
        
        pubs = if haskey(data, :result) && haskey(data.result, :publications_analyzed)
            data.result.publications_analyzed
        elseif haskey(data, :publications_analyzed)
            data.publications_analyzed
        else
            []
        end
        
        disease_descriptors = Set{String}()
        for pub in pubs
            if haskey(pub, "mesh_descriptors") && !isempty(pub["mesh_descriptors"])
                for mesh_obj in pub["mesh_descriptors"]
                    descriptor_name = String(mesh_obj["descriptor"])
                    if descriptor_name in MESH_T047_HEADINGS
                        push!(disease_descriptors, descriptor_name)
                    end
                end
            end
        end
        
        # Limit to first 20 descriptors for efficiency
        limited_descriptors = collect(disease_descriptors)[1:min(20, length(disease_descriptors))]
        
        all_codes = Set{String}()
        all_chapters = Set{String}()
        
        for descriptor in limited_descriptors
            mappings = map_to_icd10_sqlite(String(descriptor), db)
            
            for mapping in mappings
                if !isempty(mapping.icd10_code)
                    push!(all_codes, mapping.icd10_code)
                    chapter = extract_icd10_chapter(mapping.icd10_code)
                    if !isempty(chapter)
                        push!(all_chapters, chapter)
                    end
                end
            end
        end
        
        return all_codes, all_chapters
        
    catch e
        println("Warning: Error processing MeSH data for $drug_name: $e")
        return Set{String}(), Set{String}()
    end
end

function load_naive_llm_icd10_mappings_sqlite(drug_name::String, db)
    """Load Naive LLM mappings and convert to ICD-10 using SQLite"""
    naive_file = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications/$(replace(drug_name, " " => "_"))_naive_extracted_indications.json"
    
    if !isfile(naive_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(naive_file, String))
        
        if haskey(data, "indications")
            confirmed_indications = filter(ind -> get(ind, "confirmed", false), data["indications"])
            
            all_codes = Set{String}()
            all_chapters = Set{String}()
            
            for indication in confirmed_indications
                condition = get(indication, "condition", "")
                if !isempty(condition)
                    mappings = map_to_icd10_sqlite(String(condition), db)
                    
                    for mapping in mappings
                        if !isempty(mapping.icd10_code)
                            push!(all_codes, mapping.icd10_code)
                            chapter = extract_icd10_chapter(mapping.icd10_code)
                            if !isempty(chapter)
                                push!(all_chapters, chapter)
                            end
                        end
                    end
                end
            end
            
            return all_codes, all_chapters
        end
    catch e
        println("Warning: Error processing naive LLM data for $drug_name: $e")
    end
    
    return Set{String}(), Set{String}()
end

function load_pubmed_llm_icd10_mappings_sqlite(drug_name::String, db)
    """Load PubMed LLM mappings and convert to ICD-10 using SQLite"""
    pubmed_file = "/oscar/home/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/$(replace(drug_name, " " => "_"))_llama_extracted_indications.json"
    
    if !isfile(pubmed_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(pubmed_file, String))
        
        if haskey(data, "disease_pairs")
            confirmed_pairs = filter(pair -> get(pair, "confirmed", false), data["disease_pairs"])
            
            all_codes = Set{String}()
            all_chapters = Set{String}()
            
            for pair in confirmed_pairs
                disease = get(pair, "disease", "")
                if !isempty(disease)
                    mappings = map_to_icd10_sqlite(String(disease), db)
                    
                    for mapping in mappings
                        if !isempty(mapping.icd10_code)
                            push!(all_codes, mapping.icd10_code)
                            chapter = extract_icd10_chapter(mapping.icd10_code)
                            if !isempty(chapter)
                                push!(all_chapters, chapter)
                            end
                        end
                    end
                end
            end
            
            return all_codes, all_chapters
        end
    catch e
        println("Warning: Error processing PubMed LLM data for $drug_name: $e")
    end
    
    return Set{String}(), Set{String}()
end

function calculate_recovery_rates(extracted_codes, extracted_chapters, drugbank_codes, drugbank_chapters)
    if isempty(drugbank_codes) || isempty(drugbank_chapters)
        return 0.0, 0.0
    end
    
    code_overlap = intersect(extracted_codes, drugbank_codes)
    code_recovery = length(code_overlap) / length(drugbank_codes) * 100
    
    chapter_overlap = intersect(extracted_chapters, drugbank_chapters)
    chapter_recovery = length(chapter_overlap) / length(drugbank_chapters) * 100
    
    return code_recovery, chapter_recovery
end

function main()
    println("⚡ SQLite UMLS-based ICD-10 Recovery Analysis")
    println("=" ^ 70)
    
    # Check if database exists
    if !isfile(DB_PATH)
        println("❌ UMLS SQLite database not found at $DB_PATH")
        println("Please run build_umls_sqlite.jl first")
        return []
    end
    
    println("📊 Loading UMLS SQLite database...")
    db = SQLite.DB(DB_PATH)
    
    # Test database
    test_query = SQLite.DBInterface.execute(db, "SELECT COUNT(*) as count FROM icd10_mappings") |> first
    println("✅ Database loaded: $(test_query.count) ICD-10 mappings available")
    
    # Load approved drugs
    include("/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.jl")
    
    results = []
    processed_count = 0
    successful_mappings = 0
    
    println("\n🔍 Processing drugs with SQLite UMLS lookups...")
    
    # Test with first 20 drugs for efficiency
    for (drug_name, indication) in APPROVED_DRUGS_DICT
        processed_count += 1
        
        if processed_count > 20  # Limit for testing
            break
        end
        
        if processed_count % 5 == 0
            println("  Processed $processed_count drugs...")
        end
        
        # Load DrugBank LLM extracted indications as ground truth
        drugbank_codes, drugbank_chapters = load_drugbank_llm_icd10_mappings_sqlite(drug_name, db)
        
        # Skip drugs with no identifiable conditions
        if isempty(drugbank_codes) || isempty(drugbank_chapters)
            continue
        end
        
        successful_mappings += 1
        
        # Load extraction results and map to ICD-10
        mesh_codes, mesh_chapters = load_mesh_icd10_mappings_sqlite(drug_name, db)
        naive_codes, naive_chapters = load_naive_llm_icd10_mappings_sqlite(drug_name, db)
        pubmed_codes, pubmed_chapters = load_pubmed_llm_icd10_mappings_sqlite(drug_name, db)
        
        # Calculate recovery rates
        mesh_code_recovery, mesh_chapter_recovery = calculate_recovery_rates(
            mesh_codes, mesh_chapters, drugbank_codes, drugbank_chapters
        )
        
        naive_code_recovery, naive_chapter_recovery = calculate_recovery_rates(
            naive_codes, naive_chapters, drugbank_codes, drugbank_chapters
        )
        
        pubmed_code_recovery, pubmed_chapter_recovery = calculate_recovery_rates(
            pubmed_codes, pubmed_chapters, drugbank_codes, drugbank_chapters
        )
        
        # Store results
        push!(results, Dict(
            "drug_name" => drug_name,
            "mesh_icd10_code" => round(mesh_code_recovery, digits=1),
            "naive_icd10_code" => round(naive_code_recovery, digits=1),
            "pubmed_icd10_code" => round(pubmed_code_recovery, digits=1),
            "mesh_icd10_chapter" => round(mesh_chapter_recovery, digits=1),
            "naive_icd10_chapter" => round(naive_chapter_recovery, digits=1),
            "pubmed_icd10_chapter" => round(pubmed_chapter_recovery, digits=1),
            "drugbank_codes_count" => length(drugbank_codes),
            "drugbank_chapters_count" => length(drugbank_chapters)
        ))
        
        # Show progress for first few drugs
        if processed_count <= 5
            println("  ✓ $drug_name: DB=$(length(drugbank_codes)) codes, MeSH=$mesh_code_recovery%, Naive=$naive_code_recovery%, PubMed=$pubmed_code_recovery%")
        end
    end
    
    SQLite.close(db)
    
    if isempty(results)
        println("❌ No successful mappings found")
        return []
    end
    
    # Create results DataFrame
    df = DataFrame(results)
    
    # Format for display
    display_df = select(df, [
        :drug_name,
        :mesh_icd10_code,
        :naive_icd10_code,
        :pubmed_icd10_code,
        :mesh_icd10_chapter,
        :naive_icd10_chapter,
        :pubmed_icd10_chapter
    ])
    
    # Add percentage signs
    for col in [:mesh_icd10_code, :naive_icd10_code, :pubmed_icd10_code, 
                :mesh_icd10_chapter, :naive_icd10_chapter, :pubmed_icd10_chapter]
        display_df[!, col] = string.(display_df[!, col]) .* "%"
    end
    
    # Save results
    output_file = "/oscar/home/isarkar/sarkarcode/thera/sqlite_umls_icd10_recovery_analysis.csv"
    CSV.write(output_file, display_df)
    
    println("\n✅ SQLite UMLS Recovery Analysis Complete!")
    println("📊 Processed $processed_count total drugs")
    println("🎯 Successfully mapped $successful_mappings drugs with identifiable conditions")
    println("💾 Results saved to: $output_file")
    
    # Summary statistics
    if !isempty(results)
        numeric_cols = [:mesh_icd10_code, :naive_icd10_code, :pubmed_icd10_code, 
                       :mesh_icd10_chapter, :naive_icd10_chapter, :pubmed_icd10_chapter]
        
        println("\n📈 Summary Statistics:")
        for col in numeric_cols
            values = [r[string(col)] for r in results]
            mean_val = round(sum(values) / length(values), digits=1)
            median_val = round(sort(values)[div(length(values), 2)], digits=1)
            max_val = round(maximum(values), digits=1)
            nonzero_count = count(v -> v > 0, values)
            nonzero_percent = round(nonzero_count / length(values) * 100, digits=1)
            
            println("  $col:")
            println("    Mean = $mean_val%, Median = $median_val%, Max = $max_val%")
            println("    Non-zero recovery: $nonzero_count/$successful_mappings ($nonzero_percent%)")
        end
        
        # Show sample results
        println("\n📋 Sample Results:")
        println(first(display_df, min(10, size(display_df, 1))))
    end
    
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end