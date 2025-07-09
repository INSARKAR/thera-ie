#!/usr/bin/env julia

"""
Build SQLite database from UMLS MRCONSO and MRREL files for fast lookups
"""

using SQLite
using JSON3

# UMLS file paths
const UMLS_META_DIR = "/oscar/data/ursa/umls/2025AA/META"
const MRCONSO_FILE = joinpath(UMLS_META_DIR, "MRCONSO.RRF")
const MRREL_FILE = joinpath(UMLS_META_DIR, "MRREL.RRF")
const MRSTY_FILE = joinpath(UMLS_META_DIR, "MRSTY.RRF")

# Medical semantic types we care about
const MEDICAL_SEMANTIC_TYPES = Set([
    "T047",  # Disease or Syndrome
    "T048",  # Mental or Behavioral Dysfunction
    "T049",  # Cell or Molecular Dysfunction
    "T050",  # Experimental Model of Disease
    "T033",  # Finding
    "T046",  # Pathologic Function
    "T184",  # Sign or Symptom
    "T191",  # Neoplastic Process
    "T037",  # Injury or Poisoning
    "T190",  # Anatomical Abnormality
    "T019",  # Congenital Abnormality
])

const ICD10_SOURCES = ["ICD10", "ICD10CM", "ICD10AM", "ICD10AMAE"]

function create_umls_database(db_path::String="/oscar/data/ursa/umls/2025AA/umls_medical.db")
    """Create SQLite database from UMLS files"""
    
    println("🏗️  Creating UMLS SQLite database at: $db_path")
    
    # Remove existing database
    if isfile(db_path)
        rm(db_path)
        println("  Removed existing database")
    end
    
    # Create database
    db = SQLite.DB(db_path)
    
    # Create tables
    println("📊 Creating database schema...")
    
    # Table 1: Concepts with ICD-10 codes
    SQLite.execute(db, """
        CREATE TABLE concepts (
            cui TEXT,
            preferred_name TEXT,
            icd10_source TEXT,
            icd10_code TEXT,
            semantic_types TEXT,
            PRIMARY KEY (cui, icd10_source)
        )
    """)
    
    # Table 2: Terms (synonyms) pointing to CUIs
    SQLite.execute(db, """
        CREATE TABLE terms (
            term_lower TEXT,
            cui TEXT,
            term_original TEXT,
            is_preferred INTEGER,
            PRIMARY KEY (term_lower, cui)
        )
    """)
    
    # Table 3: Hierarchy relationships
    SQLite.execute(db, """
        CREATE TABLE hierarchy (
            child_cui TEXT,
            parent_cui TEXT,
            PRIMARY KEY (child_cui, parent_cui)
        )
    """)
    
    # Step 1: Load semantic types
    println("📚 Loading semantic types...")
    semantic_types = load_semantic_types()
    
    # Step 2: Load concepts with ICD-10 codes
    println("🔍 Processing MRCONSO for medical concepts with ICD-10 codes...")
    load_concepts_with_icd10(db, semantic_types)
    
    # Step 3: Load hierarchy
    println("🌳 Loading hierarchy from MRREL...")
    load_hierarchy(db)
    
    # Step 4: Create indexes for fast queries
    println("⚡ Creating database indexes...")
    create_indexes(db)
    
    SQLite.close(db)
    
    println("✅ UMLS SQLite database created successfully!")
    println("📊 Database size: $(round(stat(db_path).size / 1024 / 1024, digits=2)) MB")
    
    return db_path
end

function load_semantic_types()
    """Load semantic types for each CUI"""
    semantic_types = Dict{String, Set{String}}()
    
    if !isfile(MRSTY_FILE)
        println("⚠️  MRSTY file not found, skipping semantic type filtering")
        return semantic_types
    end
    
    open(MRSTY_FILE, "r") do file
        for (i, line) in enumerate(eachline(file))
            if i % 500000 == 0
                println("    Processed $i semantic type lines...")
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
    
    println("    Loaded semantic types for $(length(semantic_types)) CUIs")
    return semantic_types
