#!/usr/bin/env julia

"""
Phase2 Drug-Indication Analysis

This program examines phase1_results files to identify unique naive indications
for each drug, then performs targeted PubMed searches for drug-indication 
combinations and stores detailed results.

The process:
1. Load each drug's phase1 results
2. Identify unique naive indications (not found in PubMed LLM)
3. Perform targeted PubMed searches for drug + indication combinations
4. Extract and analyze publication data with MeSH descriptors
5. Save detailed results to phase2_drug_pubmed_refs/

Usage:
    julia phase2_drug_indication_analyzer.jl [drug_name]
    julia phase2_drug_indication_analyzer.jl --all
    julia phase2_drug_indication_analyzer.jl --status
"""

using HTTP
using JSON3
using Dates
using Base.Threads

# Configuration
const PHASE1_RESULTS_DIR = "phase1_results"
const PHASE2_OUTPUT_DIR = "phase2_drug_pubmed_refs"
const MAX_PMIDS_PER_SEARCH = 50
const MAX_PMIDS_TO_ANALYZE = 20
const DEMO_MODE = false  # Set to true for limited testing

# We'll implement our own PubMed functions to avoid conflicts

"""
    load_phase1_results(drug_name::String) -> Dict

Load phase1 results for a specific drug.
"""
function load_phase1_results(drug_name::String)
    # Sanitize drug name for filename
    safe_name = replace(drug_name, r"[^a-zA-Z0-9\-\.]" => "_")
    filename = "$(safe_name)_result_phase1_simple_parallel.json"
    filepath = joinpath(PHASE1_RESULTS_DIR, filename)
    
    if !isfile(filepath)
        return nothing
    end
    
    try
        json_data = JSON3.read(read(filepath, String))
        # Convert to regular Dict for easier processing
        return Dict(string(k) => v for (k, v) in pairs(json_data))
    catch e
        println("⚠️  Error loading phase1 results for $drug_name: $e")
        return nothing
    end
end

"""
    extract_unique_naive_indications(phase1_data::Dict) -> Vector{String}

Extract naive indications that are unique (not found in PubMed LLM results).
"""
function extract_unique_naive_indications(phase1_data::Dict)
    naive_indications = get(phase1_data, "naive_indications", [])
    pubmed_indications = get(phase1_data, "pubmed_llm_indications", [])
    
    # Extract indication text from naive results
    naive_texts = Set{String}()
    for indication in naive_indications
        # Handle both Dict and JSON3.Object types
        indication_dict = isa(indication, Dict) ? indication : Dict(string(k) => v for (k, v) in pairs(indication))
        
        if haskey(indication_dict, "original_condition")
            text = lowercase(strip(string(indication_dict["original_condition"])))
            if !isempty(text) && text != "no established therapeutic indication" && text != "none established"
                push!(naive_texts, text)
            end
        end
    end
    
    # Extract indication text from pubmed results
    pubmed_texts = Set{String}()
    for indication in pubmed_indications
        # Handle both Dict and JSON3.Object types
        indication_dict = isa(indication, Dict) ? indication : Dict(string(k) => v for (k, v) in pairs(indication))
        
        if haskey(indication_dict, "indication")
            push!(pubmed_texts, lowercase(strip(string(indication_dict["indication"]))))
        elseif haskey(indication_dict, "original_condition")
            push!(pubmed_texts, lowercase(strip(string(indication_dict["original_condition"]))))
        end
    end
    
    # Return unique naive indications
    unique_naive = setdiff(naive_texts, pubmed_texts)
    return collect(unique_naive)
end

