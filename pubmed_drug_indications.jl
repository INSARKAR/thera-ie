#!/usr/bin/env julia

"""
PubMed Drug Indications Analysis

This program combines PubMed search and disease association analysis into a single workflow.
It searches PubMed for approved drugs, fetches publication details, and analyzes MeSH descriptors
to identify disease associations from the MeSH T047 (Disease or Syndrome) semantic type.

CONFIGURATION:
    Set DEMO_MODE = true for quick demonstration (10 drugs, limited results)
    Set DEMO_MODE = false for full production run (all drugs, no limits)

Usage:
    julia pubmed_drug_indications.jl

Input:
    - approved_drugs_dict.jl (Dictionary of approved drugs and indications)
    - mesh_t047_headings.jl (MeSH T047 disease headings)

Output:
    - drug_disease_associations.json (Comprehensive disease associations in JSON format)
    - drug_disease_associations.txt (Human-readable summary)

The program:
1. Loads approved drugs from the dictionary
2. Loads MeSH T047 disease headings
3. For each drug:
   - Searches PubMed for publications
   - Fetches detailed publication data including MeSH descriptors
   - Analyzes disease associations
4. Outputs comprehensive drug-disease association results
"""

using HTTP
using JSON3
using Dates
using Distributed

# Add JSON fallback for compatibility
try
    using JSON
catch
    # JSON fallback not available, will use only JSON3
end

# Configuration
# Toggle between demonstration and production modes
const DEMO_MODE = true  # Set to true for demonstration, false for full production run

# Demonstration limits (used when DEMO_MODE = true)
const DEMO_MAX_DRUGS = 10
const DEMO_MAX_RESULTS_PER_DRUG = 50
const DEMO_MAX_PMIDS_TO_ANALYZE = 10

# Production settings (used when DEMO_MODE = false)
const PROD_MAX_DRUGS =  1_000_000 #  Effectively unlimited
const PROD_MAX_RESULTS_PER_DRUG = 1_000_000  # Effectively unlimited
const PROD_MAX_PMIDS_TO_ANALYZE = 1_000_000   # Effectively unlimited

# Set active configuration based on mode
const MAX_DRUGS = DEMO_MODE ? DEMO_MAX_DRUGS : PROD_MAX_DRUGS
const MAX_RESULTS_PER_DRUG = DEMO_MODE ? DEMO_MAX_RESULTS_PER_DRUG : PROD_MAX_RESULTS_PER_DRUG
const MAX_PMIDS_TO_ANALYZE = DEMO_MODE ? DEMO_MAX_PMIDS_TO_ANALYZE : PROD_MAX_PMIDS_TO_ANALYZE

# Add workers for parallel processing (disabled for compatibility)
# if nprocs() == 1
#     addprocs(min(4, Sys.CPU_THREADS ÷ 2))  # Use half available cores
# end

# @everywhere using HTTP, JSON3, Dates

"""
    sanitize_filename(name::String) -> String

Convert a drug name to a safe filename by replacing non-alphanumeric characters with underscores.
"""
function sanitize_filename(name::String)
    # Replace all non-alphanumeric characters with underscores
    sanitized = replace(name, r"[^a-zA-Z0-9]" => "_")
    # Remove multiple consecutive underscores
    sanitized = replace(sanitized, r"_+" => "_")
    # Remove leading/trailing underscores
    sanitized = strip(sanitized, '_')
    return sanitized
end

"""
    save_individual_drug_result(result::Dict, output_dir::String)

Save individual drug analysis result to a separate JSON file.
"""
function save_individual_drug_result(result::Dict, output_dir::String)
    # Create output directory if it doesn't exist
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    
    drug_name = result["drug_name"]
    safe_filename = sanitize_filename(drug_name)
    filepath = joinpath(output_dir, "$(safe_filename).json")
    
    # Prepare the data with metadata
    drug_data = Dict(
        "metadata" => Dict(
            "drug_name" => drug_name,
            "generated_on" => string(now()),
            "filename" => "$(safe_filename).json",
            "description" => "Individual drug analysis result from PubMed drug-disease association pipeline"
        ),
        "result" => result
    )
    
    # Save to JSON file
    open(filepath, "w") do file
        write(file, JSON3.write(drug_data))
    end
    
    return filepath
end

# Advanced performance optimizations
# Note: Some HTTP optimizations may not be available in all Julia versions
try
    # Try to create a connection pool for HTTP reuse
    global HTTP_CLIENT = nothing  # Will use default client for compatibility
catch
    # Fallback if HTTP client features not available
    global HTTP_CLIENT = nothing
end

# Cache for frequently accessed data
const GLOBAL_CACHE = Dict{String, Any}()

# Buffer for batch file operations
mutable struct FileWriteBuffer
    data::Vector{Pair{String, String}}  # filepath => content
    max_size::Int
    FileWriteBuffer(max_size=5) = new(Pair{String, String}[], max_size)
end

const WRITE_BUFFER = FileWriteBuffer()

"""
    flush_write_buffer!(buffer::FileWriteBuffer)

Flush all buffered writes to disk efficiently.
"""
function flush_write_buffer!(buffer::FileWriteBuffer)
    if isempty(buffer.data)
        return 0
    end
    
    writes_performed = 0
    for (filepath, content) in buffer.data
        try
            # Ensure directory exists
            dirname_path = dirname(filepath)
            if !isdir(dirname_path)
                mkpath(dirname_path)
            end
            
            # Write file
            open(filepath, "w") do file
                write(file, content)
            end
            writes_performed += 1
        catch e
            println("⚠️  Warning: Failed to write $(basename(filepath)): $e")
        end
    end
    
    empty!(buffer.data)
    return writes_performed
end

"""
    buffered_write(filepath::String, content::String, buffer::FileWriteBuffer=WRITE_BUFFER)

Add a file write to the buffer, flushing if buffer is full.
"""
function buffered_write(filepath::String, content::String, buffer::FileWriteBuffer=WRITE_BUFFER)
    push!(buffer.data, filepath => content)
    
    if length(buffer.data) >= buffer.max_size
        return flush_write_buffer!(buffer)
    end
    
    return 0
end

"""
    optimized_json_write(data::Any) -> String

Optimized JSON serialization with better memory management.
"""
function optimized_json_write(data::Any)
    try
        return JSON3.write(data)
    catch e
        # Fallback - just use JSON3 with error message
        println("⚠️  Warning: JSON3 serialization issue: $e")
        return JSON3.write(data)  # Try again, will error if it fails
    end
end

