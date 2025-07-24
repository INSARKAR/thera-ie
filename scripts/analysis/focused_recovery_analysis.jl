#!/usr/bin/env julia

"""
Focused Recovery Analysis: DrugBank Ground Truth vs Extraction Methods
Measures how many DrugBank indications are recovered by:
1. MeSH extraction 
2. Naive LLM extraction
3. PubMed LLM extraction

At both ICD-10 code level and ICD-10 chapter level using UMLS mapping.
"""

using SQLite
using JSON3
using CSV
using DataFrames

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

# ICD-10 chapter mappings
const ICD10_CHAPTERS = Dict(
    "A00" => "I", "B00" => "I", "C00" => "II", "D00" => "III", 
    "E00" => "IV", "F00" => "V", "G00" => "VI", "H00" => "VII",
    "I00" => "IX", "J00" => "X", "K00" => "XI", "L00" => "XII",
    "M00" => "XIII", "N00" => "XIV", "O00" => "XV", "P00" => "XVI",
    "Q00" => "XVII", "R00" => "XVIII", "S00" => "XIX", "T00" => "XIX",
    "V00" => "XX", "W00" => "XX", "X00" => "XX", "Y00" => "XX", "Z00" => "XXI"
)

function get_icd10_chapter(icd10_code::String)
    """Extract ICD-10 chapter from code"""
    if length(icd10_code) >= 3
        prefix = uppercase(icd10_code[1:3])
        for (chapter_start, chapter) in ICD10_CHAPTERS
            if prefix >= chapter_start
                return chapter
            end
        end
    end
    return "Unknown"
end

function map_condition_to_icd10(condition::String, db)
    """Map a medical condition to ICD-10 codes using UMLS database"""
    
    normalized_condition = lowercase(strip(condition))
    icd10_codes = Set{String}()
    
    # Direct term lookup
    direct_query = """
        SELECT DISTINCT m.icd10_code 
        FROM terms t 
        JOIN concepts c ON t.cui = c.cui 
        JOIN icd10_mappings m ON c.cui = m.cui
        WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
        LIMIT 10
    """
    
    for row in SQLite.DBInterface.execute(db, direct_query, ["%$normalized_condition%"])
        if !isnothing(row.icd10_code) && !isempty(row.icd10_code)
            push!(icd10_codes, row.icd10_code)
        end
    end
    
    # If no direct mapping, try hierarchy traversal
    if isempty(icd10_codes)
        cui_query = """
            SELECT DISTINCT t.cui
            FROM terms t 
            JOIN concepts c ON t.cui = c.cui
            WHERE t.term_lower LIKE ? AND c.has_icd10 = 0
            LIMIT 3
        """
        
        for row in SQLite.DBInterface.execute(db, cui_query, ["%$normalized_condition%"])
            # Find parent concepts with ICD-10 codes
            parent_query = """
                SELECT DISTINCT m.icd10_code
                FROM hierarchy h
                JOIN concepts p ON h.parent_cui = p.cui
                JOIN icd10_mappings m ON p.cui = m.cui
                WHERE h.child_cui = ? AND p.has_icd10 = 1
                LIMIT 5
            """
            
            for parent_row in SQLite.DBInterface.execute(db, parent_query, [row.cui])
                if !isnothing(parent_row.icd10_code) && !isempty(parent_row.icd10_code)
                    push!(icd10_codes, parent_row.icd10_code)
                end
            end
        end
    end
    
    return icd10_codes
end

function load_drugbank_ground_truth(drug_name::String, db)
    """Load DrugBank LLM extracted indications as ground truth"""
    
    drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/$(replace(drug_name, " " => "_"))_drugbank_extracted_indications.json"
    
    if !isfile(drugbank_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(drugbank_file, String))
        
        if !haskey(data, "indications") || isempty(data.indications)
            return Set{String}(), Set{String}()
        end
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        for indication in data.indications
            if haskey(indication, "condition")
                condition_codes = map_condition_to_icd10(indication.condition, db)
                union!(icd10_codes, condition_codes)
                
                for code in condition_codes
                    chapter = get_icd10_chapter(code)
                    if chapter != "Unknown"
                        push!(icd10_chapters, chapter)
                    end
                end
            end
        end
        
        return icd10_codes, icd10_chapters
    catch e
        println("Error loading DrugBank data for $drug_name: $e")
        return Set{String}(), Set{String}()
    end
end

