#!/usr/bin/env julia

"""
Local UMLS-based ICD-10 Recovery Analysis

Uses local UMLS files with efficient hash map indexing instead of API calls.
Much faster - should complete in minutes instead of hours.
"""

using JSON3
using CSV
using DataFrames

# UMLS file paths
const UMLS_META_DIR = "/oscar/data/ursa/umls/2025AA/META"
const MRCONSO_FILE = joinpath(UMLS_META_DIR, "MRCONSO.RRF")
const MRREL_FILE = joinpath(UMLS_META_DIR, "MRREL.RRF")
const MRSTY_FILE = joinpath(UMLS_META_DIR, "MRSTY.RRF")

# ICD-10 sources
const ICD10_SOURCES = ["ICD10", "ICD10CM", "ICD10AM", "ICD10AMAE"]

# Medical semantic types
const MEDICAL_SEMANTIC_TYPES = Set([
    "T047", "T048", "T049", "T050", "T033", "T046", 
    "T184", "T191", "T037", "T190", "T019"
])

# Global indexes
TERM_TO_CUIS = Dict{String, Set{String}}()          # term -> CUIs
CUI_TO_INFO = Dict{String, Dict{String, Any}}()     # CUI -> {name, semantic_types, icd10_codes}
CUI_HIERARCHY = Dict{String, Set{String}}()         # child_cui -> parent_cuis
LOADED = false

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

function build_umls_indexes()
    """Build efficient local indexes from UMLS files"""
    global TERM_TO_CUIS, CUI_TO_INFO, CUI_HIERARCHY, LOADED
    
    if LOADED
        return
    end
    
    println("🏗️  Building UMLS indexes from local files...")
    
    # Step 1: Load semantic types
    println("  📚 Loading semantic types...")
    semantic_types = Dict{String, Set{String}}()
    
    if isfile(MRSTY_FILE)
        line_count = 0
        open(MRSTY_FILE, "r") do file
            for line in eachline(file)
                line_count += 1
                if line_count % 100000 == 0
                    println("    Processed $line_count semantic type lines...")
                end
                
                fields = split(line, '|')
                if length(fields) >= 2
                    cui = fields[1]
                    sty = fields[2]
                    
                    if !haskey(semantic_types, cui)
                        semantic_types[cui] = Set{String}()
                    end
                    push!(semantic_types[cui], sty)
                end
            end
        end
        println("    ✅ Loaded semantic types for $(length(semantic_types)) CUIs")
    end
    
    # Step 2: Build term and CUI indexes from MRCONSO
    println("  📚 Building term and CUI indexes...")
    line_count = 0
    medical_cui_count = 0
    
    if isfile(MRCONSO_FILE)
        open(MRCONSO_FILE, "r") do file
            for line in eachline(file)
                line_count += 1
                if line_count % 1000000 == 0
                    println("    Processed $line_count MRCONSO lines...")
                end
                
                fields = split(line, '|')
                if length(fields) >= 18
                    cui = fields[1]
                    language = fields[2]
                    term_status = fields[3]
                    term = fields[15]
                    source = fields[12]
                    code = fields[14]
                    suppress = fields[17]
                    
                    # Only process English, non-suppressed terms
                    if language == "ENG" && suppress != "Y"
                        # Check if this is a medical concept
                        if haskey(semantic_types, cui)
                            cui_stypes = semantic_types[cui]
                            if !isempty(intersect(cui_stypes, MEDICAL_SEMANTIC_TYPES))
                                medical_cui_count += 1
                                
                                # Initialize CUI info if not exists
                                if !haskey(CUI_TO_INFO, cui)
                                    CUI_TO_INFO[cui] = Dict(
                                        "preferred_name" => "",
                                        "semantic_types" => cui_stypes,
                                        "icd10_codes" => Dict{String, String}()
                                    )
                                end
                                
                                cui_info = CUI_TO_INFO[cui]
                                
                                # Set preferred name
                                if term_status == "P" && isempty(cui_info["preferred_name"])
                                    cui_info["preferred_name"] = term
                                end
                                
                                # Add to term index (normalized)
                                term_lower = lowercase(strip(term))
                                if !isempty(term_lower) && length(term_lower) > 2
                                    if !haskey(TERM_TO_CUIS, term_lower)
                                        TERM_TO_CUIS[term_lower] = Set{String}()
                                    end
                                    push!(TERM_TO_CUIS[term_lower], cui)
                                end
                                
                                # Check for ICD-10 codes
                                if source in ICD10_SOURCES
                                    # Extract actual code from URL if needed
                                    actual_code = if occursin("/", code)
                                        split(code, "/")[end]
                                    else
                                        code
                                    end
                                    
                                    if !isempty(actual_code)
                                        cui_info["icd10_codes"][source] = actual_code
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        println("    ✅ Indexed $(length(TERM_TO_CUIS)) terms")
        println("    ✅ Indexed $(length(CUI_TO_INFO)) medical CUIs")
        println("    ✅ Found $(count(c -> !isempty(c["icd10_codes"]), values(CUI_TO_INFO))) CUIs with ICD-10 codes")
    end
    
    # Step 3: Build hierarchy index
    println("  📚 Building hierarchy index...")
    if isfile(MRREL_FILE)
        line_count = 0
        open(MRREL_FILE, "r") do file
            for line in eachline(file)
                line_count += 1
                if line_count % 1000000 == 0
                    println("    Processed $line_count relationship lines...")
                end
                
                fields = split(line, '|')
                if length(fields) >= 15
                    cui1 = fields[1]
                    rel = fields[4]
                    cui2 = fields[5]
                    suppress = fields[15]
                    
                    # Only process parent relationships for medical concepts
                    if rel == "PAR" && suppress != "Y" && 
                       haskey(CUI_TO_INFO, cui1) && haskey(CUI_TO_INFO, cui2)
                        
                        # cui2 is parent of cui1
                        if !haskey(CUI_HIERARCHY, cui1)
                            CUI_HIERARCHY[cui1] = Set{String}()
                        end
                        push!(CUI_HIERARCHY[cui1], cui2)
                    end
                end
            end
        end
        println("    ✅ Built hierarchy for $(length(CUI_HIERARCHY)) CUIs")
    end
    
    println("✅ UMLS indexes built successfully!")
    LOADED = true