"""
    save_individual_drug_result_optimized(result::Dict, output_dir::String, use_buffer::Bool=true)

Optimized version of save_individual_drug_result with buffering and better error handling.
"""
function save_individual_drug_result_optimized(result::Dict, output_dir::String, use_buffer::Bool=true)
    try
        # Create output directory if it doesn't exist
        if !isdir(output_dir)
            mkpath(output_dir)
        end
        
        drug_name = result["drug_name"]
        safe_filename = sanitize_filename(drug_name)
        filepath = joinpath(output_dir, "$(safe_filename).json")
        
        # Prepare the data with metadata
        drug_data = Dict(
            "metadata" => Dict(
                "drug_name" => drug_name,
                "generated_on" => string(now()),
                "filename" => "$(safe_filename).json",
                "description" => "Individual drug analysis result from PubMed drug-disease association pipeline"
            ),
            "result" => result
        )
        
        # Serialize JSON content
        json_content = optimized_json_write(drug_data)
        
        if use_buffer
            # Use buffered write for better I/O performance
            buffered_write(filepath, json_content)
        else
            # Direct write
            open(filepath, "w") do file
                write(file, json_content)
            end
        end
        
        return filepath
        
    catch e
        println("⚠️  Error saving result for $(get(result, "drug_name", "unknown")): $e")
        return nothing
    end
end

"""
    load_approved_drugs() -> Dict{String, String}

Load approved drugs dictionary from the generated file.
"""
function load_approved_drugs()
    # Try to load from Julia file first
    if isfile("approved_drugs_dict.jl")
        include("approved_drugs_dict.jl")
        if @isdefined(APPROVED_DRUGS_DICT)
            return APPROVED_DRUGS_DICT
        end
    end
    
    # Try to load from JSON file
    if isfile("approved_drugs_dict.json")
        json_data = JSON3.read(read("approved_drugs_dict.json", String))
        if haskey(json_data, "drugs")
            return json_data.drugs
        end
    end
    
    error("No approved drugs dictionary found! Run approved_drugs_extractor.jl first.")
end

"""
    load_mesh_disease_headings(filename::String) -> Set{String}

Load MeSH T047 disease headings from Julia file.
"""
function load_mesh_disease_headings(filename::String)
    if !isfile(filename)
        error("MeSH disease headings file not found: $filename")
    end
    
    try
        include(filename)
        return MESH_T047_HEADINGS
    catch e
        error("Error loading MeSH disease headings: $e")
    end
end

"""
    search_pubmed_optimized(drug_name::String; retmax::Int=50) -> Dict

Optimized PubMed search with better error handling and reduced latency.
"""
function search_pubmed_optimized(drug_name::String; retmax::Int=50)
    # Build simple search query for drug name
    query = "\"$drug_name\"[All Fields]"
    
    # Build the esearch URL
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    params = [
        "db=pubmed",
        "term=" * HTTP.escapeuri(query),
        "retmode=json",
        "retmax=$retmax"
    ]
    
    url = base_url * "?" * join(params, "&")
    
    try
        # Make the API request with timeout and connection reuse
        response = HTTP.get(url, readtimeout=30, connect_timeout=10)
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            
            # Extract results
            esearch_result = data.esearchresult
            count = parse(Int, esearch_result.count)
            ids = haskey(esearch_result, :idlist) ? esearch_result.idlist : String[]
            
            return Dict(
                "status" => "success",
                "count" => count,
                "pmids" => collect(String, ids),
                "query" => query
            )
        else
            return Dict(
                "status" => "error",
                "error" => "HTTP $(response.status)",
                "count" => 0,
                "pmids" => String[]
            )
        end
        
    catch e
        return Dict(
            "status" => "error", 
            "error" => string(e),
            "count" => 0,
            "pmids" => String[]
        )
    end
end

"""
    search_pubmed_cached(drug_name::String; retmax::Int=50, use_cache::Bool=true) -> Dict

Enhanced PubMed search with caching to avoid duplicate API calls.
"""
function search_pubmed_cached(drug_name::String; retmax::Int=50, use_cache::Bool=true)
    cache_key = "search_$(drug_name)_$(retmax)"
    
    # Check cache first
    if use_cache && haskey(GLOBAL_CACHE, cache_key)
        cached_result = GLOBAL_CACHE[cache_key]
        # Add cache hit indicator
        cached_result["cache_hit"] = true
        return cached_result
    end
    
    # Build simple search query for drug name
    query = "\"$drug_name\"[All Fields]"
    
    # Build the esearch URL
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    params = [
        "db=pubmed",
        "term=" * HTTP.escapeuri(query),
        "retmode=json",
        "retmax=$retmax"
    ]
    
    url = base_url * "?" * join(params, "&")
    
    try
        # Make the API request with timeout
        if HTTP_CLIENT !== nothing
            response = HTTP.get(url, HTTP_CLIENT)
        else
            response = HTTP.get(url, readtimeout=30, connect_timeout=10)
        end
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            
            # Extract results
            esearch_result = data.esearchresult
            count = parse(Int, esearch_result.count)
            ids = haskey(esearch_result, :idlist) ? esearch_result.idlist : String[]
            
            result = Dict(
                "status" => "success",
                "count" => count,
                "pmids" => collect(String, ids),
                "query" => query,
                "cache_hit" => false
            )
            
            # Cache successful results
            if use_cache && result["status"] == "success"
                GLOBAL_CACHE[cache_key] = copy(result)
            end
            
            return result
        else
            return Dict(
                "status" => "error",
                "error" => "HTTP $(response.status)",
                "count" => 0,
                "pmids" => String[],
                "cache_hit" => false
            )
        end
        
    catch e
        return Dict(
            "status" => "error", 
            "error" => string(e),
            "count" => 0,
            "pmids" => String[],
            "cache_hit" => false
        )
    end
end

