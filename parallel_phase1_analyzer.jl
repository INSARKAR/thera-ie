#!/usr/bin/env julia

"""
Parallel Phase 1 Evaluation with Multi-threading and Optimizations
"""

using SQLite
using JSON3
using Dates
using Base.Threads

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"
const RESULTS_DIR = "/oscar/home/isarkar/sarkarcode/thera/results_phase1"

# Thread-local database connections
const thread_dbs = Vector{SQLite.DB}(undef, nthreads())

function get_icd10_chapter(icd10_code::String)
    return !isempty(icd10_code) ? uppercase(split(icd10_code, '.')[1]) : "Unknown"
end

function setup_thread_dbs()
    """Setup separate database connections for each thread"""
    @threads for i in 1:nthreads()
        thread_dbs[i] = SQLite.DB(DB_PATH)
        # Optimize each connection
        SQLite.execute(thread_dbs[i], "PRAGMA journal_mode = WAL")
        SQLite.execute(thread_dbs[i], "PRAGMA synchronous = NORMAL") 
        SQLite.execute(thread_dbs[i], "PRAGMA cache_size = 50000")  # 50MB per thread
        SQLite.execute(thread_dbs[i], "PRAGMA temp_store = MEMORY")
    end
    println("✅ Setup $(nthreads()) thread-local database connections")
end

function get_thread_db()
    """Get database connection for current thread"""
    return thread_dbs[threadid()]
end

function fast_lookup_batch_parallel(terms::Vector{String})
    """Parallel batch lookup using thread-local database"""
    if isempty(terms)
        return []
    end
    
    db = get_thread_db()
    like_conditions = join(["term_lower LIKE ?" for _ in terms], " OR ")
    
    query = """
        SELECT DISTINCT 
            icd10_code,
            icd10_chapter,
            preferred_name,
            cui,
            term_lower
        FROM fast_icd10_lookup
        WHERE $like_conditions
        LIMIT 200
    """
    
    search_terms = ["%$(lowercase(term))%" for term in terms]
    concepts = []
    
    try
        for row in SQLite.DBInterface.execute(db, query, search_terms)
            push!(concepts, Dict(
                "icd10_code" => row.icd10_code,
                "icd10_chapter" => row.icd10_chapter,
                "preferred_name" => row.preferred_name,
                "cui" => row.cui,
                "matched_term" => row.term_lower
            ))
        end
    catch e
        println("    Thread $(threadid()) query error: $e")
    end
    
    return concepts
end

function extract_smart_terms(text::String)
    """Fast term extraction with medical focus"""
    cleaned = replace(text, r"\([^)]*\)" => "")
    cleaned = replace(cleaned, r"\b(primary|secondary|tertiary|congenital|acquired|well-differentiated|dependent)\b" => "", count=10)
    
    words = split(lowercase(cleaned), r"[^a-zA-Z]+")
    excluded = Set(["therapy", "treatment", "management", "adjunctive", "patients", "adults", "pediatric", "systemic", "moderate", "severe", "with", "for", "the", "and", "or"])
    
    terms = [String(word) for word in words if length(word) > 4 && !(word in excluded)]
    push!(terms, lowercase(strip(text)))
    
    return unique(terms)[1:min(5, length(unique(terms)))]
end

function process_indications_parallel(indications_data, section_name::String)
    """Process indications in parallel with thread-safe operations"""
    println("📋 Processing $section_name ($(length(indications_data)) items) with $(nthreads()) threads...")
    
    # Pre-allocate results array
    results = Vector{Dict}(undef, length(indications_data))
    
    # Process in parallel
    @threads for i in 1:length(indications_data)
        indication = indications_data[i]
        
        # Extract condition based on data structure
        condition = if haskey(indication, "condition")
            indication.condition
        elseif haskey(indication, "disease") 
            indication.disease
        elseif haskey(indication, "descriptor")
            indication.descriptor
        else
            string(indication)
        end
        
        terms = extract_smart_terms(string(condition))
        concepts = fast_lookup_batch_parallel(terms)
        
        # Remove duplicates by ICD code
        unique_concepts = []
        seen_codes = Set{String}()
        for concept in concepts
            code = concept["icd10_code"]
            if !(code in seen_codes)
                push!(unique_concepts, concept)
                push!(seen_codes, code)
            end
        end
        
        results[i] = Dict(
            "original_condition" => string(condition),
            "extracted_terms" => terms,
            "mapped_concepts" => unique_concepts,
            "source_data" => Dict(
                "confidence" => get(indication, "confidence", nothing),
                "reasoning" => get(indication, "reasoning", nothing),
                "extraction_method" => section_name,
                "thread_id" => threadid()
            )
        )
        
        if i % 10 == 0
            println("  Thread $(threadid()): processed $i/$(length(indications_data))")
        end
    end
    
    return results
end