end

function search_local_concepts(term::String)
    """Search for CUIs using local indexes"""
    
    if !LOADED
        build_umls_indexes()
    end
    
    term_lower = lowercase(strip(term))
    matches = []
    
    # Direct exact match
    if haskey(TERM_TO_CUIS, term_lower)
        for cui in TERM_TO_CUIS[term_lower]
            cui_info = CUI_TO_INFO[cui]
            push!(matches, (
                cui = cui,
                name = cui_info["preferred_name"],
                score = 1.0,
                match_type = "exact"
            ))
        end
    end
    
    # Partial matching if no exact matches
    if isempty(matches) && length(term_lower) > 3
        for (indexed_term, cuis) in TERM_TO_CUIS
            # Check for substring matches
            if occursin(term_lower, indexed_term) || occursin(indexed_term, term_lower)
                overlap = min(length(term_lower), length(indexed_term))
                total = max(length(term_lower), length(indexed_term))
                score = overlap / total
                
                if score >= 0.7  # Higher threshold for partial matches
                    for cui in cuis
                        cui_info = CUI_TO_INFO[cui]
                        push!(matches, (
                            cui = cui,
                            name = cui_info["preferred_name"],
                            score = score,
                            match_type = "partial"
                        ))
                    end
                end
            end
        end
    end
    
    # Sort by score and ICD-10 availability
    sort!(matches, by=x -> (x.score, !isempty(CUI_TO_INFO[x.cui]["icd10_codes"])), rev=true)
    
    return matches[1:min(5, length(matches))]
end

function get_local_cui_details(cui::String)
    """Get CUI details from local indexes"""
    
    if !haskey(CUI_TO_INFO, cui)
        return Dict(), []
    end
    
    cui_info = CUI_TO_INFO[cui]
    icd10_codes = []
    
    for (source, code) in cui_info["icd10_codes"]
        push!(icd10_codes, (source=source, code=code))
    end
    
    return cui_info, icd10_codes
end

function find_icd10_via_local_hierarchy(cui::String, max_depth::Int=3)
    """Find ICD-10 codes by traversing local hierarchy"""
    
    visited = Set{String}()
    queue = [(cui, 0)]
    
    while !isempty(queue)
        current_cui, depth = popfirst!(queue)
        
        if current_cui in visited || depth > max_depth
            continue
        end
        
        push!(visited, current_cui)
        
        # Check current CUI for ICD-10 codes
        cui_info, icd10_codes = get_local_cui_details(current_cui)
        
        if !isempty(icd10_codes)
            return cui_info, icd10_codes, depth
        end
        
        # Add parents to queue
        if haskey(CUI_HIERARCHY, current_cui)
            for parent_cui in CUI_HIERARCHY[current_cui]
                if parent_cui ∉ visited
                    push!(queue, (parent_cui, depth + 1))
                end
            end
        end
    end
    
    return Dict(), [], -1
end

function map_to_icd10_local(indication::String)
    """Map indication to ICD-10 using local UMLS indexes"""
    
    # Search for CUIs
    search_results = search_local_concepts(indication)
    
    if isempty(search_results)
        return ICD10Mapping[]
    end
    
    mappings = ICD10Mapping[]
    
    # For each CUI, check for ICD-10 codes (direct or via hierarchy)
    for result in search_results
        cui = result.cui
        name = result.name
        confidence = result.score
        
        # Check direct ICD-10 mapping first
        cui_info, icd10_codes = get_local_cui_details(cui)
        
        if !isempty(icd10_codes)
            # Direct mapping found
            for (source, code) in icd10_codes
                push!(mappings, ICD10Mapping(
                    indication,
                    cui,
                    name,
                    code,
                    source,
                    "direct",
                    confidence,
                    0
                ))
            end
        else
            # No direct mapping, try hierarchy
            parent_info, parent_icd10_codes, hierarchy_level = find_icd10_via_local_hierarchy(cui)
            
            if !isempty(parent_icd10_codes)
                method = "parent_L$hierarchy_level"
                parent_name = get(parent_info, "preferred_name", name)
                
                for (source, code) in parent_icd10_codes
                    push!(mappings, ICD10Mapping(
                        indication,
                        get(parent_info, "cui", cui),
                        parent_name,
                        code,
                        source,
                        method,
                        confidence * (0.9 ^ hierarchy_level),  # Decay confidence by level
                        hierarchy_level
                    ))
                end
            end
        end
        
        # Use first successful mapping (most confident)
        if !isempty(mappings)
            break
        end
    end
    
    return mappings