"""
    fetch_publication_details_optimized(pmids; use_cache::Bool=true) -> Dict

Enhanced publication fetching with caching and improved error handling.
"""
function fetch_publication_details_optimized(pmids; use_cache::Bool=true)
    if isempty(pmids)
        return Dict("status" => "error", "error" => "No PMIDs provided")
    end
    
    # Convert to regular array and limit PMIDs for analysis
    pmid_array = collect(pmids)
    limited_pmids = pmid_array[1:min(MAX_PMIDS_TO_ANALYZE, length(pmid_array))]
    
    # Check cache for entire batch
    cache_key = "fetch_" * join(sort(limited_pmids), ",")
    if use_cache && haskey(GLOBAL_CACHE, cache_key)
        cached_result = GLOBAL_CACHE[cache_key]
        cached_result["cache_hit"] = true
        return cached_result
    end
    
    # Optimized batch size based on URL length limits
    batch_size = 150  # Conservative to avoid HTTP 414 errors
    
    all_xml_data = Vector{String}()
    sizehint!(all_xml_data, ceil(Int, length(limited_pmids) / batch_size))
    
    all_fetched_pmids = Vector{String}()
    sizehint!(all_fetched_pmids, length(limited_pmids))
    
    total_batches = ceil(Int, length(limited_pmids) / batch_size)
    successful_batches = 0
    
    println("📦 Processing $(length(limited_pmids)) PMIDs in $total_batches batches...")
    
    for (batch_idx, batch_start) in enumerate(1:batch_size:length(limited_pmids))
        batch_end = min(batch_start + batch_size - 1, length(limited_pmids))
        batch_pmids = limited_pmids[batch_start:batch_end]
        pmid_string = join(batch_pmids, ",")
        
        print("  📥 Batch $batch_idx/$total_batches ($(length(batch_pmids)) PMIDs)... ")
        
        base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
        
        params = Dict(
            "db" => "pubmed",
            "id" => pmid_string,
            "retmode" => "xml",
            "tool" => "julia_pubmed_drug_indications",
            "email" => "neil_sarkar@brown.edu"
        )
        
        retry_count = 0
        max_retries = 2
        
        while retry_count <= max_retries
            try
                if HTTP_CLIENT !== nothing
                    response = HTTP.get(base_url, query=params, HTTP_CLIENT)
                else
                    response = HTTP.get(base_url, query=params, readtimeout=30)
                end
                
                if response.status == 200
                    push!(all_xml_data, String(response.body))
                    append!(all_fetched_pmids, batch_pmids)
                    successful_batches += 1
                    println("✅ Success")
                    break
                else
                    if retry_count < max_retries
                        println("⚠️  HTTP $(response.status), retrying...")
                        sleep(0.1 * (retry_count + 1))  # Exponential backoff
                        retry_count += 1
                    else
                        println("❌ HTTP $(response.status) (final attempt)")
                        break
                    end
                end
                
            catch e
                if retry_count < max_retries
                    println("⚠️  Error: $(string(e)), retrying...")
                    sleep(0.1 * (retry_count + 1))
                    retry_count += 1
                else
                    println("❌ Error: $(string(e)) (final attempt)")
                    break
                end
            end
        end
        
        # Very short pause between requests (optimized)
        sleep(0.02)
    end
    
    if successful_batches > 0
        # Combine all XML data efficiently
        combined_xml = join(all_xml_data, "\n")
        
        println("  📊 Successfully fetched $successful_batches/$total_batches batches ($(length(all_fetched_pmids)) total PMIDs)")
        
        result = Dict(
            "status" => "success",
            "xml_data" => combined_xml,
            "pmids_fetched" => all_fetched_pmids,
            "batches_processed" => successful_batches,
            "total_batches" => total_batches,
            "fetch_time" => now(),
            "cache_hit" => false
        )
        
        # Cache successful results (but not the large XML data to save memory)
        if use_cache
            cache_result = copy(result)
            # Don't cache the actual XML data to save memory
            delete!(cache_result, "xml_data")
            cache_result["xml_size"] = length(combined_xml)
            GLOBAL_CACHE[cache_key] = cache_result
        end
        
        return result
    else
        return Dict(
            "status" => "error",
            "error" => "All batches failed",
            "batches_processed" => 0,
            "total_batches" => total_batches,
            "fetch_time" => now(),
            "cache_hit" => false
        )
    end
end

"""
    extract_mesh_descriptors_optimized(xml_data::String) -> Vector{Dict}

Optimized MeSH descriptor extraction with better regex patterns and reduced allocations.
"""
function extract_mesh_descriptors_optimized(xml_data::String)
    publications = Vector{Dict}()
    sizehint!(publications, 50)  # Pre-allocate expected size
    
    try
        # Pre-compile regex patterns for better performance
        article_pattern = r"<PubmedArticle>(.*?)</PubmedArticle>"s
        pmid_pattern = r"<PMID[^>]*>(\d+)</PMID>"
        title_pattern = r"<ArticleTitle>(.*?)</ArticleTitle>"s
        abstract_pattern = r"<AbstractText[^>]*>(.*?)</AbstractText>"s
        mesh_pattern = r"<MeshHeading>(.*?)</MeshHeading>"s
        descriptor_pattern = r"<DescriptorName[^>]*>(.*?)</DescriptorName>"
        qualifier_pattern = r"<QualifierName[^>]*>(.*?)</QualifierName>"
        
        # Extract individual PubmedArticle elements
        article_matches = eachmatch(article_pattern, xml_data)
        
        for article_match in article_matches
            article_xml = article_match.captures[1]
            
            # Extract PMID
            pmid_match = match(pmid_pattern, article_xml)
            pmid = pmid_match !== nothing ? pmid_match.captures[1] : "unknown"
            
            # Extract article title
            title_match = match(title_pattern, article_xml)
            title = title_match !== nothing ? title_match.captures[1] : "No title"
            
            # Extract abstract
            abstract_match = match(abstract_pattern, article_xml)
            abstract = abstract_match !== nothing ? abstract_match.captures[1] : "No abstract available"
            
            # Extract MeSH descriptors
            mesh_descriptors = Vector{Dict}()
            mesh_matches = eachmatch(mesh_pattern, article_xml)
            
            for mesh_match in mesh_matches
                mesh_xml = mesh_match.captures[1]
                
                # Extract descriptor name
                descriptor_match = match(descriptor_pattern, mesh_xml)
                if descriptor_match !== nothing
                    descriptor_name = descriptor_match.captures[1]
                    
                    # Extract qualifiers if any
                    qualifiers = String[]
                    qualifier_matches = eachmatch(qualifier_pattern, mesh_xml)
                    
                    for qualifier_match in qualifier_matches
                        push!(qualifiers, qualifier_match.captures[1])
                    end
                    
                    push!(mesh_descriptors, Dict(
                        "descriptor" => descriptor_name,
                        "qualifiers" => qualifiers
                    ))
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
    analyze_disease_associations(publications::Vector, disease_headings::Set{String}, drug_name::String) -> Dict

