#!/usr/bin/env julia

"""
Real Recovery Analysis for Levothyroxine using actual input files
Output: CSV with drug, mesh_icd10, naive_icd10, pubmed_icd10, mesh_chapter, naive_chapter, pubmed_chapter
"""

using SQLite
using JSON3
using CSV
using DataFrames

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

# ICD-10 chapter mappings
const ICD10_CHAPTERS = Dict(
    "A" => "I", "B" => "I", "C" => "II", "D" => "III", 
    "E" => "IV", "F" => "V", "G" => "VI", "H" => "VII",
    "I" => "IX", "J" => "X", "K" => "XI", "L" => "XII",
    "M" => "XIII", "N" => "XIV", "O" => "XV", "P" => "XVI",
    "Q" => "XVII", "R" => "XVIII", "S" => "XIX", "T" => "XIX",
    "V" => "XX", "W" => "XX", "X" => "XX", "Y" => "XX", "Z" => "XXI"
)

function get_icd10_chapter(icd10_code::String)
    """Extract ICD-10 chapter from code"""
    if !isempty(icd10_code)
        first_char = uppercase(string(icd10_code[1]))
        return get(ICD10_CHAPTERS, first_char, "Unknown")
    end
    return "Unknown"
end

function extract_medical_terms(text::String)
    """Extract key medical terms from condition text"""
    # Split into words and clean
    words = split(lowercase(text), r"[^a-zA-Z]+")
    
    # Filter for potential medical terms (length > 3, not common words)
    medical_terms = []
    common_words = Set(["primary", "secondary", "tertiary", "congenital", "acquired", "therapy", "treatment", "management", "adjunctive", "well", "differentiated"])
    
    for word in words
        if length(word) > 3 && !(word in common_words)
            push!(medical_terms, word)
        end
    end
    
    # Also include the original text
    push!(medical_terms, lowercase(strip(text)))
    
    return unique(medical_terms)
end

function map_condition_to_icd10(condition::String, db)
    """Map a medical condition to ICD-10 codes using UMLS database"""
    
    icd10_codes = Set{String}()
    
    # Extract key terms from the condition
    terms_to_search = extract_medical_terms(condition)
    
    for term in terms_to_search
        # Direct term lookup
        direct_query = """
            SELECT DISTINCT m.icd10_code
            FROM terms t 
            JOIN concepts c ON t.cui = c.cui 
            JOIN icd10_mappings m ON c.cui = m.cui
            WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
        """
        
        for row in SQLite.DBInterface.execute(db, direct_query, ["%$term%"])
            if !isnothing(row.icd10_code) && !isempty(row.icd10_code)
                push!(icd10_codes, row.icd10_code)
            end
        end
    end
    
    return icd10_codes
end

function load_drugbank_ground_truth(drug_name::String, db)
    """Load DrugBank ground truth from real file"""
    
    drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/$(drug_name)_drugbank_extracted_indications.json"
    
    println("Loading DrugBank: $drugbank_file")
    
    if !isfile(drugbank_file)
        println("  ❌ File not found")
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(drugbank_file, String))
        
        if !haskey(data, "indications") || isempty(data.indications)
            println("  ❌ No indications found")
            return Set{String}(), Set{String}()
        end
        
        println("  ✅ Found $(length(data.indications)) indications")
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        for indication in data.indications
            if haskey(indication, "condition")
                condition = indication.condition
                println("    Processing: '$condition'")
                
                condition_codes = map_condition_to_icd10(condition, db)
                println("      → ICD-10 codes: $(collect(condition_codes))")
                
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
        println("  ❌ Error loading: $e")
        return Set{String}(), Set{String}()
    end
end

function load_mesh_extractions(drug_name::String, db)
    """Load MeSH extractions from real file"""
    
    mesh_file = "/oscar/home/isarkar/sarkarcode/thera/drug_pubmed_refs/$(drug_name).json"
    
    println("Loading MeSH: $mesh_file")
    
    if !isfile(mesh_file)
        println("  ❌ File not found")
        return Set{String}(), Set{String}()
    end
    
    try
        # Load MeSH disease headings
        include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
        
        data = JSON3.read(read(mesh_file, String))
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        if haskey(data, "mesh_summary") && haskey(data.mesh_summary, "mesh_terms")
            disease_terms = []
            for mesh_term in data.mesh_summary.mesh_terms
                if haskey(mesh_term, "descriptor") && mesh_term.descriptor in MESH_T047_HEADINGS
                    push!(disease_terms, mesh_term.descriptor)
                end
            end
            
            println("  ✅ Found $(length(disease_terms)) disease MeSH terms")
            
            for descriptor in disease_terms
                println("    Processing: '$descriptor'")
                
                condition_codes = map_condition_to_icd10(descriptor, db)
                println("      → ICD-10 codes: $(collect(condition_codes))")
                
                union!(icd10_codes, condition_codes)
                
                for code in condition_codes
                    chapter = get_icd10_chapter(code)
                    if chapter != "Unknown"
                        push!(icd10_chapters, chapter)
                    end
                end
            end
        else
            println("  ❌ No mesh_summary found")
        end
        
        return icd10_codes, icd10_chapters
        
    catch e
        println("  ❌ Error loading: $e")
        return Set{String}(), Set{String}()
    end
end