function load_mesh_extractions(drug_name::String, db)
    """Load MeSH extractions and map to ICD-10"""
    
    mesh_file = "/oscar/home/isarkar/sarkarcode/thera/phase1_drug_pubmed_refs/$(drug_name).json"
    
    if !isfile(mesh_file)
        return Set{String}(), Set{String}()
    end
    
    try
        include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
        
        data = JSON3.read(read(mesh_file, String))
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        if haskey(data, "mesh_summary") && haskey(data.mesh_summary, "mesh_terms")
            for mesh_term in data.mesh_summary.mesh_terms
                if haskey(mesh_term, "descriptor") && mesh_term.descriptor in MESH_T047_HEADINGS
                    condition_codes = map_condition_to_icd10(mesh_term.descriptor, db)
                    union!(icd10_codes, condition_codes)
                    
                    for code in condition_codes
                        chapter = get_icd10_chapter(code)
                        if chapter != "Unknown"
                            push!(icd10_chapters, chapter)
                        end
                    end
                end
            end
        end
        
        return icd10_codes, icd10_chapters
    catch e
        println("Error loading MeSH data for $drug_name: $e")
        return Set{String}(), Set{String}()
    end
end

function load_naive_llm_extractions(drug_name::String, db)
    """Load Naive LLM extractions and map to ICD-10"""
    
    naive_file = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications/$(replace(drug_name, " " => "_"))_naive_extracted_indications.json"
    
    if !isfile(naive_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(naive_file, String))
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        if haskey(data, "extracted_indications")
            for indication in data.extracted_indications
                if haskey(indication, "condition")
                    condition_codes = map_condition_to_icd10(indication.condition, db)
                    union!(icd10_codes, condition_codes)
                    
                    for code in condition_codes
                        chapter = get_icd10_chapter(code)
                        if chapter != "Unknown"
                            push!(icd10_chapters, chapter)
                        end
                    end
                end
            end
        end
        
        return icd10_codes, icd10_chapters
    catch e
        println("Error loading Naive LLM data for $drug_name: $e")
        return Set{String}(), Set{String}()
    end
end

function load_pubmed_llm_extractions(drug_name::String, db)
    """Load PubMed LLM extractions and map to ICD-10"""
    
    pubmed_file = "/oscar/home/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/$(replace(drug_name, " " => "_"))_llama_extracted_indications.json"
    
    if !isfile(pubmed_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(pubmed_file, String))
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        if haskey(data, "extracted_indications")
            for indication in data.extracted_indications
                if haskey(indication, "condition")
                    condition_codes = map_condition_to_icd10(indication.condition, db)
                    union!(icd10_codes, condition_codes)
                    
                    for code in condition_codes
                        chapter = get_icd10_chapter(code)
                        if chapter != "Unknown"
                            push!(icd10_chapters, chapter)
                        end
                    end
                end
            end
        end
        
        return icd10_codes, icd10_chapters
    catch e
        println("Error loading PubMed LLM data for $drug_name: $e")
        return Set{String}(), Set{String}()
    end
end

function calculate_recovery_rate(ground_truth_set, extracted_set)
    """Calculate recovery rate as percentage of ground truth recovered"""
    if isempty(ground_truth_set)
        return 0.0
    end
    
    recovered = length(intersect(ground_truth_set, extracted_set))
    total = length(ground_truth_set)
    
    return (recovered / total) * 100.0
end