end

# Recovery analysis functions using local UMLS
function load_drugbank_llm_icd10_mappings_local(drug_name::String)
    """Load DrugBank LLM extracted indications and convert to ICD-10 (ground truth)"""
    drugbank_file = "../../llama_drugbank_extracted_indications/$(replace(drug_name, " " => "_"))_drugbank_extracted_indications.json"
    
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
                    mappings = map_to_icd10_local(String(condition))
                    
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

function load_mesh_icd10_mappings_local(drug_name::String)
    """Load MeSH mappings and convert to ICD-10 using local UMLS"""
    mesh_file = "../../drug_pubmed_refs/$(drug_name).json"
    
    if !isfile(mesh_file)
        return Set{String}(), Set{String}()
    end
    
    try
        if !@isdefined(MESH_T047_HEADINGS)
            include("../../mesh_t047_headings.jl")
        end
        
        data = JSON3.read(read(mesh_file, String))
        
        pubs = if haskey(data, :result) && haskey(data.result, :publications_analyzed)
            data.result.publications_analyzed
        elseif haskey(data, :publications_analyzed)
            data.publications_analyzed
        else
            []
        end
        
        # Get unique disease descriptors
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
        
        # Limit to top 20 most common descriptors to avoid too many lookups
        limited_descriptors = collect(disease_descriptors)[1:min(20, length(disease_descriptors))]
        
        all_codes = Set{String}()
        all_chapters = Set{String}()
        
        for descriptor in limited_descriptors
            mappings = map_to_icd10_local(String(descriptor))
            
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

function load_naive_llm_icd10_mappings_local(drug_name::String)
    """Load Naive LLM mappings and convert to ICD-10 using local UMLS"""
    naive_file = "../../llama_naive_extracted_indications/$(replace(drug_name, " " => "_"))_naive_extracted_indications.json"
    
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
                    mappings = map_to_icd10_local(String(condition))
                    
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

function load_pubmed_llm_icd10_mappings_local(drug_name::String)
    """Load PubMed LLM mappings and convert to ICD-10 using local UMLS"""
    pubmed_file = "../../llama_pubmed_extracted_indications/$(replace(drug_name, " " => "_"))_llama_extracted_indications.json"
    
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
                    mappings = map_to_icd10_local(String(disease))
                    
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
    println("🚀 Local UMLS-based ICD-10 Recovery Analysis")
    println("=" ^ 70)
    println("Using local UMLS files with efficient indexing")
    
    # Build indexes
    build_umls_indexes()
    
    # Load approved drugs
    include("../../approved_drugs_dict.jl")
    
    results = []
    processed_count = 0
    successful_mappings = 0
    
    println("\n🔍 Processing drugs with local UMLS lookups...")
    
    for (drug_name, indication) in APPROVED_DRUGS_DICT
        processed_count += 1
        
        if processed_count % 100 == 0
            println("  Processed $processed_count drugs...")
        end
        
        # Load DrugBank LLM extracted indications as ground truth
        drugbank_codes, drugbank_chapters = load_drugbank_llm_icd10_mappings_local(drug_name)
        
        # Skip drugs with no identifiable conditions
        if isempty(drugbank_codes) || isempty(drugbank_chapters)
            continue
        end
        
        successful_mappings += 1
        
        # Load extraction results and map to ICD-10
        mesh_codes, mesh_chapters = load_mesh_icd10_mappings_local(drug_name)
        naive_codes, naive_chapters = load_naive_llm_icd10_mappings_local(drug_name)
        pubmed_codes, pubmed_chapters = load_pubmed_llm_icd10_mappings_local(drug_name)
        
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
        if processed_count <= 10
            println("  ✓ $drug_name: DB=$(length(drugbank_codes)) codes, MeSH=$mesh_code_recovery%, Naive=$naive_code_recovery%, PubMed=$pubmed_code_recovery%")
        end
    end
    
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
    output_file = "../../local_umls_icd10_recovery_analysis.csv"
    CSV.write(output_file, display_df)
    
    println("\n✅ Local UMLS Recovery Analysis Complete!")
    println("📊 Processed $processed_count total drugs")
    println("🎯 Successfully mapped $successful_mappings drugs with identifiable conditions")
    println("💾 Results saved to: $output_file")
    
    # Summary statistics
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
    
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end