Analyze publications to find disease associations based on MeSH descriptors.
Creates detailed dictionaries for drug-disease pairings with publication information.
"""
function analyze_disease_associations(publications::Vector, disease_headings::Set{String}, drug_name::String)
    disease_associations = Dict{String, Vector{Dict}}()
    drug_disease_publications = Dict{String, Dict}()  # New: store detailed publication info
    total_publications = length(publications)
    total_mesh_terms = 0
    matched_diseases = Set{String}()
    
    for pub in publications
        total_mesh_terms += length(pub["mesh_descriptors"])
        
        for mesh_desc in pub["mesh_descriptors"]
            descriptor_name = mesh_desc["descriptor"]
            
            # Check if this MeSH descriptor is in our disease list
            if descriptor_name in disease_headings
                if !haskey(disease_associations, descriptor_name)
                    disease_associations[descriptor_name] = []
                end
                
                # Create drug-disease pairing key
                drug_disease_key = "$(drug_name)||$(descriptor_name)"
                
                # Store detailed publication information for this drug-disease pairing
                if !haskey(drug_disease_publications, drug_disease_key)
                    drug_disease_publications[drug_disease_key] = Dict(
                        "drug_name" => drug_name,
                        "disease_name" => descriptor_name,
                        "publications" => Dict{String, Dict}()  # PMID => publication details
                    )
                end
                
                # Add publication details to the drug-disease pairing
                pmid = pub["pmid"]
                drug_disease_publications[drug_disease_key]["publications"][pmid] = Dict(
                    "pmid" => pmid,
                    "title" => pub["title"],
                    "abstract" => pub["abstract"],
                    "qualifiers" => mesh_desc["qualifiers"]
                )
                
                push!(disease_associations[descriptor_name], Dict(
                    "pmid" => pub["pmid"],
                    "title" => pub["title"],
                    "qualifiers" => mesh_desc["qualifiers"]
                ))
                
                push!(matched_diseases, descriptor_name)
            end
        end
    end
    
    return Dict(
        "disease_associations" => disease_associations,
        "drug_disease_publications" => drug_disease_publications,
        "summary" => Dict(
            "total_publications_analyzed" => total_publications,
            "total_mesh_terms" => total_mesh_terms,
            "unique_diseases_found" => length(matched_diseases),
            "diseases_with_associations" => length(disease_associations),
            "matched_diseases" => collect(matched_diseases)
        )
    )
end

"""
    process_drug(drug_name::String, indication::String, disease_headings::Set{String}) -> Dict

Complete processing pipeline for a single drug: search, fetch, and analyze.
"""
function process_drug(drug_name::String, indication::String, disease_headings::Set{String})
    println("  Searching PubMed...")
    
    # Step 1: Search PubMed
    search_result = search_pubmed_optimized(drug_name; retmax=MAX_RESULTS_PER_DRUG)
    
    if search_result["status"] != "success"
        return Dict(
            "drug_name" => drug_name,
            "drugbank_indication" => indication,
            "search_status" => search_result["status"],
            "search_error" => get(search_result, "error", "Unknown error"),
            "count" => 0,
            "pmids" => String[],
            "disease_analysis" => Dict("status" => "search_failed")
        )
    end
    
    pmids = search_result["pmids"]
    count = search_result["count"]
    
    println("    ✓ Found $count publications ($(length(pmids)) PMIDs retrieved)")
    
    if isempty(pmids)
        return Dict(
            "drug_name" => drug_name,
            "drugbank_indication" => indication,
            "search_status" => "success",
            "count" => count,
            "pmids" => pmids,
            "disease_analysis" => Dict("status" => "no_pmids")
        )
    end
    
    # Step 2: Fetch publication details
    println("  Fetching publication details...")
    fetch_result = fetch_publication_details(pmids)
    
    if fetch_result["status"] != "success"
        return Dict(
            "drug_name" => drug_name,
            "drugbank_indication" => indication,
            "search_status" => "success",
            "count" => count,
            "pmids" => pmids,
            "fetch_error" => get(fetch_result, "error", "Unknown error"),
            "disease_analysis" => Dict("status" => "fetch_failed")
        )
    end
    
    # Step 3: Extract MeSH descriptors
    println("  Extracting MeSH descriptors...")
    publications = extract_mesh_descriptors_optimized(fetch_result["xml_data"])
    println("    ✓ Analyzed $(length(publications)) publications")
    
    # Step 4: Analyze disease associations
    println("  Analyzing disease associations...")
    disease_analysis = analyze_disease_associations(publications, disease_headings, drug_name)
    
    # Display findings
    disease_count = disease_analysis["summary"]["unique_diseases_found"]
    if disease_count > 0
        println("    🔬 Found associations with $disease_count disease(s):")
        matched_diseases = disease_analysis["summary"]["matched_diseases"]
        for disease in matched_diseases[1:min(3, length(matched_diseases))]
            pub_count = length(disease_analysis["disease_associations"][disease])
            println("      - $disease ($pub_count publications)")
        end
        if disease_count > 3
            println("      ... and $(disease_count - 3) more diseases")
        end
    else
        println("    ℹ️  No disease associations found")
    end
    
    return Dict(
        "drug_name" => drug_name,
        "drugbank_indication" => indication,
        "search_status" => "success",
        "count" => count,
        "pmids" => fetch_result["pmids_fetched"],
        "publications_analyzed" => publications,
        "disease_analysis" => disease_analysis
    )
end

"""
    process_drug_memory_efficient(drug_name::String, indication::String, disease_headings::Set{String}, output_dir::String) -> Dict

