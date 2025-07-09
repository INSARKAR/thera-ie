#!/usr/bin/env julia

"""
Parallel SQLite database builder from UMLS MRCONSO and MRREL files
Uses multiple threads and batch processing for faster performance
"""

using SQLite
using JSON3
using Base.Threads

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
const BATCH_SIZE = 10000

function create_umls_database_parallel(db_path::String="/oscar/data/ursa/umls/2025AA/umls_medical.db")
    """Create SQLite database from UMLS files using parallel processing"""
    
    println("🏗️  Creating UMLS SQLite database (PARALLEL) at: $db_path")
    println("💻 Using $(nthreads()) threads")
    
    # Remove existing database
    if isfile(db_path)
        rm(db_path)
        println("  Removed existing database")
    end
    
    # Create database
    db = SQLite.DB(db_path)
    
    # Create tables
    println("📊 Creating database schema...")
    create_tables(db)
    
    # Step 1: Load semantic types (fast)
    println("📚 Loading semantic types...")
    semantic_types = load_semantic_types()
    
    # Step 2: Process MRCONSO in parallel batches
    println("🔍 Processing MRCONSO in parallel batches...")
    load_concepts_parallel(db, semantic_types)
    
    # Step 3: Load hierarchy
    println("🌳 Loading hierarchy from MRREL...")
    load_hierarchy_parallel(db)
    
    # Step 4: Create indexes
    println("⚡ Creating database indexes...")
    create_indexes(db)
    
    SQLite.close(db)
    
    println("✅ UMLS SQLite database created successfully!")
    println("📊 Database size: $(round(stat(db_path).size / 1024 / 1024, digits=2)) MB")
    
    return db_path
end

function create_tables(db)
    """Create database tables with optimized structure"""
    
    # Disable synchronous writes for speed
    SQLite.execute(db, "PRAGMA synchronous = OFF")
    SQLite.execute(db, "PRAGMA journal_mode = MEMORY")
    SQLite.execute(db, "PRAGMA cache_size = 100000")
    
    # Table 1: All medical concepts (with optional ICD-10 codes)
    SQLite.execute(db, """
        CREATE TABLE concepts (
            cui TEXT PRIMARY KEY,
            preferred_name TEXT,
            semantic_types TEXT,
            has_icd10 INTEGER DEFAULT 0
        )
    """)
    
    # Table 1b: ICD-10 mappings (separate table for multiple codes per CUI)
    SQLite.execute(db, """
        CREATE TABLE icd10_mappings (
            cui TEXT,
            icd10_source TEXT,
            icd10_code TEXT,
            PRIMARY KEY (cui, icd10_source, icd10_code)
        )
    """)
    
    # Table 2: Terms pointing to CUIs
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
end

function load_semantic_types()
    """Load semantic types for each CUI"""
    semantic_types = Dict{String, Set{String}}()
    
    if !isfile(MRSTY_FILE)
        println("⚠️  MRSTY file not found, skipping semantic type filtering")
        return semantic_types
    end
    
    # Read lines into chunks for parallel processing
    lines = readlines(MRSTY_FILE)
    println("    Processing $(length(lines)) semantic type lines...")
    
    # Process in parallel chunks
    chunks = collect(Iterators.partition(lines, div(length(lines), nthreads()) + 1))
    results = Vector{Dict{String, Set{String}}}(undef, length(chunks))
    
    @threads for i in 1:length(chunks)
        local_types = Dict{String, Set{String}}()
        for line in chunks[i]
            fields = split(line, '|')
            if length(fields) >= 2
                cui = fields[1]
                sty = fields[2]
                
                if !haskey(local_types, cui)
                    local_types[cui] = Set{String}()
                end
                push!(local_types[cui], sty)
            end
        end
        results[i] = local_types
    end
    
    # Merge results
    for local_types in results
        for (cui, stypes) in local_types
            if !haskey(semantic_types, cui)
                semantic_types[cui] = Set{String}()
            end
            union!(semantic_types[cui], stypes)
        end
    end
    
    println("    Loaded semantic types for $(length(semantic_types)) CUIs")
    return semantic_types
end

