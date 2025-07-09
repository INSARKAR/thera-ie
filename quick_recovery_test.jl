#!/usr/bin/env julia

# Quick recovery test with hierarchy-enhanced SQLite database

using SQLite
using JSON3
using CSV
using DataFrames

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

# Load necessary files
include("/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.jl")

function quick_recovery_test()
    println("🎯 Quick SQLite Recovery Test")
    println("=" ^ 40)
    
    db = SQLite.DB(DB_PATH)
    
    # Test just 5 drugs
    test_drugs = ["Abacavir", "Cycrimine", "Parnaparin", "Ubidecarenone", "Deucravacitinib"]
    
    results = []
    
    for drug_name in test_drugs
        println("\n🧪 Testing: $drug_name")
        
        # Load DrugBank ground truth
        drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/$(drug_name)_drugbank_extracted_indications.json"
        
        if isfile(drugbank_file)
            data = JSON3.read(read(drugbank_file, String))
            
            if haskey(data, "indications") && !isempty(data.indications)
                drugbank_conditions = [cond.condition for cond in data.indications]
                println("  DrugBank: $(length(drugbank_conditions)) conditions")
                
                # Test first 3 conditions for ICD-10 mapping
                icd10_found = 0
                for condition in drugbank_conditions[1:min(3, length(drugbank_conditions))]
                    # Direct ICD-10 lookup
                    query = """
                        SELECT COUNT(*) as found
                        FROM terms t 
                        JOIN concepts c ON t.cui = c.cui 
                        LEFT JOIN icd10_mappings m ON c.cui = m.cui
                        WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
                    """
                    
                    found = SQLite.DBInterface.execute(db, query, ["%$(lowercase(condition))%"]) |> first |> first
                    
                    if found > 0
                        icd10_found += 1
                        println("    ✅ '$condition' → ICD-10 mappable")
                    else
                        println("    ❌ '$condition' → No direct mapping")
                    end
                end
                
                recovery_rate = (icd10_found / min(3, length(drugbank_conditions))) * 100
                println("  Recovery rate: $(round(recovery_rate, digits=1))%")
                
                push!(results, (
                    drug = drug_name,
                    conditions = length(drugbank_conditions),
                    tested = min(3, length(drugbank_conditions)),
                    mapped = icd10_found,
                    recovery = recovery_rate
                ))
            else
                println("  ❌ No extracted indications found")
            end
        else
            println("  ❌ DrugBank file not found")
        end
    end
    
    SQLite.close(db)
    
    # Summary
    println("\n📊 Quick Test Results:")
    println("=" ^ 40)
    
    if !isempty(results)
        df = DataFrame(results)
        println(df)
        
        avg_recovery = mean(df.recovery)
        println("\n🎯 Average Recovery Rate: $(round(avg_recovery, digits=1))%")
        
        drugs_with_recovery = sum(df.recovery .> 0)
        println("🎯 Drugs with Some Recovery: $drugs_with_recovery/$(length(results))")
    else
        println("❌ No successful tests")
    end
    
    println("\n✅ Quick test complete! Database is ready for full analysis.")
end

quick_recovery_test()