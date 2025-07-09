#!/usr/bin/env julia

using SQLite
using JSON3

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

function extract_key_terms(condition::String)
    """Extract key medical terms from complex condition descriptions"""
    
    # Convert to lowercase and split into words
    words = split(lowercase(condition), r"[^a-z]+")
    
    # Medical terms to look for
    key_terms = []
    
    # Common medical term patterns
    medical_keywords = ["hypothyroidism", "thyroid", "cancer", "pituitary", "diabetes", "hypertension", "heart", "disease"]
    
    for word in words
        if length(word) > 3 && any(keyword -> occursin(keyword, word) || occursin(word, keyword), medical_keywords)
            push!(key_terms, word)
        end
    end
    
    # Also try the original condition
    push!(key_terms, lowercase(strip(condition)))
    
    return unique(key_terms)
end

function simple_lookup(condition::String, db)
    """Simple ICD-10 lookup with key term extraction"""
    
    println("  Testing: '$condition'")
    
    # Extract key terms
    terms_to_try = extract_key_terms(condition)
    println("    Key terms: $(terms_to_try)")
    
    icd10_codes = Set{String}()
    
    for term in terms_to_try
        query = """
            SELECT DISTINCT m.icd10_code, c.preferred_name
            FROM terms t 
            JOIN concepts c ON t.cui = c.cui 
            JOIN icd10_mappings m ON c.cui = m.cui
            WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
            LIMIT 3
        """
        
        for row in SQLite.DBInterface.execute(db, query, ["%$term%"])
            if !isnothing(row.icd10_code) && !isempty(row.icd10_code)
                push!(icd10_codes, row.icd10_code)
                println("      ✅ '$term' → $(row.preferred_name) → $(row.icd10_code)")
            end
        end
    end
    
    if isempty(icd10_codes)
        println("      ❌ No ICD-10 mapping found")
    end
    
    return icd10_codes
end

function simple_test()
    println("🧪 Simple Levothyroxine Recovery Test")
    println("=" ^ 40)
    
    db = SQLite.DB(DB_PATH)
    
    # Test DrugBank conditions
    println("\n📋 DrugBank Ground Truth:")
    drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/Levothyroxine_drugbank_extracted_indications.json"
    
    drugbank_codes = Set{String}()
    
    if isfile(drugbank_file)
        data = JSON3.read(read(drugbank_file, String))
        println("  DrugBank indications:")
        
        for indication in data.indications
            codes = simple_lookup(indication.condition, db)
            union!(drugbank_codes, codes)
        end
    end
    
    println("\n  → DrugBank ICD-10 codes found: $(collect(drugbank_codes))")
    
    # Test MeSH terms
    println("\n📋 MeSH Extractions:")
    mesh_file = "/oscar/home/isarkar/sarkarcode/thera/drug_pubmed_refs/Levothyroxine.json"
    
    mesh_codes = Set{String}()
    
    if isfile(mesh_file)
        try
            include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
            data = JSON3.read(read(mesh_file, String))
            
            if haskey(data, "mesh_summary") && haskey(data.mesh_summary, "mesh_terms")
                disease_terms = [term.descriptor for term in data.mesh_summary.mesh_terms 
                               if haskey(term, "descriptor") && term.descriptor in MESH_T047_HEADINGS]
                
                println("  MeSH disease terms:")
                for descriptor in disease_terms
                    codes = simple_lookup(descriptor, db)
                    union!(mesh_codes, codes)
                end
            end
        catch e
            println("  ❌ Error: $e")
        end
    end
    
    println("\n  → MeSH ICD-10 codes found: $(collect(mesh_codes))")
    
    # Calculate recovery
    println("\n🎯 Recovery Analysis:")
    if !isempty(drugbank_codes)
        intersection = intersect(drugbank_codes, mesh_codes)
        recovery_rate = (length(intersection) / length(drugbank_codes)) * 100
        
        println("  DrugBank codes: $(collect(drugbank_codes))")
        println("  MeSH codes: $(collect(mesh_codes))")
        println("  Intersection: $(collect(intersection))")
        println("  Recovery rate: $(length(intersection))/$(length(drugbank_codes)) = $(round(recovery_rate, digits=1))%")
    else
        println("  No DrugBank codes to compare")
    end
    
    SQLite.close(db)
    
    println("\n✅ Simple test complete!")
end

simple_test()