function load_concepts_parallel(db, semantic_types)
    """Load concepts with ICD-10 codes using parallel processing"""
    
    if !isfile(MRCONSO_FILE)
        println("❌ MRCONSO file not found at $MRCONSO_FILE")
        return
    end
    
    println("    Reading MRCONSO file...")
    lines = readlines(MRCONSO_FILE)
    println("    Processing $(length(lines)) MRCONSO lines in parallel...")
    
    # Process lines in parallel chunks
    chunks = collect(Iterators.partition(lines, div(length(lines), nthreads()) + 1))
    
    concept_results = Vector{Dict{String, Dict{String, Any}}}(undef, length(chunks))
    terms_results = Vector{Vector{NamedTuple}}(undef, length(chunks))
    
    @threads for i in 1:length(chunks)
        local_concepts = Dict{String, Dict{String, Any}}()
        local_terms = []
        
        for line in chunks[i]
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
                            if !haskey(local_concepts, cui)
                                local_concepts[cui] = Dict(
                                    "preferred_name" => "",
                                    "icd10_codes" => Dict{String, String}(),
                                    "semantic_types" => cui_stypes
                                )
                            end
                            
                            concept = local_concepts[cui]
                            
                            # Set preferred name
                            if term_status == "P"
                                concept["preferred_name"] = term
                            end
                            
                            # Check if this is an ICD-10 code
                            if source in ICD10_SOURCES
                                actual_code = if occursin("/", code)
                                    split(code, "/")[end]
                                else
                                    code
                                end
                                concept["icd10_codes"][source] = actual_code
                            end
                            
                            # Store term mapping
                            push!(local_terms, (
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
        
        concept_results[i] = local_concepts
        terms_results[i] = local_terms
    end
    
    # Merge concept results
    println("    Merging parallel results...")
    all_concepts = Dict{String, Dict{String, Any}}()
    all_terms = []
    
    for local_concepts in concept_results
        for (cui, concept) in local_concepts
            if !haskey(all_concepts, cui)
                all_concepts[cui] = concept
            else
                # Merge ICD-10 codes
                merge!(all_concepts[cui]["icd10_codes"], concept["icd10_codes"])
                # Use non-empty preferred name
                if isempty(all_concepts[cui]["preferred_name"]) && !isempty(concept["preferred_name"])
                    all_concepts[cui]["preferred_name"] = concept["preferred_name"]
                end
            end
        end
    end
    
    for local_terms in terms_results
        append!(all_terms, local_terms)
    end
    
    println("    Found $(length(all_concepts)) medical concepts")
    
    # Separate concepts with and without ICD-10 codes
    concepts_with_icd10 = filter(p -> !isempty(p.second["icd10_codes"]), all_concepts)
    concepts_without_icd10 = filter(p -> isempty(p.second["icd10_codes"]), all_concepts)
    
    println("    $(length(concepts_with_icd10)) concepts have ICD-10 codes")
    println("    $(length(concepts_without_icd10)) concepts need hierarchy traversal")
    
    # Insert ALL medical concepts in batches
    println("    Inserting all medical concepts in batches...")
    insert_all_concepts_batch(db, all_concepts)
    
    # Insert ALL medical terms (not just ones with ICD-10) for lookups
    println("    Inserting ALL medical terms in batches...")
    medical_cuis = Set(keys(all_concepts))  # All medical concepts, not just ICD-10 ones
    medical_terms = filter(t -> t.cui in medical_cuis, all_terms)
    insert_terms_batch(db, medical_terms)
    
    println("    Inserted $(length(medical_terms)) medical term mappings")
    println("    $(length(filter(t -> t.cui in Set(keys(concepts_with_icd10)), medical_terms))) terms link to ICD-10 concepts")
end

function insert_all_concepts_batch(db, concepts)
    """Insert all medical concepts with separate ICD-10 mappings"""
    
    SQLite.execute(db, "BEGIN TRANSACTION")
    
    concept_count = 0
    icd10_count = 0
    
    for (cui, concept) in concepts
        semantic_types_json = JSON3.write(collect(concept["semantic_types"]))
        has_icd10 = !isempty(concept["icd10_codes"]) ? 1 : 0
        
        # Insert concept
        SQLite.execute(db, """
            INSERT OR REPLACE INTO concepts 
            (cui, preferred_name, semantic_types, has_icd10) 
            VALUES (?, ?, ?, ?)
        """, [cui, concept["preferred_name"], semantic_types_json, has_icd10])
        
        concept_count += 1
        
        # Insert ICD-10 mappings if they exist
        for (icd10_source, icd10_code) in concept["icd10_codes"]
            SQLite.execute(db, """
                INSERT OR REPLACE INTO icd10_mappings 
                (cui, icd10_source, icd10_code) 
                VALUES (?, ?, ?)
            """, [cui, icd10_source, icd10_code])
            
            icd10_count += 1
        end
        
        if concept_count % BATCH_SIZE == 0
            SQLite.execute(db, "COMMIT")
            SQLite.execute(db, "BEGIN TRANSACTION")
            println("      Inserted $concept_count concepts, $icd10_count ICD-10 mappings...")
        end
    end
    
    SQLite.execute(db, "COMMIT")
    println("    Final: $concept_count concepts, $icd10_count ICD-10 mappings")
end

function insert_terms_batch(db, terms)
    """Insert terms in batches for better performance"""
    
    SQLite.execute(db, "BEGIN TRANSACTION")
    
    for (i, term_data) in enumerate(terms)
        SQLite.execute(db, """
            INSERT OR REPLACE INTO terms 
            (term_lower, cui, term_original, is_preferred) 
            VALUES (?, ?, ?, ?)
        """, [term_data.term_lower, term_data.cui, term_data.term_original, term_data.is_preferred])
        
        if i % BATCH_SIZE == 0
            SQLite.execute(db, "COMMIT")
            SQLite.execute(db, "BEGIN TRANSACTION")
            println("      Inserted $i term mappings...")
        end
    end
    
    SQLite.execute(db, "COMMIT")
end

function load_hierarchy_parallel(db)
    """Load hierarchy using parallel processing"""
    
    if !isfile(MRREL_FILE)
        println("⚠️  MRREL file not found, skipping hierarchy")
        return
    end
    
    # Get relevant CUIs (all medical concepts in database)
    relevant_cuis = Set{String}()
    for row in SQLite.DBInterface.execute(db, "SELECT cui FROM concepts")
        push!(relevant_cuis, row.cui)
    end
    
    println("    Loading hierarchy for $(length(relevant_cuis)) relevant CUIs...")
    
    lines = readlines(MRREL_FILE)
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
                
                if rel == "PAR" && suppress != "Y" && 
                   (cui1 in relevant_cuis || cui2 in relevant_cuis)
                    push!(local_hierarchy, (child_cui = cui1, parent_cui = cui2))
                end
            end
        end
        
        hierarchy_results[i] = local_hierarchy
    end
    
    # Merge and insert hierarchy
    all_hierarchy = []
    for local_hierarchy in hierarchy_results
        append!(all_hierarchy, local_hierarchy)
    end
    
    println("    Inserting $(length(all_hierarchy)) hierarchy relationships...")
    
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
end

function create_indexes(db)
    """Create indexes for fast queries"""
    
    # Index for term lookups
    SQLite.execute(db, "CREATE INDEX idx_terms_lower ON terms(term_lower)")
    SQLite.execute(db, "CREATE INDEX idx_terms_cui ON terms(cui)")
    
    # Index for concept lookups
    SQLite.execute(db, "CREATE INDEX idx_concepts_cui ON concepts(cui)")
    SQLite.execute(db, "CREATE INDEX idx_concepts_has_icd10 ON concepts(has_icd10)")
    
    # Index for ICD-10 mappings
    SQLite.execute(db, "CREATE INDEX idx_icd10_cui ON icd10_mappings(cui)")
    SQLite.execute(db, "CREATE INDEX idx_icd10_code ON icd10_mappings(icd10_code)")
    
    # Index for hierarchy traversal
    SQLite.execute(db, "CREATE INDEX idx_hierarchy_child ON hierarchy(child_cui)")
    SQLite.execute(db, "CREATE INDEX idx_hierarchy_parent ON hierarchy(parent_cui)")
    
    println("    Created database indexes")
end

function main()
    println("🏗️  Parallel UMLS SQLite Database Builder")
    println("💻 Available threads: $(nthreads())")
    println("=" ^ 60)
    
    # Check if UMLS files exist
    if !isfile(MRCONSO_FILE)
        println("❌ UMLS files not found at $UMLS_META_DIR")
        println("Please ensure UMLS 2025AA data is available")
        return
    end
    
    # Build database
    db_path = create_umls_database_parallel()
    
    println("\n✅ Parallel UMLS SQLite database ready!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end