"""
    search_drug_indication_pubmed(drug_name::String, indication::String) -> Dict

Search PubMed for a specific drug-indication combination.
"""
function search_drug_indication_pubmed(drug_name::String, indication::String)
    # Build targeted search query
    query = "\"$drug_name\"[All Fields] AND \"$indication\"[All Fields]"
    
    # Build the esearch URL
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    params = [
        "db=pubmed",
        "term=" * HTTP.escapeuri(query),
        "retmode=json",
        "retmax=$MAX_PMIDS_PER_SEARCH"
    ]
    
    url = base_url * "?" * join(params, "&")
    
    try
        response = HTTP.get(url, readtimeout=30, connect_timeout=10)
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            esearch_result = data.esearchresult
            count = parse(Int, esearch_result.count)
            ids = haskey(esearch_result, :idlist) ? esearch_result.idlist : String[]
            
            return Dict(
                "status" => "success",
                "count" => count,
                "pmids" => collect(String, ids),
                "query" => query,
                "drug" => drug_name,
                "indication" => indication
            )
        else
            return Dict(
                "status" => "error",
                "error" => "HTTP $(response.status)",
                "count" => 0,
                "pmids" => String[],
                "query" => query,
                "drug" => drug_name,
                "indication" => indication
            )
        end
        
    catch e
        return Dict(
            "status" => "error", 
            "error" => string(e),
            "count" => 0,
            "pmids" => String[],
            "query" => query,
            "drug" => drug_name,
            "indication" => indication
        )
    end
end

"""
    fetch_publication_details(pmids::Vector{String}) -> Dict

Fetch publication details from PubMed using efetch API.
"""
function fetch_publication_details(pmids::Vector{String})
    if isempty(pmids)
        return Dict("status" => "error", "error" => "No PMIDs provided")
    end
    
    # Limit PMIDs for analysis
    limited_pmids = pmids[1:min(MAX_PMIDS_TO_ANALYZE, length(pmids))]
    pmid_string = join(limited_pmids, ",")
    
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    params = Dict(
        "db" => "pubmed",
        "id" => pmid_string,
        "retmode" => "xml",
        "tool" => "julia_phase2_analyzer",
        "email" => "neil_sarkar@brown.edu"
    )
    
    try
        response = HTTP.get(base_url, query=params, readtimeout=30)
        
        if response.status == 200
            return Dict(
                "status" => "success",
                "xml_data" => String(response.body),
                "pmids_fetched" => limited_pmids
            )
        else
            return Dict(
                "status" => "error",
                "error" => "HTTP $(response.status)"
            )
        end
        
    catch e
        return Dict(
            "status" => "error",
            "error" => string(e)
        )
    end
end

"""
    extract_mesh_descriptors(xml_data::String) -> Vector{Dict}

Extract MeSH descriptors from PubMed XML data.
"""
function extract_mesh_descriptors(xml_data::String)
    publications = Vector{Dict}()
    
    try
        # Pre-compile regex patterns
        article_pattern = r"<PubmedArticle>(.*?)</PubmedArticle>"s
        pmid_pattern = r"<PMID[^>]*>(\d+)</PMID>"
        title_pattern = r"<ArticleTitle>(.*?)</ArticleTitle>"s
        abstract_pattern = r"<AbstractText[^>]*>(.*?)</AbstractText>"s
        mesh_pattern = r"<MeshHeading>(.*?)</MeshHeading>"s
        descriptor_pattern = r"<DescriptorName[^>]*>(.*?)</DescriptorName>"
        
        # Extract individual articles
        article_matches = eachmatch(article_pattern, xml_data)
        
        for article_match in article_matches
            article_xml = article_match.captures[1]
            
            # Extract PMID
            pmid_match = match(pmid_pattern, article_xml)
            pmid = pmid_match !== nothing ? pmid_match.captures[1] : "unknown"
            
            # Extract title
            title_match = match(title_pattern, article_xml)
            title = title_match !== nothing ? title_match.captures[1] : "No title"
            
            # Extract abstract
            abstract_match = match(abstract_pattern, article_xml)
            abstract = abstract_match !== nothing ? abstract_match.captures[1] : "No abstract available"
            
            # Extract MeSH descriptors
            mesh_descriptors = Vector{String}()
            mesh_matches = eachmatch(mesh_pattern, article_xml)
            
            for mesh_match in mesh_matches
                mesh_xml = mesh_match.captures[1]
                descriptor_match = match(descriptor_pattern, mesh_xml)
                if descriptor_match !== nothing
                    push!(mesh_descriptors, descriptor_match.captures[1])
                end
            end
            
            push!(publications, Dict(
                "pmid" => pmid,
                "title" => title,
                "abstract" => abstract,
                "mesh_descriptors" => mesh_descriptors
            ))
        end
        
    catch e
        println("Warning: Error parsing XML data: $e")
    end
    
    return publications