end

function load_concepts_with_icd10(db, semantic_types)
    """Load concepts that have ICD-10 codes and are medical"""
    
    if !isfile(MRCONSO_FILE)
        println("❌ MRCONSO file not found at $MRCONSO_FILE")
        return
    end
    
    concept_data = Dict{String, Dict{String, Any}}()
    terms_data = []
    
    open(MRCONSO_FILE, "r") do file
        for (i, line) in enumerate(eachline(file))
            if i % 1000000 == 0
                println("    Processed $i MRCONSO lines...")
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
                            
                            # Initialize concept if not exists
                            if !haskey(concept_data, cui)
                                concept_data[cui] = Dict(
                                    "preferred_name" => "",
                                    "icd10_codes" => Dict{String, String}(),
                                    "semantic_types" => cui_stypes
                                )
                            end
                            
                            concept = concept_data[cui]
                            
                            # Set preferred name
                            if term_status == "P"
                                concept["preferred_name"] = term
                            end
                            
                            # Check if this is an ICD-10 code
                            if source in ICD10_SOURCES
                                # Extract actual code from URL if needed
                                actual_code = if occursin("/", code)
                                    split(code, "/")[end]
                                else
                                    code
                                end
                                concept["icd10_codes"][source] = actual_code
                            end
                            
                            # Store term mapping
                            push!(terms_data, (
                                term_lower = lowercase(strip(term)),
                                cui = cui,
                                term_original = term,
                                is_preferred = (term_status == "P") ? 1 : 0
                            ))
                        end
                    end
                end
            end
        end
    end
    
    println("    Found $(length(concept_data)) medical concepts")
    
    # Filter to only concepts with ICD-10 codes
    concepts_with_icd10 = filter(p -> !isempty(p.second["icd10_codes"]), concept_data)
    println("    $(length(concepts_with_icd10)) concepts have ICD-10 codes")
    
    # Insert concepts into database
    println("    Inserting concepts into database...")
    for (cui, concept) in concepts_with_icd10
        semantic_types_json = JSON3.write(collect(concept["semantic_types"]))
        
        for (icd10_source, icd10_code) in concept["icd10_codes"]
            SQLite.execute(db, """
                INSERT OR REPLACE INTO concepts 
                (cui, preferred_name, icd10_source, icd10_code, semantic_types) 
                VALUES (?, ?, ?, ?, ?)
            """, [cui, concept["preferred_name"], icd10_source, icd10_code, semantic_types_json])
        end
    end
    
    # Insert terms for concepts with ICD-10 codes
    println("    Inserting terms into database...")
    concepts_with_icd10_set = Set(keys(concepts_with_icd10))
    relevant_terms = filter(t -> t.cui in concepts_with_icd10_set, terms_data)
    
    for term_data in relevant_terms
        SQLite.execute(db, """
            INSERT OR REPLACE INTO terms 
            (term_lower, cui, term_original, is_preferred) 
            VALUES (?, ?, ?, ?)
        """, [term_data.term_lower, term_data.cui, term_data.term_original, term_data.is_preferred])
    end
    
    println("    Inserted $(length(relevant_terms)) term mappings")
end

function load_hierarchy(db)
    """Load parent-child relationships for hierarchy traversal"""
    
    if !isfile(MRREL_FILE)
        println("⚠️  MRREL file not found, skipping hierarchy")
        return
    end
    
    # Get CUIs that are in our database
    relevant_cuis = Set{String}()
    for row in SQLite.Query(db, "SELECT DISTINCT cui FROM concepts")
        push!(relevant_cuis, row.cui)
    end
    
    println("    Loading hierarchy for $(length(relevant_cuis)) relevant CUIs...")
    
    hierarchy_data = []
    
    open(MRREL_FILE, "r") do file
        for (i, line) in enumerate(eachline(file))
            if i % 1000000 == 0
                println("      Processed $i MRREL lines...")
            end
            
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
                    push!(hierarchy_data, (child_cui = cui1, parent_cui = cui2))
                end
            end
        end
    end
    
    println("    Inserting $(length(hierarchy_data)) hierarchy relationships...")
    
    for hierarchy in hierarchy_data
        SQLite.execute(db, """
            INSERT OR REPLACE INTO hierarchy (child_cui, parent_cui) 
            VALUES (?, ?)
        """, [hierarchy.child_cui, hierarchy.parent_cui])
    end
