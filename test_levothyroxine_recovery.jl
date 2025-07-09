#!/usr/bin/env julia

"""
Test Recovery Analysis with Levothyroxine
DrugBank Ground Truth vs MeSH/Naive LLM/PubMed LLM extractions
"""

using SQLite
using JSON3

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

function map_condition_to_icd10(condition::String, db)
    """Map a medical condition to ICD-10 codes using UMLS database"""
    
    normalized_condition = lowercase(strip(condition))
    icd10_codes = Set{String}()
    
    println("    Mapping: '$condition'")
    
    # Direct term lookup
    direct_query = """
        SELECT DISTINCT m.icd10_code, c.preferred_name
        FROM terms t 
        JOIN concepts c ON t.cui = c.cui 
        JOIN icd10_mappings m ON c.cui = m.cui
        WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
        LIMIT 5
    """
    
    found_direct = false
    for row in SQLite.DBInterface.execute(db, direct_query, ["%$normalized_condition%"])
        if !isnothing(row.icd10_code) && !isempty(row.icd10_code)
            push!(icd10_codes, row.icd10_code)
            println("      ✅ Direct: $(row.preferred_name) → $(row.icd10_code)")
            found_direct = true
        end
    end
    
    if !found_direct
        println("      ❌ No direct ICD-10 mapping found")
    end
    
    return icd10_codes
end