function main()
    println("🎯 Focused Recovery Analysis: DrugBank vs Extraction Methods")
    println("=" ^ 70)
    
    # Load database
    println("📊 Loading UMLS SQLite database...")
    db = SQLite.DB(DB_PATH)
    
    # Load approved drugs
    include("/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.jl")
    
    results = []
    processed_count = 0
    successful_mappings = 0
    
    println("🔍 Processing drugs for recovery analysis...")
    
    for drug_name in keys(APPROVED_DRUGS_DICT)
        processed_count += 1
        
        # Load ground truth (DrugBank)
        drugbank_icd10, drugbank_chapters = load_drugbank_ground_truth(drug_name, db)
        
        if isempty(drugbank_icd10) && isempty(drugbank_chapters)
            continue  # Skip drugs without ground truth
        end
        
        successful_mappings += 1
        
        # Load extraction methods
        mesh_icd10, mesh_chapters = load_mesh_extractions(drug_name, db)
        naive_icd10, naive_chapters = load_naive_llm_extractions(drug_name, db)
        pubmed_icd10, pubmed_chapters = load_pubmed_llm_extractions(drug_name, db)
        
        # Calculate recovery rates
        mesh_icd10_recovery = calculate_recovery_rate(drugbank_icd10, mesh_icd10)
        naive_icd10_recovery = calculate_recovery_rate(drugbank_icd10, naive_icd10)
        pubmed_icd10_recovery = calculate_recovery_rate(drugbank_icd10, pubmed_icd10)
        
        mesh_chapter_recovery = calculate_recovery_rate(drugbank_chapters, mesh_chapters)
        naive_chapter_recovery = calculate_recovery_rate(drugbank_chapters, naive_chapters)
        pubmed_chapter_recovery = calculate_recovery_rate(drugbank_chapters, pubmed_chapters)
        
        push!(results, (
            drug_name = drug_name,
            drugbank_icd10_count = length(drugbank_icd10),
            drugbank_chapters_count = length(drugbank_chapters),
            mesh_icd10_recovery = mesh_icd10_recovery,
            naive_icd10_recovery = naive_icd10_recovery,
            pubmed_icd10_recovery = pubmed_icd10_recovery,
            mesh_chapter_recovery = mesh_chapter_recovery,
            naive_chapter_recovery = naive_chapter_recovery,
            pubmed_chapter_recovery = pubmed_chapter_recovery
        ))
        
        if successful_mappings <= 10  # Show progress for first 10
            println("  ✓ $(drug_name): DB=$(length(drugbank_icd10)) ICD-10, MeSH=$(round(mesh_icd10_recovery, digits=1))%, Naive=$(round(naive_icd10_recovery, digits=1))%, PubMed=$(round(pubmed_icd10_recovery, digits=1))%")
        elseif successful_mappings % 5 == 0
            println("  Processed $successful_mappings drugs...")
        end
    end
    
    SQLite.close(db)
    
    if isempty(results)
        println("❌ No drugs with recoverable ground truth found")
        return
    end
    
    # Create results DataFrame
    df = DataFrame(results)
    
    # Calculate summary statistics
    println("\n✅ Focused Recovery Analysis Complete!")
    println("📊 Processed $processed_count total drugs")
    println("🎯 Successfully analyzed $successful_mappings drugs with DrugBank ground truth")
    
    # ICD-10 Code Level Statistics
    println("\n📋 ICD-10 Code Recovery Statistics:")
    mesh_mean = round(sum(df.mesh_icd10_recovery) / length(df), digits=1)
    naive_mean = round(sum(df.naive_icd10_recovery) / length(df), digits=1)
    pubmed_mean = round(sum(df.pubmed_icd10_recovery) / length(df), digits=1)
    
    mesh_nonzero = sum(df.mesh_icd10_recovery .> 0)
    naive_nonzero = sum(df.naive_icd10_recovery .> 0)
    pubmed_nonzero = sum(df.pubmed_icd10_recovery .> 0)
    
    println("  MeSH:      Mean = $(mesh_mean)%, Non-zero = $(mesh_nonzero)/$(length(df)) ($(round(mesh_nonzero/length(df)*100, digits=1))%)")
    println("  Naive LLM: Mean = $(naive_mean)%, Non-zero = $(naive_nonzero)/$(length(df)) ($(round(naive_nonzero/length(df)*100, digits=1))%)")
    println("  PubMed LLM: Mean = $(pubmed_mean)%, Non-zero = $(pubmed_nonzero)/$(length(df)) ($(round(pubmed_nonzero/length(df)*100, digits=1))%)")
    
    # ICD-10 Chapter Level Statistics
    println("\n📋 ICD-10 Chapter Recovery Statistics:")
    mesh_chap_mean = round(sum(df.mesh_chapter_recovery) / length(df), digits=1)
    naive_chap_mean = round(sum(df.naive_chapter_recovery) / length(df), digits=1)
    pubmed_chap_mean = round(sum(df.pubmed_chapter_recovery) / length(df), digits=1)
    
    mesh_chap_nonzero = sum(df.mesh_chapter_recovery .> 0)
    naive_chap_nonzero = sum(df.naive_chapter_recovery .> 0)
    pubmed_chap_nonzero = sum(df.pubmed_chapter_recovery .> 0)
    
    println("  MeSH:      Mean = $(mesh_chap_mean)%, Non-zero = $(mesh_chap_nonzero)/$(length(df)) ($(round(mesh_chap_nonzero/length(df)*100, digits=1))%)")
    println("  Naive LLM: Mean = $(naive_chap_mean)%, Non-zero = $(naive_chap_nonzero)/$(length(df)) ($(round(naive_chap_nonzero/length(df)*100, digits=1))%)")
    println("  PubMed LLM: Mean = $(pubmed_chap_mean)%, Non-zero = $(pubmed_chap_nonzero)/$(length(df)) ($(round(pubmed_chap_nonzero/length(df)*100, digits=1))%)")
    
    # Save results
    output_file = "/oscar/home/isarkar/sarkarcode/thera/focused_drugbank_recovery_analysis.csv"
    
    # Format for display
    display_df = copy(df)
    for col in [:mesh_icd10_recovery, :naive_icd10_recovery, :pubmed_icd10_recovery, 
                :mesh_chapter_recovery, :naive_chapter_recovery, :pubmed_chapter_recovery]
        display_df[!, col] = round.(display_df[!, col], digits=1)
    end
    
    CSV.write(output_file, display_df)
    println("💾 Results saved to: $output_file")
    
    # Show sample results
    println("\n📋 Sample Results:")
    println(first(display_df, min(10, nrow(display_df))))
    
    println("\n🏆 Analysis Complete! DrugBank ground truth recovery rates calculated.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end