function load_naive_llm_extractions(drug_name::String, db)
    """Load Naive LLM extractions from real file"""
    
    naive_file = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications/$(drug_name)_naive_extracted_indications.json"
    
    println("Loading Naive LLM: $naive_file")
    
    if !isfile(naive_file)
        println("  ❌ File not found")
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(naive_file, String))
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        if haskey(data, "extracted_indications") && !isempty(data.extracted_indications)
            println("  ✅ Found $(length(data.extracted_indications)) naive extractions")
            
            for indication in data.extracted_indications
                if haskey(indication, "condition")
                    condition = indication.condition
                    println("    Processing: '$condition'")
                    
                    condition_codes = map_condition_to_icd10(condition, db)
                    println("      → ICD-10 codes: $(collect(condition_codes))")
                    
                    union!(icd10_codes, condition_codes)
                    
                    for code in condition_codes
                        chapter = get_icd10_chapter(code)
                        if chapter != "Unknown"
                            push!(icd10_chapters, chapter)
                        end
                    end
                end
            end
        else
            println("  ❌ No extracted_indications found")
        end
        
        return icd10_codes, icd10_chapters
        
    catch e
        println("  ❌ Error loading: $e")
        return Set{String}(), Set{String}()
    end
end

function load_pubmed_llm_extractions(drug_name::String, db)
    """Load PubMed LLM extractions from real file"""
    
    pubmed_file = "/oscar/home/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/$(drug_name)_llama_extracted_indications.json"
    
    println("Loading PubMed LLM: $pubmed_file")
    
    if !isfile(pubmed_file)
        println("  ❌ File not found")
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(pubmed_file, String))
        
        icd10_codes = Set{String}()
        icd10_chapters = Set{String}()
        
        if haskey(data, "extracted_indications") && !isempty(data.extracted_indications)
            println("  ✅ Found $(length(data.extracted_indications)) PubMed extractions")
            
            for indication in data.extracted_indications
                if haskey(indication, "condition")
                    condition = indication.condition
                    println("    Processing: '$condition'")
                    
                    condition_codes = map_condition_to_icd10(condition, db)
                    println("      → ICD-10 codes: $(collect(condition_codes))")
                    
                    union!(icd10_codes, condition_codes)
                    
                    for code in condition_codes
                        chapter = get_icd10_chapter(code)
                        if chapter != "Unknown"
                            push!(icd10_chapters, chapter)
                        end
                    end
                end
            end
        else
            println("  ❌ No extracted_indications found")
        end
        
        return icd10_codes, icd10_chapters
        
    catch e
        println("  ❌ Error loading: $e")
        return Set{String}(), Set{String}()
    end
end

function calculate_recovery_rate(ground_truth_set, extracted_set)
    """Calculate recovery rate as percentage"""
    if isempty(ground_truth_set)
        return 0.0
    end
    
    intersection = intersect(ground_truth_set, extracted_set)
    return (length(intersection) / length(ground_truth_set)) * 100.0
end

function analyze_levothyroxine()
    println("🎯 Real Levothyroxine Recovery Analysis")
    println("=" ^ 50)
    
    db = SQLite.DB(DB_PATH)
    drug_name = "Levothyroxine"
    
    # Load ground truth
    println("\n📋 1. Loading DrugBank Ground Truth...")
    drugbank_icd10, drugbank_chapters = load_drugbank_ground_truth(drug_name, db)
    
    println("\n  DrugBank Results:")
    println("    ICD-10 codes: $(collect(drugbank_icd10))")
    println("    Chapters: $(collect(drugbank_chapters))")
    
    # Load extraction methods
    println("\n📋 2. Loading MeSH Extractions...")
    mesh_icd10, mesh_chapters = load_mesh_extractions(drug_name, db)
    
    println("\n  MeSH Results:")
    println("    ICD-10 codes: $(collect(mesh_icd10))")
    println("    Chapters: $(collect(mesh_chapters))")
    
    println("\n📋 3. Loading Naive LLM Extractions...")
    naive_icd10, naive_chapters = load_naive_llm_extractions(drug_name, db)
    
    println("\n  Naive LLM Results:")
    println("    ICD-10 codes: $(collect(naive_icd10))")
    println("    Chapters: $(collect(naive_chapters))")
    
    println("\n📋 4. Loading PubMed LLM Extractions...")
    pubmed_icd10, pubmed_chapters = load_pubmed_llm_extractions(drug_name, db)
    
    println("\n  PubMed LLM Results:")
    println("    ICD-10 codes: $(collect(pubmed_icd10))")
    println("    Chapters: $(collect(pubmed_chapters))")
    
    # Calculate recovery rates
    mesh_icd10_recovery = calculate_recovery_rate(drugbank_icd10, mesh_icd10)
    naive_icd10_recovery = calculate_recovery_rate(drugbank_icd10, naive_icd10)
    pubmed_icd10_recovery = calculate_recovery_rate(drugbank_icd10, pubmed_icd10)
    
    mesh_chapter_recovery = calculate_recovery_rate(drugbank_chapters, mesh_chapters)
    naive_chapter_recovery = calculate_recovery_rate(drugbank_chapters, naive_chapters)
    pubmed_chapter_recovery = calculate_recovery_rate(drugbank_chapters, pubmed_chapters)
    
    # Create CSV output
    result = DataFrame(
        drug = [drug_name],
        mesh_icd10 = [round(mesh_icd10_recovery, digits=1)],
        naive_icd10 = [round(naive_icd10_recovery, digits=1)],
        pubmed_icd10 = [round(pubmed_icd10_recovery, digits=1)],
        mesh_chapter = [round(mesh_chapter_recovery, digits=1)],
        naive_chapter = [round(naive_chapter_recovery, digits=1)],
        pubmed_chapter = [round(pubmed_chapter_recovery, digits=1)]
    )
    
    println("\n🎯 Recovery Analysis Results:")
    println(result)
    
    # Save to CSV
    output_file = "/oscar/home/isarkar/sarkarcode/thera/levothyroxine_recovery_analysis.csv"
    CSV.write(output_file, result)
    
    println("\n💾 Results saved to: $output_file")
    
    SQLite.close(db)
    
    println("\n✅ Levothyroxine analysis complete!")
end

analyze_levothyroxine()