function analyze_overlap_parallel(naive_data, pubmed_data)
    """Parallel overlap analysis between methods"""
    println("🔍 Analyzing overlap with parallel processing...")
    
    # Pre-compute ICD mappings for faster lookup
    naive_icd_map = Dict()
    pubmed_icd_map = Dict()
    
    @threads for item in naive_data
        codes = Set([concept["icd10_code"] for concept in item["mapped_concepts"]])
        chapters = Set([concept["icd10_chapter"] for concept in item["mapped_concepts"]])
        naive_icd_map[item["original_condition"]] = (codes, chapters)
    end
    
    @threads for item in pubmed_data
        codes = Set([concept["icd10_code"] for concept in item["mapped_concepts"]])
        chapters = Set([concept["icd10_chapter"] for concept in item["mapped_concepts"]])
        pubmed_icd_map[item["original_condition"]] = (codes, chapters)
    end
    
    # Parallel overlap detection
    overlaps = Vector{Dict}(undef, length(naive_data))
    unique_naive = []
    
    @threads for i in 1:length(naive_data)
        naive_item = naive_data[i]
        naive_condition = naive_item["original_condition"]
        naive_codes, naive_chapters = naive_icd_map[naive_condition]
        
        overlapping_pubmed = []
        found_overlap = false
        
        for (pubmed_condition, (pubmed_codes, pubmed_chapters)) in pubmed_icd_map
            if !isempty(intersect(naive_codes, pubmed_codes)) || !isempty(intersect(naive_chapters, pubmed_chapters))
                found_overlap = true
                push!(overlapping_pubmed, Dict(
                    "pubmed_condition" => pubmed_condition,
                    "shared_codes" => collect(intersect(naive_codes, pubmed_codes)),
                    "shared_chapters" => collect(intersect(naive_chapters, pubmed_chapters))
                ))
            end
        end
        
        if found_overlap
            overlaps[i] = Dict(
                "naive_condition" => naive_condition,
                "overlapping_pubmed_conditions" => overlapping_pubmed
            )
        else
            lock(() -> push!(unique_naive, naive_condition), ReentrantLock())
        end
    end
    
    # Filter out nothing values
    overlaps = [x for x in overlaps if x !== nothing]
    
    return overlaps, unique_naive
end

function parallel_analyze_drug(drug_name::String)
    """Analyze a single drug with full parallelization"""
    println("⚡ Parallel Phase 1 Evaluation: $drug_name")
    println("🧵 Using $(nthreads()) threads")
    
    # Setup thread-local databases
    setup_thread_dbs()
    
    result_data = Dict(
        "drugbank_indications" => [],
        "mesh_descriptors" => [],
        "naive_indications" => [],
        "pubmed_llm_indications" => []
    )
    
    # Load and process each data source in parallel
    tasks = []
    
    # DrugBank task
    push!(tasks, @spawn begin
        drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/$(drug_name)_drugbank_extracted_indications.json"
        if isfile(drugbank_file)
            data = JSON3.read(read(drugbank_file, String))
            if haskey(data, "indications")
                process_indications_parallel(data.indications, "llama_drugbank")
            else
                []
            end
        else
            []
        end
    end)
    
    # Naive LLM task
    push!(tasks, @spawn begin
        naive_file = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications/$(drug_name)_enhanced_naive_extracted_indications.json"
        if isfile(naive_file)
            data = JSON3.read(read(naive_file, String))
            if haskey(data, "indications")
                process_indications_parallel(data.indications, "llama_naive_enhanced")
            else
                []
            end
        else
            []
        end
    end)
    
    # PubMed LLM task
    push!(tasks, @spawn begin
        pubmed_file = "/oscar/home/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/$(drug_name)_llama_extracted_indications.json"
        if isfile(pubmed_file)
            data = JSON3.read(read(pubmed_file, String))
            if haskey(data, "disease_pairs")
                confirmed_pairs = filter(pair -> get(pair, "confirmed", false), data.disease_pairs)
                process_indications_parallel(confirmed_pairs, "llama_pubmed")
            else
                []
            end
        else
            []
        end
    end)
    
    # MeSH task (simplified for now)
    push!(tasks, @spawn begin
        mesh_file = "/oscar/home/isarkar/sarkarcode/thera/drug_pubmed_refs/$(drug_name).json"
        if isfile(mesh_file)
            try
                include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
                data = JSON3.read(read(mesh_file, String))
                if haskey(data, "mesh_summary") && haskey(data.mesh_summary, "mesh_terms")
                    mesh_descriptors = [term for term in data.mesh_summary.mesh_terms 
                                     if haskey(term, "descriptor") && term.descriptor in MESH_T047_HEADINGS]
                    process_indications_parallel(mesh_descriptors, "mesh_t047_filtering")
                else
                    []
                end
            catch e
                println("  MeSH error: $e")
                []
            end
        else
            []
        end
    end)
    
    # Collect results from parallel tasks
    results = fetch.(tasks)
    result_data["drugbank_indications"] = results[1]
    result_data["naive_indications"] = results[2] 
    result_data["pubmed_llm_indications"] = results[3]
    result_data["mesh_descriptors"] = results[4]
    
    # Recovery analysis (can also be parallelized)
    println("🔍 Calculating recovery analysis...")
    recovery_analysis = calculate_recovery_sets_parallel(result_data)
    
    # Create final result
    result = Dict(
        "metadata" => Dict(
            "drug_name" => drug_name,
            "analysis_type" => "phase1_evaluation_parallel",
            "generated_at" => string(now()),
            "threads_used" => nthreads(),
            "total_drugbank_indications" => length(result_data["drugbank_indications"]),
            "total_mesh_descriptors" => length(result_data["mesh_descriptors"]),
            "total_naive_indications" => length(result_data["naive_indications"]),
            "total_pubmed_llm_indications" => length(result_data["pubmed_llm_indications"])
        ),
        "drugbank_indications" => result_data["drugbank_indications"],
        "mesh_descriptors" => result_data["mesh_descriptors"],
        "naive_indications" => result_data["naive_indications"],
        "pubmed_llm_indications" => result_data["pubmed_llm_indications"],
        "recovery_analysis" => recovery_analysis
    )
    
    # Save results
    output_file = joinpath(RESULTS_DIR, "$(drug_name)_result_phase1_parallel.json")
    open(output_file, "w") do f
        write(f, JSON3.write(result))
    end
    
    println("✅ Parallel results saved to: $output_file")
    
    # Close thread databases
    for db in thread_dbs
        SQLite.close(db)
    end
    
    return result