Memory-efficient processing pipeline for a single drug that immediately saves results and returns minimal summary.
"""
function process_drug_memory_efficient(drug_name::String, indication::String, disease_headings::Set{String}, output_dir::String)
    println("  Searching PubMed...")
    
    # Step 1: Search PubMed with caching
    search_result = search_pubmed_cached(drug_name; retmax=MAX_RESULTS_PER_DRUG)
    
    if search_result["status"] != "success"
        # Create minimal error result
        minimal_result = Dict(
            "drug_name" => drug_name,
            "drugbank_indication" => indication,
            "search_status" => search_result["status"],
            "search_error" => get(search_result, "error", "Unknown error"),
            "count" => 0,
            "disease_associations_count" => 0,
            "publications_analyzed_count" => 0
        )
        
        # Save individual file immediately
        save_individual_drug_result(create_full_result_for_storage(minimal_result), output_dir)
        return minimal_result
    end
    
    pmids = search_result["pmids"]
    count = search_result["count"]
    
    println("    ✓ Found $count publications ($(length(pmids)) PMIDs retrieved)")
    
    if isempty(pmids)
        minimal_result = Dict(
            "drug_name" => drug_name,
            "drugbank_indication" => indication,
            "search_status" => "success",
            "count" => count,
            "disease_associations_count" => 0,
            "publications_analyzed_count" => 0
        )
        
        save_individual_drug_result(create_full_result_for_storage(minimal_result), output_dir)
        return minimal_result
    end
    
    # Step 2: Fetch publication details
    println("  Fetching publication details...")
    fetch_result = fetch_publication_details_optimized(pmids)
    
    if fetch_result["status"] != "success"
        minimal_result = Dict(
            "drug_name" => drug_name,
            "drugbank_indication" => indication,
            "search_status" => "success",
            "count" => count,
            "fetch_error" => get(fetch_result, "error", "Unknown error"),
            "disease_associations_count" => 0,
            "publications_analyzed_count" => 0
        )
        
        save_individual_drug_result_optimized(create_full_result_for_storage(minimal_result), output_dir)
        return minimal_result
    end
    
    # Step 3: Extract MeSH descriptors
    println("  Extracting MeSH descriptors...")
    publications = extract_mesh_descriptors_optimized(fetch_result["xml_data"])
    println("    ✓ Analyzed $(length(publications)) publications")
    
    # Step 4: Analyze disease associations
    println("  Analyzing disease associations...")
    disease_analysis = analyze_disease_associations(publications, disease_headings, drug_name)
    
    # Create full result for storage
    full_result = Dict(
        "drug_name" => drug_name,
        "drugbank_indication" => indication,
        "search_status" => "success",
        "count" => count,
        "pmids" => fetch_result["pmids_fetched"],
        "publications_analyzed" => publications,
        "disease_analysis" => disease_analysis
    )
    
    # Save individual file immediately with optimized function
    save_individual_drug_result_optimized(full_result, output_dir)
    
    # Display findings
    disease_count = disease_analysis["summary"]["unique_diseases_found"]
    if disease_count > 0
        println("    🔬 Found associations with $disease_count disease(s):")
        matched_diseases = disease_analysis["summary"]["matched_diseases"]
        for disease in matched_diseases[1:min(3, length(matched_diseases))]
            pub_count = length(disease_analysis["disease_associations"][disease])
            println("      - $disease ($pub_count publications)")
        end
        if disease_count > 3
            println("      ... and $(disease_count - 3) more diseases")
        end
    else
        println("    ℹ️  No disease associations found")
    end
    
    # Return minimal summary only (not full data)
    return Dict(
        "drug_name" => drug_name,
        "search_status" => "success",
        "count" => count,
        "disease_associations_count" => disease_count,
        "publications_analyzed_count" => length(publications),
        "drug_disease_publications" => disease_analysis["drug_disease_publications"]  # Keep this for aggregation
    )
end

"""
    create_full_result_for_storage(minimal_result::Dict) -> Dict

Convert minimal result to full format for storage.
"""
function create_full_result_for_storage(minimal_result::Dict)
    # Add missing fields for consistency
    full_result = copy(minimal_result)
    
    if !haskey(full_result, "pmids")
        full_result["pmids"] = String[]
    end
    if !haskey(full_result, "publications_analyzed")
        full_result["publications_analyzed"] = []
    end
    if !haskey(full_result, "disease_analysis")
        full_result["disease_analysis"] = Dict("status" => "no_analysis")
    end
    
    return full_result
end

"""
    generate_summary_from_files(output_dir::String, individual_files::Vector{String})

Generate comprehensive summary files by reading individual drug result files.
This approach is memory-efficient as it processes files one at a time.
"""
function generate_summary_from_files(output_dir::String, individual_files::Vector{String})
    output_json = "drug_disease_associations.json"
    output_txt = "drug_disease_associations.txt"
    publications_json = "drug_disease_publications.json"
    
    # Collect minimal results and drug-disease publications
    results_summary = []
    all_drug_disease_publications = Dict{String, Dict}()
    
    println("  📄 Processing $(length(individual_files)) individual files...")
    
    for (i, filepath) in enumerate(individual_files)
        try
            # Read individual file
            file_content = JSON3.read(read(filepath, String))
            result = file_content.result
            
            # Create minimal summary for comprehensive JSON
            minimal_result = Dict(
                "drug_name" => result["drug_name"],
                "drugbank_indication" => get(result, "drugbank_indication", ""),
                "search_status" => get(result, "search_status", "unknown"),
                "count" => get(result, "count", 0),
                "disease_associations_count" => 0,
                "publications_analyzed_count" => 0
            )
            
            # Add disease analysis summary if available
            if haskey(result, "disease_analysis") && haskey(result["disease_analysis"], "summary")
                summary = result["disease_analysis"]["summary"]
                minimal_result["disease_associations_count"] = get(summary, "unique_diseases_found", 0)
                minimal_result["publications_analyzed_count"] = get(summary, "total_publications_analyzed", 0)
                minimal_result["disease_analysis_summary"] = summary
            end
            
            push!(results_summary, minimal_result)
            
            # Collect drug-disease publications (safely)
            if haskey(result, "disease_analysis") && 
               haskey(result["disease_analysis"], "drug_disease_publications")
                
                drug_publications = result["disease_analysis"]["drug_disease_publications"]
                # Convert JSON3 object to regular Dict
                for (key, value) in pairs(drug_publications)
                    key_str = string(key)
                    # Convert value to regular Dict structure
                    if haskey(value, "publications") && haskey(value, "drug_name") && haskey(value, "disease_name")
                        value_dict = Dict(
                            "drug_name" => value["drug_name"],
                            "disease_name" => value["disease_name"],
                            "publications" => Dict(string(k) => Dict(
                                "pmid" => v["pmid"],
                                "title" => v["title"],
                                "abstract" => v["abstract"],
                                "qualifiers" => collect(v["qualifiers"])
                            ) for (k, v) in pairs(value["publications"]))
                        )
                        all_drug_disease_publications[key_str] = value_dict
                    end
                end
            end
            
            if i % 10 == 0 || i == length(individual_files)
                println("    ✓ Processed $i/$(length(individual_files)) files")
            end
            
        catch e
            println("    ⚠️  Warning: Error reading $(basename(filepath)): $e")
        end
    end
    
    # Generate comprehensive JSON summary
    save_results_summary(results_summary, output_json, output_txt)
    
    # Generate drug-disease publications file
    save_drug_disease_publications_summary(all_drug_disease_publications, publications_json)
    
    println("  ✅ Summary files generated successfully")
end

"""
    save_results_summary(results_summary::Vector, filename_json::String, filename_txt::String)

