#!/usr/bin/env julia

"""
Phase 1 Evaluation: Detailed ICD-10 Mapping Analysis
Creates individual JSON files for each drug with complete ICD-10 concept mappings
"""

using SQLite
using JSON3
using Dates

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"
const RESULTS_DIR = "/oscar/home/isarkar/sarkarcode/thera/phase1_results"

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
    """Extract ICD-10 chapter from code (everything before the dot)"""
    if !isempty(icd10_code)
        # Extract everything before the first dot
        chapter_code = split(icd10_code, '.')[1]
        return uppercase(chapter_code)
    end
    return "Unknown"
end

function extract_medical_terms(text::String)
    """Extract medical terms from condition text using algorithmic approach"""
    # Remove parenthetical information and split
    cleaned_text = replace(text, r"\\([^)]*\\)" => "")
    words = split(lowercase(cleaned_text), r"[^a-zA-Z]+")
    
    # Filter for meaningful medical terms
    medical_terms = []
    excluded_words = Set(["primary", "secondary", "tertiary", "congenital", "acquired", 
                         "therapy", "treatment", "management", "adjunctive", "well", 
                         "differentiated", "dependent", "the", "and", "or", "with", "for",
                         "patients", "adults", "pediatric", "systemic", "moderate", "severe"])
    
    for word in words
        if length(word) > 4 && !(word in excluded_words)
            push!(medical_terms, word)
        end
    end
    
    # Also include the original text for comprehensive matching
    push!(medical_terms, lowercase(strip(text)))
    
    return unique(medical_terms)
end

function lookup_icd10_concepts(term::String, db)
    """Lookup ICD-10 concepts for a medical term with detailed information"""
    
    concepts = []
    
    # Direct term lookup with concept details
    direct_query = """
        SELECT DISTINCT m.icd10_code, c.preferred_name, c.cui, t.term_original
        FROM terms t 
        JOIN concepts c ON t.cui = c.cui 
        JOIN icd10_mappings m ON c.cui = m.cui
        WHERE t.term_lower LIKE ? AND c.has_icd10 = 1
        LIMIT 10
    """
    
    for row in SQLite.DBInterface.execute(db, direct_query, ["%$(lowercase(term))%"])
        if !isnothing(row.icd10_code) && !isempty(row.icd10_code)
            chapter = get_icd10_chapter(row.icd10_code)
            
            push!(concepts, Dict(
                "icd10_code" => row.icd10_code,
                "icd10_chapter" => chapter,
                "preferred_name" => row.preferred_name,
                "cui" => row.cui,
                "matched_term" => row.term_original,
                "search_term" => term,
                "mapping_type" => "direct"
            ))
        end
    end
    
    # If no direct mapping, try hierarchy traversal
    if isempty(concepts)
        cui_query = """
            SELECT DISTINCT t.cui, c.preferred_name, t.term_original
            FROM terms t 
            JOIN concepts c ON t.cui = c.cui
            WHERE t.term_lower LIKE ? AND c.has_icd10 = 0
            LIMIT 3
        """
        
        for row in SQLite.DBInterface.execute(db, cui_query, ["%$(lowercase(term))%"])
            # Find parent concepts with ICD-10 codes
            parent_query = """
                SELECT DISTINCT p.cui, p.preferred_name, m.icd10_code
                FROM hierarchy h
                JOIN concepts p ON h.parent_cui = p.cui
                JOIN icd10_mappings m ON p.cui = m.cui
                WHERE h.child_cui = ? AND p.has_icd10 = 1
                LIMIT 5
            """
            
            for parent_row in SQLite.DBInterface.execute(db, parent_query, [row.cui])
                if !isnothing(parent_row.icd10_code) && !isempty(parent_row.icd10_code)
                    chapter = get_icd10_chapter(parent_row.icd10_code)
                    
                    push!(concepts, Dict(
                        "icd10_code" => parent_row.icd10_code,
                        "icd10_chapter" => chapter,
                        "preferred_name" => parent_row.preferred_name,
                        "cui" => parent_row.cui,
                        "matched_term" => row.term_original,
                        "search_term" => term,
                        "mapping_type" => "hierarchy",
                        "child_concept" => row.preferred_name,
                        "child_cui" => row.cui
                    ))
                end
            end
        end
    end
    
    return concepts
end

