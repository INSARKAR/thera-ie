#!/usr/bin/env julia

using SQLite
using JSON3

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

function quick_icd10_lookup(term::String, db)
    """Quick ICD-10 lookup for a medical term"""
    codes = Set{String}()
    
    query = """
        SELECT DISTINCT m.icd10_code
        FROM terms t 
        JOIN concepts c ON t.cui = c.cui 
        JOIN icd10_mappings m ON c.cui = m.cui
        WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
        LIMIT 5
    """
    
    for row in SQLite.DBInterface.execute(db, query, ["%$(lowercase(term))%"])
        if !isnothing(row.icd10_code) && !isempty(row.icd10_code)
            push!(codes, row.icd10_code)
        end
    end
    
    return codes
end

function demo_recovery()
    println("🎯 DEMO: Recovery Analysis Concept")
    println("=" ^ 40)
    
    db = SQLite.DB(DB_PATH)
    
    # Simulated ground truth (DrugBank)
    println("📋 Ground Truth (DrugBank): Levothyroxine treats...")
    ground_truth_terms = ["hypothyroidism", "thyroid cancer"]
    ground_truth_codes = Set{String}()
    
    for term in ground_truth_terms
        codes = quick_icd10_lookup(term, db)
        println("  '$term' → $(collect(codes))")
        union!(ground_truth_codes, codes)
    end
    
    println("\n→ Ground Truth ICD-10 codes: $(collect(ground_truth_codes))")
    
    # Simulated MeSH extraction
    println("\n📋 MeSH Extraction found...")
    mesh_terms = ["hypothyroidism", "thyroid diseases"]  # What MeSH might find
    mesh_codes = Set{String}()
    
    for term in mesh_terms
        codes = quick_icd10_lookup(term, db)
        println("  '$term' → $(collect(codes))")
        union!(mesh_codes, codes)
    end
    
    println("\n→ MeSH ICD-10 codes: $(collect(mesh_codes))")
    
    # Simulated Naive LLM extraction
    println("\n📋 Naive LLM Extraction found...")
    naive_terms = ["thyroid problems"]  # What naive LLM might find
    naive_codes = Set{String}()
    
    for term in naive_terms
        codes = quick_icd10_lookup(term, db)
        println("  '$term' → $(collect(codes))")
        union!(naive_codes, codes)
    end
    
    println("\n→ Naive LLM ICD-10 codes: $(collect(naive_codes))")
    
    # Simulated PubMed LLM extraction
    println("\n📋 PubMed LLM Extraction found...")
    pubmed_terms = ["hypothyroidism", "thyroid neoplasm"]  # What PubMed LLM might find
    pubmed_codes = Set{String}()
    
    for term in pubmed_terms
        codes = quick_icd10_lookup(term, db)
        println("  '$term' → $(collect(codes))")
        union!(pubmed_codes, codes)
    end
    
    println("\n→ PubMed LLM ICD-10 codes: $(collect(pubmed_codes))")
    
    # Calculate Recovery Rates
    println("\n🎯 RECOVERY ANALYSIS:")
    println("=" ^ 25)
    
    function calc_recovery(method_name, method_codes)
        if isempty(ground_truth_codes)
            return 0.0
        end
        
        intersection = intersect(ground_truth_codes, method_codes)
        recovery = (length(intersection) / length(ground_truth_codes)) * 100
        
        println("$method_name Recovery:")
        println("  Ground Truth: $(collect(ground_truth_codes))")
        println("  Extracted:    $(collect(method_codes))")
        println("  Intersection: $(collect(intersection))")
        println("  Recovery:     $(length(intersection))/$(length(ground_truth_codes)) = $(round(recovery, digits=1))%")
        println()
        
        return recovery
    end
    
    mesh_recovery = calc_recovery("MeSH", mesh_codes)
    naive_recovery = calc_recovery("Naive LLM", naive_codes)
    pubmed_recovery = calc_recovery("PubMed LLM", pubmed_codes)
    
    # Summary
    println("🏆 SUMMARY:")
    println("  MeSH Recovery:      $(round(mesh_recovery, digits=1))%")
    println("  Naive LLM Recovery: $(round(naive_recovery, digits=1))%")
    println("  PubMed LLM Recovery: $(round(pubmed_recovery, digits=1))%")
    
    SQLite.close(db)
    
    println("\n✅ This demonstrates how we measure recovery rates!")
    println("   Higher % = method recovers more DrugBank ground truth")
end

demo_recovery()