Save summary results to both JSON and text files.
"""
function save_results_summary(results_summary::Vector, filename_json::String, filename_txt::String)
    # Prepare output data with metadata
    output_data = Dict(
        "metadata" => Dict(
            "generated_on" => string(now()),
            "total_drugs_analyzed" => length(results_summary),
            "max_drugs_limit" => MAX_DRUGS,
            "max_results_per_drug" => MAX_RESULTS_PER_DRUG,
            "max_pmids_analyzed_per_drug" => MAX_PMIDS_TO_ANALYZE,
            "description" => "Comprehensive PubMed drug-disease association analysis (generated from individual files)",
            "note" => "This summary was generated from individual drug files to minimize memory usage"
        ),
        "results_summary" => results_summary
    )
    
    # Save JSON
    open(filename_json, "w") do file
        write(file, JSON3.write(output_data))
    end
    println("    📄 Saved comprehensive results to: $filename_json")
    
    # Save human-readable summary
    open(filename_txt, "w") do file
        write(file, "Drug-Disease Association Analysis\n")
        write(file, "Generated on: $(now())\n")
        write(file, "Total drugs analyzed: $(length(results_summary))\n")
        write(file, "=" ^ 50 * "\n\n")
        
        successful_analyses = filter(r -> haskey(r, "disease_analysis_summary"), results_summary)
        
        if !isempty(successful_analyses)
            write(file, "DRUG-DISEASE ASSOCIATIONS SUMMARY\n")
            write(file, "=" ^ 35 * "\n\n")
            
            for (i, result) in enumerate(successful_analyses)
                drug_name = result["drug_name"]
                pub_count = result["count"]
                drugbank_indication = result["drugbank_indication"]
                disease_count = result["disease_associations_count"]
                pubs_analyzed = result["publications_analyzed_count"]
                
                write(file, "$i. $drug_name\n")
                write(file, "   FDA Indication: $(drugbank_indication[1:min(100, length(drugbank_indication))])...\n")
                write(file, "   Publications found: $pub_count\n")
                write(file, "   Publications analyzed: $pubs_analyzed\n")
                write(file, "   Disease associations found: $disease_count\n")
                
                if haskey(result, "disease_analysis_summary") && haskey(result["disease_analysis_summary"], "matched_diseases")
                    matched_diseases = result["disease_analysis_summary"]["matched_diseases"]
                    if !isempty(matched_diseases)
                        write(file, "   Associated diseases: $(join(matched_diseases[1:min(3, length(matched_diseases))], ", "))")
                        if length(matched_diseases) > 3
                            write(file, ", ... and $(length(matched_diseases) - 3) more")
                        end
                        write(file, "\n")
                    end
                end
                
                write(file, "\n")
            end
            
            # Overall statistics
            total_diseases = sum(r["disease_associations_count"] for r in successful_analyses; init=0)
            total_analyzed_pubs = sum(r["publications_analyzed_count"] for r in successful_analyses; init=0)
            
            write(file, "\nOVERALL STATISTICS:\n")
            write(file, "-" ^ 20 * "\n")
            write(file, "Total publications analyzed: $total_analyzed_pubs\n")
            write(file, "Total unique disease associations: $total_diseases\n")
            write(file, "Average disease associations per drug: $(length(successful_analyses) > 0 ? round(total_diseases / length(successful_analyses), digits=1) : 0)\n")
        end
        
        # Error summary
        failed_searches = filter(r -> get(r, "search_status", "") != "success", results_summary)
        no_disease_analysis = filter(r -> !haskey(r, "disease_analysis_summary"), results_summary)
        
        if !isempty(failed_searches) || !isempty(no_disease_analysis)
            write(file, "\nERRORS AND WARNINGS:\n")
            write(file, "-" ^ 20 * "\n")
            write(file, "Failed searches: $(length(failed_searches))\n")
            write(file, "Drugs without disease analysis: $(length(no_disease_analysis))\n")
        end
    end
    println("    📄 Saved summary to: $filename_txt")
end

"""
    save_drug_disease_publications_summary(drug_disease_publications::Dict, filename::String)

Save detailed drug-disease publication dictionaries for next pipeline step.
"""
function save_drug_disease_publications_summary(drug_disease_publications::Dict, filename::String)
    # Prepare organized data structure
    organized_data = Dict(
        "metadata" => Dict(
            "generated_on" => string(now()),
            "total_drug_disease_pairs" => length(drug_disease_publications),
            "description" => "Detailed publications for each drug-disease pairing found in PubMed analysis",
            "format_notes" => Dict(
                "structure" => "drug_name||disease_name => {drug_name, disease_name, publications: {pmid => {pmid, title, abstract, qualifiers}}}",
                "pmid_format" => "String (PubMed ID)",
                "title_format" => "String (Article title from PubMed)",
                "abstract_format" => "String (Article abstract, may be 'No abstract available')",
                "qualifiers_format" => "Array of Strings (MeSH qualifiers for the disease term)"
            )
        ),
        "drug_disease_publications" => drug_disease_publications
    )
    
    # Create summary statistics
    total_publications = 0
    drug_count = Set{String}()
    disease_count = Set{String}()
    
    for (key, data) in drug_disease_publications
        total_publications += length(data["publications"])
        push!(drug_count, data["drug_name"])
        push!(disease_count, data["disease_name"])
    end
    
    organized_data["summary"] = Dict(
        "total_unique_publications" => total_publications,
        "unique_drugs_with_disease_associations" => length(drug_count),
        "unique_diseases_found" => length(disease_count),
        "average_publications_per_pairing" => total_publications > 0 ? round(total_publications / length(drug_disease_publications), digits=2) : 0
    )
    
    # Save to JSON file
    open(filename, "w") do file
        write(file, JSON3.write(organized_data))
    end
    
    println("    📄 Saved detailed drug-disease publications to: $filename")
    if length(drug_disease_publications) > 0
        println("      Total drug-disease pairs: $(length(drug_disease_publications))")
        println("      Total publications: $total_publications")
        println("      Unique drugs with associations: $(length(drug_count))")
        println("      Unique diseases found: $(length(disease_count))")
    end
    
    # Create human-readable index file
    index_filename = replace(filename, ".json" => "_index.txt")
    open(index_filename, "w") do file
        write(file, "Drug-Disease Publications Index\n")
        write(file, "Generated on: $(now())\n")
        write(file, "=" ^ 50 * "\n\n")
        
        write(file, "SUMMARY:\n")
        write(file, "Total drug-disease pairs: $(length(drug_disease_publications))\n")
        write(file, "Total publications: $total_publications\n")
        write(file, "Unique drugs: $(length(drug_count))\n")
        write(file, "Unique diseases: $(length(disease_count))\n\n")
        
        if length(drug_disease_publications) > 0
            write(file, "DRUG-DISEASE PAIRS WITH PUBLICATION COUNTS:\n")
            write(file, "=" ^ 45 * "\n")
            
            # Sort by number of publications (descending)
            sorted_pairs = sort(collect(drug_disease_publications), 
                               by = x -> length(x[2]["publications"]), rev=true)
            
            for (i, (key, data)) in enumerate(sorted_pairs)
                drug = data["drug_name"]
                disease = data["disease_name"]
                pub_count = length(data["publications"])
                
                write(file, "$i. $drug → $disease\n")
                write(file, "   Publications: $pub_count\n")
                write(file, "   Sample PMIDs: ")
                
                pmids = collect(keys(data["publications"]))
                sample_pmids = pmids[1:min(3, length(pmids))]
                write(file, join(sample_pmids, ", "))
                if length(pmids) > 3
                    write(file, ", ... ($(length(pmids) - 3) more)")
                end
                write(file, "\n\n")
            end
        end
    end
    
    println("      Index saved to: $index_filename")
end

"""
    estimate_runtime(total_drugs::Int, avg_time_per_drug::Float64=15.0) -> String