function test_levothyroxine_recovery()
    println("🧪 Levothyroxine Recovery Analysis Test")
    println("=" ^ 50)
    
    db = SQLite.DB(DB_PATH)
    drug_name = "Levothyroxine"
    
    # 1. Load DrugBank Ground Truth
    println("\n📋 1. DrugBank Ground Truth:")
    drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/Levothyroxine_drugbank_extracted_indications.json"
    
    drugbank_icd10 = Set{String}()
    drugbank_chapters = Set{String}()
    
    if isfile(drugbank_file)
        data = JSON3.read(read(drugbank_file, String))
        
        if haskey(data, "indications")
            println("  Found $(length(data.indications)) DrugBank indications:")
            
            for (i, indication) in enumerate(data.indications)
                condition = indication.condition
                println("    $i. $condition")
                
                condition_codes = map_condition_to_icd10(condition, db)
                union!(drugbank_icd10, condition_codes)
                
                for code in condition_codes
                    chapter = get_icd10_chapter(code)
                    if chapter != "Unknown"
                        push!(drugbank_chapters, chapter)
                    end
                end
            end
        end
    else
        println("  ❌ DrugBank file not found")
    end
    
    println("  → DrugBank ICD-10 codes: $(collect(drugbank_icd10))")
    println("  → DrugBank chapters: $(collect(drugbank_chapters))")
    
    # 2. Load MeSH Extractions
    println("\n📋 2. MeSH Extractions:")
    mesh_file = "/oscar/home/isarkar/sarkarcode/thera/drug_pubmed_refs/Levothyroxine.json"
    
    mesh_icd10 = Set{String}()
    mesh_chapters = Set{String}()
    
    if isfile(mesh_file)
        try
            include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
            data = JSON3.read(read(mesh_file, String))
            
            if haskey(data, "mesh_summary") && haskey(data.mesh_summary, "mesh_terms")
                disease_terms = [term for term in data.mesh_summary.mesh_terms 
                               if haskey(term, "descriptor") && term.descriptor in MESH_T047_HEADINGS]
                
                println("  Found $(length(disease_terms)) MeSH disease terms:")
                
                for (i, mesh_term) in enumerate(disease_terms)
                    descriptor = mesh_term.descriptor
                    println("    $i. $descriptor")
                    
                    condition_codes = map_condition_to_icd10(descriptor, db)
                    union!(mesh_icd10, condition_codes)
                    
                    for code in condition_codes
                        chapter = get_icd10_chapter(code)
                        if chapter != "Unknown"
                            push!(mesh_chapters, chapter)
                        end
                    end
                end
            end
        catch e
            println("  ❌ Error loading MeSH data: $e")
        end
    else
        println("  ❌ MeSH file not found")
    end
    
    println("  → MeSH ICD-10 codes: $(collect(mesh_icd10))")
    println("  → MeSH chapters: $(collect(mesh_chapters))")
    
    # 3. Load Naive LLM Extractions
    println("\n📋 3. Naive LLM Extractions:")
    naive_file = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications/Levothyroxine_naive_extracted_indications.json"
    
    naive_icd10 = Set{String}()
    naive_chapters = Set{String}()
    
    if isfile(naive_file)
        try
            data = JSON3.read(read(naive_file, String))
            
            if haskey(data, "extracted_indications")
                println("  Found $(length(data.extracted_indications)) naive LLM indications:")
                
                for (i, indication) in enumerate(data.extracted_indications)
                    if haskey(indication, "condition")
                        condition = indication.condition
                        println("    $i. $condition")
                        
                        condition_codes = map_condition_to_icd10(condition, db)
                        union!(naive_icd10, condition_codes)
                        
                        for code in condition_codes
                            chapter = get_icd10_chapter(code)
                            if chapter != "Unknown"
                                push!(naive_chapters, chapter)
                            end
                        end
                    end
                end
            end
        catch e
            println("  ❌ Error loading Naive LLM data: $e")
        end
    else
        println("  ❌ Naive LLM file not found")
    end
    
    println("  → Naive LLM ICD-10 codes: $(collect(naive_icd10))")
    println("  → Naive LLM chapters: $(collect(naive_chapters))")
    
    # 4. Load PubMed LLM Extractions
    println("\n📋 4. PubMed LLM Extractions:")
    pubmed_file = "/oscar/home/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/Levothyroxine_llama_extracted_indications.json"
    
    pubmed_icd10 = Set{String}()
    pubmed_chapters = Set{String}()
    
    if isfile(pubmed_file)
        try
            data = JSON3.read(read(pubmed_file, String))
            
            if haskey(data, "extracted_indications")
                println("  Found $(length(data.extracted_indications)) PubMed LLM indications:")
                
                for (i, indication) in enumerate(data.extracted_indications)
                    if haskey(indication, "condition")
                        condition = indication.condition
                        println("    $i. $condition")
                        
                        condition_codes = map_condition_to_icd10(condition, db)
                        union!(pubmed_icd10, condition_codes)
                        
                        for code in condition_codes
                            chapter = get_icd10_chapter(code)
                            if chapter != "Unknown"
                                push!(pubmed_chapters, chapter)
                            end
                        end
                    end
                end
            end
        catch e
            println("  ❌ Error loading PubMed LLM data: $e")
        end
    else
        println("  ❌ PubMed LLM file not found")
    end
    
    println("  → PubMed LLM ICD-10 codes: $(collect(pubmed_icd10))")
    println("  → PubMed LLM chapters: $(collect(pubmed_chapters))")
    
    # 5. Calculate Recovery Rates
    println("\n🎯 Recovery Rate Analysis:")
    println("=" ^ 30)
    
    function calculate_recovery(ground_truth, extracted, level_name)
        if isempty(ground_truth)
            return 0.0, 0, 0
        end
        
        intersection_set = intersect(ground_truth, extracted)
        recovered = length(intersection_set)
        total = length(ground_truth)
        recovery_rate = (recovered / total) * 100.0
        
        println("  $level_name:")
        println("    Ground Truth: $(collect(ground_truth))")
        println("    Extracted: $(collect(extracted))")
        println("    Intersection: $(collect(intersection_set))")
        println("    Recovery: $recovered/$total = $(round(recovery_rate, digits=1))%")
        
        return recovery_rate, recovered, total
    end
    
    # ICD-10 Code Level
    println("\n📊 ICD-10 Code Level Recovery:")
    mesh_code_recovery, _, _ = calculate_recovery(drugbank_icd10, mesh_icd10, "MeSH")
    naive_code_recovery, _, _ = calculate_recovery(drugbank_icd10, naive_icd10, "Naive LLM")
    pubmed_code_recovery, _, _ = calculate_recovery(drugbank_icd10, pubmed_icd10, "PubMed LLM")
    
    # ICD-10 Chapter Level
    println("\n📊 ICD-10 Chapter Level Recovery:")
    mesh_chapter_recovery, _, _ = calculate_recovery(drugbank_chapters, mesh_chapters, "MeSH")
    naive_chapter_recovery, _, _ = calculate_recovery(drugbank_chapters, naive_chapters, "Naive LLM")
    pubmed_chapter_recovery, _, _ = calculate_recovery(drugbank_chapters, pubmed_chapters, "PubMed LLM")
    
    # Summary
    println("\n🏆 SUMMARY - Levothyroxine Recovery Analysis:")
    println("=" ^ 50)
    println("ICD-10 Code Recovery:")
    println("  MeSH:      $(round(mesh_code_recovery, digits=1))%")
    println("  Naive LLM: $(round(naive_code_recovery, digits=1))%")
    println("  PubMed LLM: $(round(pubmed_code_recovery, digits=1))%")
    
    println("\nICD-10 Chapter Recovery:")
    println("  MeSH:      $(round(mesh_chapter_recovery, digits=1))%")
    println("  Naive LLM: $(round(naive_chapter_recovery, digits=1))%")
    println("  PubMed LLM: $(round(pubmed_chapter_recovery, digits=1))%")
    
    SQLite.close(db)
    
    println("\n✅ Levothyroxine recovery analysis complete!")
end

test_levothyroxine_recovery()