end

"""
    fetch_and_analyze_publications(pmids::Vector{String}) -> Vector{Dict}

Fetch publication details and extract MeSH descriptors.
"""
function fetch_and_analyze_publications(pmids::Vector{String})
    if isempty(pmids)
        return []
    end
    
    # Fetch publication details
    fetch_result = fetch_publication_details(pmids)
    
    if fetch_result["status"] != "success"
        return []
    end
    
    # Extract MeSH descriptors
    publications = extract_mesh_descriptors(fetch_result["xml_data"])
    
    return publications
end

"""
    analyze_drug_indication_combination(drug_name::String, indication::String) -> Dict

Perform complete analysis for a drug-indication combination.
"""
function analyze_drug_indication_combination(drug_name::String, indication::String)
    println("  🔍 Analyzing: $drug_name + $indication")
    
    # Search PubMed for this combination
    search_result = search_drug_indication_pubmed(drug_name, indication)
    
    if search_result["status"] != "success"
        return Dict(
            "drug_name" => drug_name,
            "indication" => indication,
            "search_status" => search_result["status"],
            "search_error" => get(search_result, "error", "Unknown error"),
            "publications_found" => 0,
            "publications_analyzed" => 0,
            "mesh_analysis" => Dict("status" => "search_failed")
        )
    end
    
    pmids = search_result["pmids"]
    count = search_result["count"]
    
    println("    📊 Found $count publications ($(length(pmids)) PMIDs retrieved)")
    
    if isempty(pmids)
        return Dict(
            "drug_name" => drug_name,
            "indication" => indication,
            "search_status" => "success",
            "search_query" => search_result["query"],
            "publications_found" => count,
            "publications_analyzed" => 0,
            "mesh_analysis" => Dict("status" => "no_publications")
        )
    end
    
    # Fetch and analyze publications
    println("    📥 Fetching publication details...")
    publications = fetch_and_analyze_publications(pmids)
    
    # Analyze MeSH terms and extract disease associations
    mesh_terms = []
    disease_terms = []
    
    for pub in publications
        for descriptor in pub["mesh_descriptors"]
            push!(mesh_terms, descriptor)
            
            # Simple heuristic: if it contains disease-related keywords
            if occursin(r"disease|disorder|syndrome|condition|pathology|cancer|tumor", lowercase(descriptor))
                push!(disease_terms, descriptor)
            end
        end
    end
    
    return Dict(
        "drug_name" => drug_name,
        "indication" => indication,
        "search_status" => "success",
        "search_query" => search_result["query"],
        "publications_found" => count,
        "publications_analyzed" => length(publications),
        "pmids_analyzed" => [pub["pmid"] for pub in publications],
        "mesh_analysis" => Dict(
            "status" => "success",
            "total_mesh_terms" => length(mesh_terms),
            "unique_mesh_terms" => length(unique(mesh_terms)),
            "disease_related_terms" => unique(disease_terms),
            "mesh_term_counts" => countmap(mesh_terms)
        ),
        "publications" => publications,
        "analysis_timestamp" => string(now())
    )
end

