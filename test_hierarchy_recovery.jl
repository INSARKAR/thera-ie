#!/usr/bin/env julia

using SQLite
using JSON3

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

function test_hierarchy_recovery()
    println("🧪 Testing Hierarchy-Enhanced Recovery")
    println("=" ^ 50)
    
    db = SQLite.DB(DB_PATH)
    
    # Test database stats
    println("\n📊 Database Statistics:")
    concepts = SQLite.DBInterface.execute(db, "SELECT COUNT(*) FROM concepts") |> first |> first
    terms = SQLite.DBInterface.execute(db, "SELECT COUNT(*) FROM terms") |> first |> first
    icd10_mappings = SQLite.DBInterface.execute(db, "SELECT COUNT(*) FROM icd10_mappings") |> first |> first
    hierarchy = SQLite.DBInterface.execute(db, "SELECT COUNT(*) FROM hierarchy") |> first |> first
    
    println("  Concepts: $concepts")
    println("  Terms: $terms")
    println("  ICD-10 mappings: $icd10_mappings")
    println("  Hierarchy relationships: $hierarchy")
    
    # Test hierarchy lookup for a medical term
    println("\n🔍 Testing term lookup with hierarchy:")
    test_terms = ["hypothyroidism", "diabetes", "hypertension", "heart failure"]
    
    for term in test_terms
        println("\n  Testing: '$term'")
        
        # Direct lookup
        direct_query = """
            SELECT t.cui, c.preferred_name, m.icd10_code 
            FROM terms t 
            JOIN concepts c ON t.cui = c.cui 
            LEFT JOIN icd10_mappings m ON c.cui = m.cui
            WHERE t.term_lower = ? AND c.has_icd10 = 1
            LIMIT 2
        """
        
        direct_results = []
        for row in SQLite.DBInterface.execute(db, direct_query, [term])
            push!(direct_results, (row.cui, row.preferred_name, row.icd10_code))
        end
        
        if !isempty(direct_results)
            println("    ✅ Direct ICD-10 found:")
            for (cui, name, code) in direct_results
                println("      $name → $code")
            end
        else
            println("    ❌ No direct ICD-10 found")
            
            # Try hierarchy traversal
            cui_query = """
                SELECT DISTINCT t.cui, c.preferred_name
                FROM terms t 
                JOIN concepts c ON t.cui = c.cui
                WHERE t.term_lower = ? AND c.has_icd10 = 0
                LIMIT 1
            """
            
            for row in SQLite.DBInterface.execute(db, cui_query, [term])
                println("    🌳 Trying hierarchy for: $(row.preferred_name)")
                
                # Find parents with ICD-10 codes
                parent_query = """
                    SELECT DISTINCT p.cui, p.preferred_name, m.icd10_code
                    FROM hierarchy h
                    JOIN concepts p ON h.parent_cui = p.cui
                    LEFT JOIN icd10_mappings m ON p.cui = m.cui
                    WHERE h.child_cui = ? AND p.has_icd10 = 1
                    LIMIT 3
                """
                
                hierarchy_found = false
                for parent_row in SQLite.DBInterface.execute(db, parent_query, [row.cui])
                    if !hierarchy_found
                        println("    ✅ Parent ICD-10 found via hierarchy:")
                        hierarchy_found = true
                    end
                    println("      $(parent_row.preferred_name) → $(parent_row.icd10_code)")
                end
                
                if !hierarchy_found
                    println("    ❌ No parent ICD-10 codes found")
                end
            end
        end
    end
    
    # Test with actual extraction data
    println("\n🎯 Testing with real extraction data:")
    
    # Check a few drugs
    test_drugs = ["Levothyroxine", "Metformin", "Cycrimine"]
    
    for drug in test_drugs
        println("\n  Testing drug: $drug")
        
        # Load DrugBank ground truth
        drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/$(drug)_drugbank_extracted_indications.json"
        
        if isfile(drugbank_file)
            data = JSON3.read(read(drugbank_file, String))
            if haskey(data, "extracted_indications") && !isempty(data.extracted_indications)
                conditions = [cond.condition for cond in data.extracted_indications]
                println("    DrugBank conditions: $(length(conditions))")
                
                # Test first few conditions
                for (i, condition) in enumerate(conditions[1:min(3, length(conditions))])
                    println("      Testing: '$condition'")
                    
                    # Quick lookup
                    lookup_query = """
                        SELECT COUNT(*) as found
                        FROM terms t 
                        JOIN concepts c ON t.cui = c.cui 
                        WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
                    """
                    
                    found = SQLite.DBInterface.execute(db, lookup_query, ["%$(lowercase(condition))%"]) |> first |> first
                    
                    if found > 0
                        println("        ✅ ICD-10 mappable")
                    else
                        println("        ❌ No direct mapping")
                    end
                end
            end
        else
            println("    ❌ DrugBank file not found")
        end
    end
    
    SQLite.close(db)
    
    println("\n✅ Hierarchy testing complete!")
end

test_hierarchy_recovery()