Estimate total runtime based on number of drugs and average processing time.
"""
function estimate_runtime(total_drugs::Int, avg_time_per_drug::Float64=15.0)
    total_seconds = total_drugs * avg_time_per_drug
    hours = floor(Int, total_seconds / 3600)
    minutes = floor(Int, (total_seconds % 3600) / 60)
    
    if hours > 0
        return "~$(hours)h $(minutes)m"
    else
        return "~$(minutes)m"
    end
end

"""
    cleanup_optimizations()

Clean up resources and caches used by optimization functions.
"""
function cleanup_optimizations()
    # Clear cache if it gets too large
    if length(GLOBAL_CACHE) > 1000
        println("🧹 Clearing cache ($(length(GLOBAL_CACHE)) entries)")
        empty!(GLOBAL_CACHE)
    end
    
    # Final flush of write buffer
    writes_flushed = flush_write_buffer!(WRITE_BUFFER)
    if writes_flushed > 0
        println("🧹 Final cleanup: flushed $writes_flushed buffered files")
    end
end

"""
    should_skip_drug(drug_name::String, output_dir::String) -> Bool

Check if a drug has already been processed to allow for resuming interrupted runs.
"""
function should_skip_drug(drug_name::String, output_dir::String)
    safe_filename = sanitize_filename(drug_name)
    filepath = joinpath(output_dir, "$(safe_filename).json")
    
    if isfile(filepath)
        try
            # Check if file contains valid data
            file_content = JSON3.read(read(filepath, String))
            if haskey(file_content, "result") && haskey(file_content.result, "drug_name")
                return true  # File exists and contains valid result
            end
        catch e
            # If file is corrupted, reprocess
            println("  🔄 File corrupted, will reprocess: $(basename(filepath))")
            return false
        end
    end
    
    return false  # File doesn't exist or is invalid
end

"""
    get_already_processed_drugs(output_dir::String) -> Set{String}

Get a set of drug names that have already been processed.
"""
function get_already_processed_drugs(output_dir::String)
    processed_drugs = Set{String}()
    
    if !isdir(output_dir)
        return processed_drugs
    end
    
    # Get all JSON files in the output directory
    json_files = filter(f -> endswith(f, ".json"), readdir(output_dir))
    
    for filename in json_files
        filepath = joinpath(output_dir, filename)
        try
            # Read and validate the file
            file_content = JSON3.read(read(filepath, String))
            if haskey(file_content, "result") && haskey(file_content.result, "drug_name")
                drug_name = file_content.result["drug_name"]
                push!(processed_drugs, drug_name)
            end
        catch e
            # Skip corrupted files
            println("⚠️  Warning: Corrupted file found: $filename (will be reprocessed)")
        end
    end
    
    return processed_drugs
end

"""
    get_processing_status(drugs_dict::Dict, output_dir::String) -> Dict

Get detailed processing status for all drugs.
"""
function get_processing_status(drugs_dict::Dict, output_dir::String)
    already_processed = get_already_processed_drugs(output_dir)
    total_drugs = length(drugs_dict)
    remaining_drugs = filter(drug_name -> drug_name ∉ already_processed, keys(drugs_dict))
    
    return Dict(
        "total_drugs" => total_drugs,
        "already_processed" => length(already_processed),
        "remaining_to_process" => length(remaining_drugs),
        "processed_drugs" => already_processed,
        "remaining_drugs" => remaining_drugs,
        "completion_percentage" => round(length(already_processed) / total_drugs * 100, digits=1)
    )
end

# ...existing code...

"""
    main()