"""
    process_drug_phase2(drug_name::String) -> Dict

Process a single drug for phase2 analysis.
"""
function process_drug_phase2(drug_name::String)
    println("🔬 Processing drug: $drug_name")
    
    # Load phase1 results
    phase1_data = load_phase1_results(drug_name)
    if phase1_data === nothing
        println("  ❌ No phase1 results found for $drug_name")
        return Dict(
            "drug_name" => drug_name,
            "status" => "error",
            "error" => "No phase1 results found",
            "unique_indications" => [],
            "indication_analyses" => []
        )
    end
    
    # Extract unique naive indications
    unique_indications = extract_unique_naive_indications(phase1_data)
    
    if isempty(unique_indications)
        println("  ℹ️  No unique naive indications found for $drug_name")
        return Dict(
            "drug_name" => drug_name,
            "status" => "success",
            "unique_indications" => [],
            "indication_analyses" => [],
            "summary" => "No unique naive indications to analyze"
        )
    end
    
    println("  📋 Found $(length(unique_indications)) unique naive indications")
    
    # Analyze each unique indication
    indication_analyses = []
    for (i, indication) in enumerate(unique_indications)
        println("    [$i/$(length(unique_indications))] $indication")
        
        analysis = analyze_drug_indication_combination(drug_name, indication)
        push!(indication_analyses, analysis)
        
        # Small delay to be respectful to NCBI
        sleep(0.5)
    end
    
    # Create summary
    successful_analyses = filter(a -> get(a, "search_status", "") == "success", indication_analyses)
    total_publications = sum(get(a, "publications_found", 0) for a in successful_analyses)
    
    result = Dict(
        "drug_name" => drug_name,
        "status" => "success",
        "unique_indications" => unique_indications,
        "indication_analyses" => indication_analyses,
        "summary" => Dict(
            "total_unique_indications" => length(unique_indications),
            "successful_searches" => length(successful_analyses),
            "total_publications_found" => total_publications,
            "average_publications_per_indication" => length(successful_analyses) > 0 ? round(total_publications / length(successful_analyses), digits=1) : 0.0
        ),
        "metadata" => Dict(
            "processed_at" => string(now()),
            "phase2_analysis_version" => "1.0",
            "max_pmids_per_search" => MAX_PMIDS_PER_SEARCH,
            "max_pmids_analyzed" => MAX_PMIDS_TO_ANALYZE
        )
    )
    
    return result
end

"""
    save_phase2_results(drug_name::String, results::Dict)

Save phase2 results to individual JSON file.
"""
function save_phase2_results(drug_name::String, results::Dict)
    # Create output directory if needed
    if !isdir(PHASE2_OUTPUT_DIR)
        mkpath(PHASE2_OUTPUT_DIR)
    end
    
    # Sanitize filename
    safe_name = replace(drug_name, r"[^a-zA-Z0-9\-\.]" => "_")
    filename = "$(safe_name)_phase2_drug_indication_analysis.json"
    filepath = joinpath(PHASE2_OUTPUT_DIR, filename)
    
    try
        open(filepath, "w") do f
            write(f, JSON3.write(results, indent=2))
        end
        println("  💾 Saved results to: $filename")
    catch e
        println("  ❌ Error saving results: $e")
    end
end

"""
    get_drugs_for_processing() -> Vector{String}

Get list of drugs that have phase1 results and need phase2 processing.
"""
function get_drugs_for_processing()
    if !isdir(PHASE1_RESULTS_DIR)
        error("Phase1 results directory not found: $PHASE1_RESULTS_DIR")
    end
    
    # Get all phase1 result files
    files = filter(f -> endswith(f, "_result_phase1_simple_parallel.json"), readdir(PHASE1_RESULTS_DIR))
    
    # Extract drug names
    drugs = []
    for file in files
        # Remove the suffix to get drug name
        drug_name = replace(file, "_result_phase1_simple_parallel.json" => "")
        # Restore spaces and special characters (reverse sanitization)
        drug_name = replace(drug_name, "_" => " ")
        push!(drugs, drug_name)
    end
    
    return sort(drugs)
end

"""
    get_processing_status() -> Dict

Check which drugs have been processed and which are remaining.
"""
function get_processing_status()
    all_drugs = get_drugs_for_processing()
    
    # Check which drugs already have phase2 results
    processed_drugs = []
    if isdir(PHASE2_OUTPUT_DIR)
        phase2_files = filter(f -> endswith(f, "_phase2_drug_indication_analysis.json"), readdir(PHASE2_OUTPUT_DIR))
        for file in phase2_files
            drug_name = replace(file, "_phase2_drug_indication_analysis.json" => "")
            drug_name = replace(drug_name, "_" => " ")
            push!(processed_drugs, drug_name)
        end
    end
    
    remaining_drugs = setdiff(all_drugs, processed_drugs)
    
    return Dict(
        "total_drugs" => length(all_drugs),
        "processed" => length(processed_drugs),
        "remaining" => length(remaining_drugs),
        "processed_drugs" => sort(processed_drugs),
        "remaining_drugs" => sort(remaining_drugs),
        "completion_percentage" => length(all_drugs) > 0 ? round(length(processed_drugs) / length(all_drugs) * 100, digits=1) : 0.0
    )
