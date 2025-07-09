#!/usr/bin/env julia

"""
Add hierarchy relationships to existing UMLS SQLite database
"""

using SQLite
using Base.Threads

# UMLS file paths
const UMLS_META_DIR = "/oscar/data/ursa/umls/2025AA/META"
const MRREL_FILE = joinpath(UMLS_META_DIR, "MRREL.RRF")
const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"
const BATCH_SIZE = 10000

function add_hierarchy_to_database()
    """Add hierarchy relationships to existing database"""
    
    println("🌳 Adding hierarchy to existing UMLS database...")
    
    if !isfile(DB_PATH)
        println("❌ Database not found at $DB_PATH")
        return
    end
    
    if !isfile(MRREL_FILE)
        println("❌ MRREL file not found at $MRREL_FILE")
        return
    end
    
    # Open database
    db = SQLite.DB(DB_PATH)
    
    # Check if hierarchy table exists and is empty
    try
        hierarchy_count = SQLite.DBInterface.execute(db, "SELECT COUNT(*) FROM hierarchy") |> first |> first
        if hierarchy_count > 0
            println("✅ Hierarchy already exists ($hierarchy_count relationships)")
            SQLite.close(db)
            return
        end
    catch e
        println("❌ Hierarchy table not found: $e")
        SQLite.close(db)
        return
    end
    
    # Get relevant CUIs (all medical concepts in database)
    println("📊 Loading medical CUIs from database...")
    relevant_cuis = Set{String}()
    for row in SQLite.DBInterface.execute(db, "SELECT cui FROM concepts")
        push!(relevant_cuis, row.cui)
    end
    
    println("    Found $(length(relevant_cuis)) medical CUIs")
    
    # Load and process MRREL in parallel
    println("🔍 Processing MRREL hierarchy relationships...")
    lines = readlines(MRREL_FILE)
    println("    Processing $(length(lines)) MRREL lines...")
    
    # Process lines in parallel chunks
    chunks = collect(Iterators.partition(lines, div(length(lines), nthreads()) + 1))
    hierarchy_results = Vector{Vector{NamedTuple}}(undef, length(chunks))
    
    @threads for i in 1:length(chunks)
        local_hierarchy = []
        
        for line in chunks[i]
            fields = split(line, '|')
            if length(fields) >= 15
                cui1 = fields[1]  # child
                rel = fields[4]
                cui2 = fields[5]  # parent
                suppress = fields[15]
                
                # Only process parent relationships that are not suppressed
                # and involve our relevant CUIs
                if rel == "PAR" && suppress != "Y" && 
                   (cui1 in relevant_cuis || cui2 in relevant_cuis)
                    push!(local_hierarchy, (child_cui = cui1, parent_cui = cui2))
                end
            end
        end
        
        hierarchy_results[i] = local_hierarchy
    end
    
    # Merge results
    all_hierarchy = []
    for local_hierarchy in hierarchy_results
        append!(all_hierarchy, local_hierarchy)
    end
    
    println("    Found $(length(all_hierarchy)) relevant hierarchy relationships")
    
    # Insert hierarchy in batches
    println("💾 Inserting hierarchy relationships...")
    
    SQLite.execute(db, "BEGIN TRANSACTION")
    for (i, hierarchy) in enumerate(all_hierarchy)
        SQLite.execute(db, """
            INSERT OR REPLACE INTO hierarchy (child_cui, parent_cui) 
            VALUES (?, ?)
        """, [hierarchy.child_cui, hierarchy.parent_cui])
        
        if i % BATCH_SIZE == 0
            SQLite.execute(db, "COMMIT")
            SQLite.execute(db, "BEGIN TRANSACTION")
            println("      Inserted $i hierarchy relationships...")
        end
    end
    SQLite.execute(db, "COMMIT")
    
    # Create hierarchy indexes if they don't exist
    println("⚡ Creating hierarchy indexes...")
    try
        SQLite.execute(db, "CREATE INDEX IF NOT EXISTS idx_hierarchy_child ON hierarchy(child_cui)")
        SQLite.execute(db, "CREATE INDEX IF NOT EXISTS idx_hierarchy_parent ON hierarchy(parent_cui)")
        println("    Created hierarchy indexes")
    catch e
        println("    Indexes may already exist: $e")
    end
    
    SQLite.close(db)
    
    println("✅ Hierarchy addition complete!")
    println("📊 Added $(length(all_hierarchy)) hierarchy relationships")
    
    return length(all_hierarchy)
end

function test_hierarchy()
    """Test hierarchy functionality"""
    
    println("\n🧪 Testing hierarchy functionality...")
    
    db = SQLite.DB(DB_PATH)
    
    # Test hierarchy count
    hierarchy_count = SQLite.DBInterface.execute(db, "SELECT COUNT(*) FROM hierarchy") |> first |> first
    println("  Hierarchy relationships: $hierarchy_count")
    
    # Test a sample hierarchy lookup
    println("\n  Sample hierarchy traversal:")
    sample_query = """
        SELECT h.child_cui, h.parent_cui, c1.preferred_name as child_name, c2.preferred_name as parent_name
        FROM hierarchy h
        LEFT JOIN concepts c1 ON h.child_cui = c1.cui
        LEFT JOIN concepts c2 ON h.parent_cui = c2.cui
        WHERE c1.preferred_name IS NOT NULL AND c2.preferred_name IS NOT NULL
        LIMIT 3
    """
    
    for row in SQLite.DBInterface.execute(db, sample_query)
        println("    $(row.child_name) → $(row.parent_name)")
    end
    
    SQLite.close(db)
end

function main()
    println("🌳 UMLS Hierarchy Addition Tool")
    println("=" ^ 50)
    
    # Add hierarchy
    hierarchy_count = add_hierarchy_to_database()
    
    if hierarchy_count > 0
        # Test hierarchy
        test_hierarchy()
        
        println("\n🎯 Hierarchy ready for recovery analysis!")
        println("   Now terms without direct ICD-10 codes can use parent traversal")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end