function load_drugbank_indications(drug_name::String, db)
    """Load and map DrugBank indications"""
    
    drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/phase1_llama_drugbank_extracted_indications/$(drug_name)_drugbank_extracted_indications.json"
    
    if !isfile(drugbank_file)
        return []
    end
    
    try
        data = JSON3.read(read(drugbank_file, String))
        
        if !haskey(data, "indications") || isempty(data.indications)
            return []
        end
        
        drugbank_concepts = []
        
        for indication in data.indications
            if haskey(indication, "condition")
                condition = indication.condition
                
                # Extract terms and lookup concepts
                terms = extract_medical_terms(condition)
                mapped_concepts = []
                
                for term in terms
                    concepts = lookup_icd10_concepts(term, db)
                    append!(mapped_concepts, concepts)
                end
                
                # Remove duplicates based on ICD-10 code
                unique_concepts = []
                seen_codes = Set()
                for concept in mapped_concepts
                    if !(concept["icd10_code"] in seen_codes)
                        push!(unique_concepts, concept)
                        push!(seen_codes, concept["icd10_code"])
                    end
                end
                
                push!(drugbank_concepts, Dict(
                    "original_condition" => condition,
                    "confidence" => get(indication, "confidence", nothing),
                    "reasoning" => get(indication, "reasoning", nothing),
                    "extracted_terms" => terms,
                    "mapped_concepts" => unique_concepts
                ))
            end
        end
        
        return drugbank_concepts
        
    catch e
        println("Error loading DrugBank data for $drug_name: $e")
        return []
    end
end

function load_mesh_descriptors(drug_name::String, db)
    """Load and map MeSH descriptors"""
    
    mesh_file = "/oscar/home/isarkar/sarkarcode/thera/phase1_drug_pubmed_refs/$(drug_name).json"
    
    if !isfile(mesh_file)
        return []
    end
    
    try
        include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
        
        data = JSON3.read(read(mesh_file, String))
        
        mesh_concepts = []
        
        if haskey(data, "mesh_summary") && haskey(data.mesh_summary, "mesh_terms")
            for mesh_term in data.mesh_summary.mesh_terms
                if haskey(mesh_term, "descriptor") && mesh_term.descriptor in MESH_T047_HEADINGS
                    descriptor = mesh_term.descriptor
                    
                    # Lookup concepts for this descriptor
                    concepts = lookup_icd10_concepts(descriptor, db)
                    
                    push!(mesh_concepts, Dict(
                        "mesh_descriptor" => descriptor,
                        "mesh_id" => get(mesh_term, "mesh_id", nothing),
                        "publications_count" => get(mesh_term, "count", 0),
                        "mapped_concepts" => concepts
                    ))
                end
            end
        end
        
        return mesh_concepts
        
    catch e
        println("Error loading MeSH data for $drug_name: $e")
        return []
    end
end

function load_naive_indications(drug_name::String, db)
    """Load and map Naive LLM indications"""
    
    naive_file = "/oscar/home/isarkar/sarkarcode/thera/phase1_llama_naive_extracted_indications/$(drug_name)_enhanced_naive_extracted_indications.json"
    
    if !isfile(naive_file)
        return []
    end
    
    try
        data = JSON3.read(read(naive_file, String))
        
        naive_concepts = []
        
        if haskey(data, "extracted_indications") && !isempty(data.extracted_indications)
            for indication in data.extracted_indications
                if haskey(indication, "condition")
                    condition = indication.condition
                    
                    # Extract terms and lookup concepts
                    terms = extract_medical_terms(condition)
                    mapped_concepts = []
                    
                    for term in terms
                        concepts = lookup_icd10_concepts(term, db)
                        append!(mapped_concepts, concepts)
                    end
                    
                    # Remove duplicates
                    unique_concepts = []
                    seen_codes = Set()
                    for concept in mapped_concepts
                        if !(concept["icd10_code"] in seen_codes)
                            push!(unique_concepts, concept)
                            push!(seen_codes, concept["icd10_code"])
                        end
                    end
                    
                    push!(naive_concepts, Dict(
                        "original_condition" => condition,
                        "confidence" => get(indication, "confidence", nothing),
                        "reasoning" => get(indication, "reasoning", nothing),
                        "extracted_terms" => terms,
                        "mapped_concepts" => unique_concepts
                    ))
                end
            end
        end
        
        return naive_concepts
        
    catch e
        println("Error loading Naive LLM data for $drug_name: $e")
        return []
    end
end