Main function to run the complete PubMed drug indications analysis pipeline with resume capability.
"""
function main()
    println("PubMed Drug Indications Analysis")
    println("=" ^ 35)
    println("Comprehensive drug-disease association analysis using PubMed and MeSH")
    println()
    
    try
        # Load data
        println("Loading required data...")
        
        # Load approved drugs
        drugs_dict = load_approved_drugs()
        println("✓ Loaded $(length(drugs_dict)) approved drugs")
        
        # Load MeSH disease headings
        mesh_file = "mesh_t047_headings.jl"
        disease_headings = load_mesh_disease_headings(mesh_file)
        println("✓ Loaded $(length(disease_headings)) MeSH T047 disease headings")
        
        # Setup output directory
        output_dir = "drug_pubmed_refs"
        println("📁 Output directory: $output_dir")
        if !isdir(output_dir)
            mkpath(output_dir)
            println("✓ Directory created")
        else
            println("✓ Directory already exists")
        end
        
        # Check processing status and implement resume functionality
        println("\n🔍 Checking processing status...")
        status = get_processing_status(drugs_dict, output_dir)
        
        println("📊 Processing Status:")
        println("  • Total drugs: $(status["total_drugs"])")
        println("  • Already processed: $(status["already_processed"])")
        println("  • Remaining to process: $(status["remaining_to_process"])")
        println("  • Completion: $(status["completion_percentage"])%")
        
        if status["already_processed"] > 0
            println("\n🔄 RESUME MODE: Found $(status["already_processed"]) already processed drugs")
            println("   Will skip these and process remaining $(status["remaining_to_process"]) drugs")
        else
            println("\n🆕 FRESH START: No previously processed drugs found")
        end
        
        # Display current mode and settings
        if DEMO_MODE
            println("\n⚡ DEMONSTRATION MODE - Limited to $MAX_DRUGS drugs, $MAX_RESULTS_PER_DRUG results/drug, $MAX_PMIDS_TO_ANALYZE PMIDs analyzed/drug")
        else
            println("\n🚀 PRODUCTION MODE - Processing all $(length(drugs_dict)) drugs with no limits")
            if status["remaining_to_process"] > 0
                estimated_time = estimate_runtime(min(status["remaining_to_process"], MAX_DRUGS))
                println("📊 Estimated runtime for remaining drugs: $estimated_time")
            end
        end
        println()
        
        # Filter to only unprocessed drugs and apply demo limit
        unprocessed_drugs = [(name, indication) for (name, indication) in drugs_dict if name ∉ status["processed_drugs"]]
        drug_list = unprocessed_drugs[1:min(MAX_DRUGS, length(unprocessed_drugs))]
        
        if isempty(drug_list)
            println("✅ All drugs have been processed! Generating final summary...")
            
            # Get all individual files for summary generation
            all_files = [joinpath(output_dir, f) for f in readdir(output_dir) if endswith(f, ".json")]
            generate_summary_from_files(output_dir, all_files)
            
            println("🎉 Analysis already complete!")
            return
        end
        
        println("📋 Will process $(length(drug_list)) drugs ($(length(unprocessed_drugs) - length(drug_list)) skipped due to limits)")
        
        # Process each unprocessed drug
        individual_files = Vector{String}()  # Track individual files created
        
        # Summary counters (instead of storing full results)
        drugs_processed = 0
        successful_searches = 0
        successful_analyses = 0
        total_diseases = 0
        total_pubs_analyzed = 0
        skipped_drugs = 0
        
        for (i, (drug_name, indication)) in enumerate(drug_list)
            println("[$i/$(length(drug_list))] Processing: $drug_name")
            
            # Double-check if drug should be skipped (in case files were added during processing)
            if should_skip_drug(drug_name, output_dir)
                println("  ⏭️  Skipping $(drug_name) (already processed)")
                skipped_drugs += 1
                
                # Still add to individual_files list for summary generation
                safe_filename = sanitize_filename(drug_name)
                individual_file = joinpath(output_dir, "$(safe_filename).json")
                push!(individual_files, individual_file)
                continue
            end
            
            result = process_drug_memory_efficient(drug_name, indication, disease_headings, output_dir)
            drugs_processed += 1
            
            # Update summary counters
            if get(result, "search_status", "") == "success"
                successful_searches += 1
            end
            
            # Check if drug-disease publications are available for aggregation
            if haskey(result, "drug_disease_publications")
                successful_analyses += 1
                total_diseases += get(result, "disease_associations_count", 0)
                total_pubs_analyzed += get(result, "publications_analyzed_count", 0)
            end
            
            # Save individual drug result to separate file (done in process_drug_memory_efficient)
            safe_filename = sanitize_filename(drug_name)
            individual_file = joinpath(output_dir, "$(safe_filename).json")
            push!(individual_files, individual_file)
            println("  💾 Saved to: $(basename(individual_file))")
            
            # Flush write buffer periodically for better performance
            if i % 5 == 0
                writes_flushed = flush_write_buffer!(WRITE_BUFFER)
                if writes_flushed > 0
                    println("  📤 Flushed $writes_flushed buffered files")
                end
            end
            
            # Minimal delay to be respectful to NCBI servers (reduced for efficiency)
            sleep(0.2)
            println()
        end
        
        # Final flush of any remaining buffered writes
        final_writes = flush_write_buffer!(WRITE_BUFFER)
        if final_writes > 0
            println("📤 Final flush: $final_writes files written")
        end
        
        # Get all processed files (including previously processed ones) for summary generation
        all_files = [joinpath(output_dir, f) for f in readdir(output_dir) if endswith(f, ".json")]
        
        # Generate summary files from all individual files
        println("📊 Generating summary files from all drug results...")
        generate_summary_from_files(output_dir, all_files)
        
        # Final summary
        total_processed_now = drugs_processed
        total_skipped = skipped_drugs
        final_status = get_processing_status(drugs_dict, output_dir)
        
        println()
        println("ANALYSIS COMPLETED!")
        println("=" ^ 20)
        println("This session:")
        println("  Drugs processed: $total_processed_now")
        println("  Drugs skipped (already done): $total_skipped")
        println("  Successful PubMed searches: $successful_searches")
        println("  Successful disease analyses: $successful_analyses")
        println("  Total publications analyzed: $total_pubs_analyzed")
        println("  Total disease associations found: $total_diseases")
        println()
        println("Overall progress:")
        println("  Total drugs in dataset: $(final_status["total_drugs"])")
        println("  Total drugs processed: $(final_status["already_processed"])")
        println("  Completion: $(final_status["completion_percentage"])%")
        
        if final_status["remaining_to_process"] > 0
            println("  Remaining to process: $(final_status["remaining_to_process"]) drugs")
            println("  👉 Run the program again to continue processing remaining drugs")
        else
            println("  🎉 All drugs have been processed!")
        end
        
        println()
        println("Output files:")
        println("  ✓ drug_disease_associations.json - Comprehensive JSON results with metadata")
        println("  ✓ drug_disease_associations.txt - Human-readable summary")
        println("  ✓ drug_disease_publications.json - Detailed drug-disease publications with PMIDs, titles, and abstracts")
        println("  ✓ drug_disease_publications_index.txt - Human-readable index of drug-disease pairs")
        println("  📁 $output_dir/ - Individual drug analysis files ($(length(all_files)) files)")
        for file in all_files[1:min(3, length(all_files))]
            println("    - $(basename(file))")
        end
        if length(all_files) > 3
            println("    ... and $(length(all_files) - 3) more files")
        end
        println()
        println("This unified pipeline has successfully:")
        println("  • Searched PubMed for approved drug publications")
        println("  • Fetched detailed publication data including MeSH descriptors")
        println("  • Analyzed disease associations using MeSH T047 terms")
        println("  • Generated comprehensive drug-disease association data")
        println("  • Stored detailed publication information (PMID, title, abstract) for each drug-disease pairing")
        println("  • Created individual analysis files for each drug in $output_dir/ directory")
        println("  • Implemented resume capability to skip already processed drugs")
        
        # Cleanup optimizations
        cleanup_optimizations()
        
    catch e
        println("Error: $e")
        println()
        println("Make sure you have run:")
        println("  1. approved_drugs_extractor.jl (to generate approved drugs data)")
        println("  2. mesh_t047_extractor.jl (to generate MeSH disease headings)")
        exit(1)
    end
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end