end

"""
    main()

Main function to run phase2 analysis.
"""
function main()
    println("🔬 Phase2 Drug-Indication Analysis")
    println("=" ^ 40)
    println()
    
    # Parse command line arguments
    if length(ARGS) == 0
        println("Usage:")
        println("  julia phase2_drug_indication_analyzer.jl [drug_name]")
        println("  julia phase2_drug_indication_analyzer.jl --all")
        println("  julia phase2_drug_indication_analyzer.jl --status")
        return
    end
    
    arg = ARGS[1]
    
    if arg == "--status"
        println("📊 Processing Status:")
        status = get_processing_status()
        println("  • Total drugs with phase1 results: $(status["total_drugs"])")
        println("  • Already processed: $(status["processed"])")
        println("  • Remaining to process: $(status["remaining"])")
        println("  • Completion: $(status["completion_percentage"])%")
        
        if status["remaining"] > 0
            println("\n📋 Next drugs to process:")
            for (i, drug) in enumerate(status["remaining_drugs"][1:min(10, length(status["remaining_drugs"]))])
                println("  $i. $drug")
            end
            if length(status["remaining_drugs"]) > 10
                println("  ... and $(length(status["remaining_drugs"]) - 10) more")
            end
        end
        
        return
    end
    
    if arg == "--all"
        println("🚀 Processing all drugs with unique naive indications...")
        
        status = get_processing_status()
        drugs_to_process = status["remaining_drugs"]
        
        if isempty(drugs_to_process)
            println("✅ All drugs have been processed!")
            return
        end
        
        println("📋 Will process $(length(drugs_to_process)) drugs")
        
        if DEMO_MODE
            drugs_to_process = drugs_to_process[1:min(5, length(drugs_to_process))]
            println("⚡ Demo mode: Limited to $(length(drugs_to_process)) drugs")
        end
        
        # Process each drug
        for (i, drug_name) in enumerate(drugs_to_process)
            println("\n[$i/$(length(drugs_to_process))] Processing: $drug_name")
            
            results = process_drug_phase2(drug_name)
            save_phase2_results(drug_name, results)
            
            # Show summary
            if results["status"] == "success" && !isempty(results["unique_indications"])
                summary = results["summary"]
                println("  ✅ Found $(summary["total_unique_indications"]) unique indications")
                println("     $(summary["successful_searches"]) successful searches")
                println("     $(summary["total_publications_found"]) total publications")
            end
            
            # Small delay between drugs
            sleep(1.0)
        end
        
        println("\n🎉 Batch processing complete!")
        
    else
        # Process single drug
        drug_name = arg
        println("🔬 Processing single drug: $drug_name")
        
        results = process_drug_phase2(drug_name)
        save_phase2_results(drug_name, results)
        
        if results["status"] == "success"
            if !isempty(results["unique_indications"])
                summary = results["summary"]
                println("\n📊 Results Summary:")
                println("  • Unique indications: $(summary["total_unique_indications"])")
                println("  • Successful searches: $(summary["successful_searches"])")
                println("  • Total publications: $(summary["total_publications_found"])")
                println("  • Avg publications/indication: $(summary["average_publications_per_indication"])")
            else
                println("\n📊 No unique naive indications found for this drug")
            end
        else
            println("\n❌ Processing failed: $(get(results, "error", "Unknown error"))")
        end
    end
end

# Simple countmap function (in case it's not available)
function countmap(items)
    counts = Dict{eltype(items), Int}()
    for item in items
        counts[item] = get(counts, item, 0) + 1
    end
    return counts
end

# Run main function if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end