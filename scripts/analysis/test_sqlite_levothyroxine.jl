#!/usr/bin/env julia

using SQLite
using JSON3

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

function test_sqlite_database()
    println("🧪 Testing SQLite database with Levothyroxine")
    
    if !isfile(DB_PATH)
        println("❌ Database not found")
        return
    end
    
    db = SQLite.DB(DB_PATH)
    
    # Test 1: Check database contents
    println("\n1. Database statistics:")
    
    concepts_count = SQLite.DBInterface.execute(db, "SELECT COUNT(*) as count FROM concepts") |> first
    println("  Concepts: $(concepts_count.count)")
    
    terms_count = SQLite.DBInterface.execute(db, "SELECT COUNT(*) as count FROM terms") |> first
    println("  Terms: $(terms_count.count)")
    
    # Test 2: Search for hypothyroidism
    println("\n2. Searching for 'hypothyroidism':")
    
    for row in SQLite.DBInterface.execute(db, """
        SELECT t.cui, c.preferred_name, c.icd10_source, c.icd10_code 
        FROM terms t 
        JOIN concepts c ON t.cui = c.cui 
        WHERE t.term_lower LIKE '%hypothyroid%' 
        LIMIT 5
    """)
        println("  $(row.cui): $(row.preferred_name) -> $(row.icd10_source): $(row.icd10_code)")
    end
    
    # Test 3: Check if DrugBank LLM file exists for Levothyroxine
    println("\n3. Checking DrugBank LLM extraction file:")
    drugbank_file = "../../llama_drugbank_extracted_indications/Levothyroxine_drugbank_extracted_indications.json"
    println("  File: $drugbank_file")
    println("  Exists: $(isfile(drugbank_file))")
    
    if isfile(drugbank_file)
        data = JSON3.read(read(drugbank_file, String))
        if haskey(data, "indications")
            confirmed = filter(ind -> get(ind, "confirmed", false), data["indications"])
            println("  Confirmed indications: $(length(confirmed))")
            
            for (i, indication) in enumerate(confirmed)
                condition = get(indication, "condition", "")
                println("    $i. $condition")
                
                # Test search for this condition
                println("      Searching database for: '$condition'")
                found_any = false
                
                for row in SQLite.DBInterface.execute(db, """
                    SELECT t.cui, c.preferred_name, c.icd10_source, c.icd10_code 
                    FROM terms t 
                    JOIN concepts c ON t.cui = c.cui 
                    WHERE t.term_lower LIKE ?
                    LIMIT 2
                """, ["%$(lowercase(condition))%"])
                    println("        Found: $(row.cui) - $(row.preferred_name) -> $(row.icd10_code)")
                    found_any = true
                end
                
                if !found_any
                    println("        ❌ No matches found in database")
                end
            end
        end
    end
    
    SQLite.close(db)
end

test_sqlite_database()