end

function create_indexes(db)
    """Create indexes for fast queries"""
    
    # Index for term lookups
    SQLite.execute(db, "CREATE INDEX idx_terms_lower ON terms(term_lower)")
    SQLite.execute(db, "CREATE INDEX idx_terms_cui ON terms(cui)")
    
    # Index for concept lookups
    SQLite.execute(db, "CREATE INDEX idx_concepts_cui ON concepts(cui)")
    
    # Index for hierarchy traversal
    SQLite.execute(db, "CREATE INDEX idx_hierarchy_child ON hierarchy(child_cui)")
    SQLite.execute(db, "CREATE INDEX idx_hierarchy_parent ON hierarchy(parent_cui)")
    
    println("    Created database indexes")
end

function test_database(db_path::String="/oscar/data/ursa/umls/2025AA/umls_medical.db")
    """Test the created database with some sample queries"""
    
    if !isfile(db_path)
        println("❌ Database not found at $db_path")
        return
    end
    
    println("\n🧪 Testing UMLS SQLite database...")
    
    db = SQLite.DB(db_path)
    
    # Test 1: Search for "hypothyroidism"
    println("\n1. Searching for 'hypothyroidism':")
    for row in SQLite.Query(db, """
        SELECT t.cui, c.preferred_name, c.icd10_source, c.icd10_code 
        FROM terms t 
        JOIN concepts c ON t.cui = c.cui 
        WHERE t.term_lower LIKE '%hypothyroid%' 
        LIMIT 5
    """)
        println("  $(row.cui): $(row.preferred_name) -> $(row.icd10_source): $(row.icd10_code)")
    end
    
    # Test 2: Get hierarchy for a CUI
    println("\n2. Testing hierarchy traversal:")
    for row in SQLite.Query(db, """
        SELECT child_cui, parent_cui 
        FROM hierarchy 
        WHERE child_cui LIKE 'C00%' 
        LIMIT 5
    """)
        println("  $(row.child_cui) -> $(row.parent_cui)")
    end
    
    # Test 3: Database statistics
    println("\n3. Database statistics:")
    
    concepts_count = SQLite.Query(db, "SELECT COUNT(DISTINCT cui) as count FROM concepts") |> first
    println("  Concepts with ICD-10: $(concepts_count.count)")
    
    terms_count = SQLite.Query(db, "SELECT COUNT(*) as count FROM terms") |> first
    println("  Term mappings: $(terms_count.count)")
    
    hierarchy_count = SQLite.Query(db, "SELECT COUNT(*) as count FROM hierarchy") |> first
    println("  Hierarchy relationships: $(hierarchy_count.count)")
    
    icd10_count = SQLite.Query(db, "SELECT COUNT(*) as count FROM concepts") |> first
    println("  ICD-10 mappings: $(icd10_count.count)")
    
    SQLite.close(db)
end

function main()
    println("🏗️  UMLS SQLite Database Builder")
    println("=" ^ 50)
    
    # Check if UMLS files exist
    if !isfile(MRCONSO_FILE)
        println("❌ UMLS files not found at $UMLS_META_DIR")
        println("Please ensure UMLS 2025AA data is available")
        return
    end
    
    # Build database
    db_path = create_umls_database()
    
    # Test database
    test_database(db_path)
    
    println("\n✅ UMLS SQLite database ready for fast lookups!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end