function load_pubmed_llm_indications(drug_name::String, db)
    """Load and map PubMed LLM indications"""
    
    pubmed_file = "/oscar/home/isarkar/sarkarcode/thera/phase1_llama_pubmed_extracted_indications/$(drug_name)_llama_extracted_indications.json"
    
    if !isfile(pubmed_file)
        return []
    end
    
    try
        data = JSON3.read(read(pubmed_file, String))
        
        pubmed_concepts = []
        
        if haskey(data, "extracted_indications") && !isempty(data.extracted_indications)
            for indication in data.extracted_indications
                if haskey(indication, "condition")
                    condition = indication.condition
                    
                    # Extract terms and lookup concepts
                    terms = extract_medical_terms(condition)
                    mapped_concepts = []
                    
                    for term in terms
                        concepts = lookup_icd10_concepts(term, db)
                        append!(mapped_concepts, concepts)
                    end
                    
                    # Remove duplicates
                    unique_concepts = []
                    seen_codes = Set()
                    for concept in mapped_concepts
                        if !(concept["icd10_code"] in seen_codes)
                            push!(unique_concepts, concept)
                            push!(seen_codes, concept["icd10_code"])
                        end
                    end
                    
                    push!(pubmed_concepts, Dict(
                        "original_condition" => condition,
                        "confidence" => get(indication, "confidence", nothing),
                        "reasoning" => get(indication, "reasoning", nothing),
                        "extracted_terms" => terms,
                        "mapped_concepts" => unique_concepts
                    ))
                end
            end
        end
        
        return pubmed_concepts
        
    catch e
        println("Error loading PubMed LLM data for $drug_name: $e")
        return []
    end
end

function generate_phase1_result(drug_name::String, db)
    """Generate complete Phase 1 result for a drug"""
    
    println("🔍 Processing $drug_name for Phase 1 evaluation...")
    
    # Load all indication sources
    drugbank_indications = load_drugbank_indications(drug_name, db)
    mesh_descriptors = load_mesh_descriptors(drug_name, db)
    naive_indications = load_naive_indications(drug_name, db)
    pubmed_llm_indications = load_pubmed_llm_indications(drug_name, db)
    
    # Create comprehensive result
    result = Dict(
        "metadata" => Dict(
            "drug_name" => drug_name,
            "analysis_type" => "phase1_evaluation",
            "generated_at" => string(now()),
            "umls_database_version" => "2025AA",
            "total_drugbank_indications" => length(drugbank_indications),
            "total_mesh_descriptors" => length(mesh_descriptors),
            "total_naive_indications" => length(naive_indications),
            "total_pubmed_llm_indications" => length(pubmed_llm_indications)
        ),
        "drugbank_indications" => drugbank_indications,
        "mesh_descriptors" => mesh_descriptors,
        "naive_indications" => naive_indications,
        "pubmed_llm_indications" => pubmed_llm_indications
    )
    
    # Save to file
    output_file = joinpath(RESULTS_DIR, "$(drug_name)_result_phase1.json")
    
    open(output_file, "w") do f
        write(f, JSON3.write(result))
    end
    
    println("  ✅ Saved results to: $output_file")
    
    # Print summary
    total_concepts = 0
    for source in [drugbank_indications, mesh_descriptors, naive_indications, pubmed_llm_indications]
        for item in source
            if haskey(item, "mapped_concepts")
                total_concepts += length(item["mapped_concepts"])
            end
        end
    end
    
    println("  📊 Summary:")
    println("    DrugBank indications: $(length(drugbank_indications))")
    println("    MeSH descriptors: $(length(mesh_descriptors))")
    println("    Naive indications: $(length(naive_indications))")
    println("    PubMed LLM indications: $(length(pubmed_llm_indications))")
    println("    Total mapped ICD-10 concepts: $total_concepts")
    
    return result
end

function main()
    println("🎯 Phase 1 Evaluation: Detailed ICD-10 Mapping Analysis")
    println("=" ^ 60)
    
    # Ensure results directory exists
    if !isdir(RESULTS_DIR)
        mkdir(RESULTS_DIR)
        println("📁 Created results directory: $RESULTS_DIR")
    end
    
    # Load database
    println("📊 Loading UMLS SQLite database...")
    db = SQLite.DB(DB_PATH)
    
    # Process specific drug (Levothyroxine for initial focus)
    drug_name = "Levothyroxine"
    
    result = generate_phase1_result(drug_name, db)
    
    SQLite.close(db)
    
    println("\n✅ Phase 1 evaluation complete for $drug_name!")
    println("📁 Results saved in: $RESULTS_DIR")
    
    # Show file location
    result_file = joinpath(RESULTS_DIR, "$(drug_name)_result_phase1.json")
    println("📄 View results: cat $result_file")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end