end

function calculate_recovery_sets_parallel(result_data)
    """Parallel recovery analysis calculation"""
    # Same logic as before but with parallel processing where beneficial
    drugbank_indications = [indication["original_condition"] for indication in result_data["drugbank_indications"]]
    total_drugbank_indications = length(drugbank_indications)
    
    # Parallel recovery checking for each method
    methods = [
        ("mesh_descriptors", "mesh_recovery"),
        ("naive_indications", "naive_llm_recovery"), 
        ("pubmed_llm_indications", "pubmed_llm_recovery")
    ]
    
    method_recoveries = Dict()
    
    for (method_key, recovery_key) in methods
        recoveries = []
        method_data = result_data[method_key]
        
        # Process drugbank indications in parallel
        recovery_results = Vector{Union{Nothing, Dict}}(undef, length(drugbank_indications))
        
        @threads for i in 1:length(drugbank_indications)
            drugbank_indication = drugbank_indications[i]
            recovered, matches = check_indication_recovery(drugbank_indication, method_data, result_data)
            if recovered
                recovery_results[i] = Dict(
                    "drugbank_indication" => drugbank_indication,
                    "matches" => matches
                )
            end
        end
        
        # Filter out nothing values
        recoveries = [x for x in recovery_results if x !== nothing]
        
        recovery_rate = length(recoveries) / total_drugbank_indications * 100
        
        method_recoveries[recovery_key] = Dict(
            "recovered_indications" => recoveries,
            "recovery_rate" => recovery_rate,
            "total_recovered" => length(recoveries)
        )
    end
    
    # Overlap analysis
    if !isempty(result_data["naive_indications"]) && !isempty(result_data["pubmed_llm_indications"])
        overlaps, unique_naive = analyze_overlap_parallel(result_data["naive_indications"], result_data["pubmed_llm_indications"])
        
        extracted_analysis = Dict(
            "method_totals" => Dict(
                "naive_total" => length(result_data["naive_indications"]),
                "pubmed_total" => length(result_data["pubmed_llm_indications"])
            ),
            "overlap_analysis" => Dict(
                "naive_pubmed_overlaps" => overlaps,
                "total_overlapping_pairs" => length(overlaps),
                "naive_unique_count" => length(unique_naive)
            )
        )
    else
        extracted_analysis = Dict()
    end
    
    return Dict(
        "ground_truth" => Dict(
            "drugbank_indications" => drugbank_indications,
            "total_indications" => total_drugbank_indications
        ),
        "method_recoveries" => method_recoveries,
        "extracted_indications_analysis" => extracted_analysis
    )
end

function check_indication_recovery(drugbank_indication, method_results, result_data)
    """Check if indication is recovered by method"""
    target_indication = nothing
    for indication in result_data["drugbank_indications"]
        if indication["original_condition"] == drugbank_indication
            target_indication = indication
            break
        end
    end
    
    if target_indication === nothing
        return false, []
    end
    
    target_codes = Set([concept["icd10_code"] for concept in target_indication["mapped_concepts"]])
    target_chapters = Set([concept["icd10_chapter"] for concept in target_indication["mapped_concepts"]])
    
    matching_items = []
    for item in method_results
        item_codes = Set([concept["icd10_code"] for concept in item["mapped_concepts"]])
        item_chapters = Set([concept["icd10_chapter"] for concept in item["mapped_concepts"]])
        
        if !isempty(intersect(target_codes, item_codes)) || !isempty(intersect(target_chapters, item_chapters))
            push!(matching_items, Dict(
                "extracted_condition" => item["original_condition"],
                "overlapping_codes" => collect(intersect(target_codes, item_codes)),
                "overlapping_chapters" => collect(intersect(target_chapters, item_chapters))
            ))
        end
    end
    
    return !isempty(matching_items), matching_items
end

# Main execution for single drug
if length(ARGS) > 0
    drug_name = ARGS[1]
    parallel_analyze_drug(drug_name)
else
    parallel_analyze_drug("Levothyroxine")
end