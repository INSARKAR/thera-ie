#!/usr/bin/env julia

# Batch Phase 1 PubMed Search Cleanup Worker
# Fresh extraction with fixed issues
# Usage: julia batch_phase1_pubmed_cleanup_worker.jl <start_index> <batch_size>

using HTTP, JSON3, Dates

# Get the job parameters
if length(ARGS) != 2
    println("Usage: julia batch_phase1_pubmed_cleanup_worker.jl <start_index> <batch_size>")
    exit(1)
end

start_index = parse(Int, ARGS[1])
batch_size = parse(Int, ARGS[2])

println("Starting cleanup batch worker:")
println("  Start index: $start_index")
println("  Batch size: $batch_size")

# Include necessary modules
include("phase1_step1_approved_drugs_extractor.jl")

# Load all drugs from file
all_drugs = String[]
if isfile("all_drugs_for_cleanup.txt")
    all_drugs = readlines("all_drugs_for_cleanup.txt")
else
    println("Error: all_drugs_for_cleanup.txt not found.")
    exit(1)
end

println("Total drugs for cleanup: $(length(all_drugs))")

# Calculate the subset to process for this worker
end_index = min(start_index + batch_size - 1, length(all_drugs))
if start_index > length(all_drugs)
    println("Start index $start_index exceeds total drugs ($(length(all_drugs))). Nothing to process.")
    exit(0)
end

drugs_to_process = all_drugs[start_index:end_index]
println("Processing $(length(drugs_to_process)) drugs (indices $start_index to $end_index)")

# Extract MeSH descriptors from XML
function extract_mesh_descriptors_from_xml(article_xml::AbstractString)
    descriptors = String[]
    
    # Look for MeshHeadingList section in the full article XML
    mesh_section_pattern = r"<MeshHeadingList>(.*?)</MeshHeadingList>"s
    mesh_section_match = match(mesh_section_pattern, article_xml)
    
    if mesh_section_match !== nothing
        mesh_section = String(mesh_section_match.captures[1])
        
        # Extract all DescriptorName entries
        mesh_pattern = r"<DescriptorName[^>]*>(.*?)</DescriptorName>"s
        mesh_matches = eachmatch(mesh_pattern, mesh_section)
        
        for mesh_match in mesh_matches
            descriptor = String(mesh_match.captures[1])
            push!(descriptors, descriptor)
        end
    end
    
    return descriptors
end

# Parse PubMed XML batch
function parse_pubmed_xml_content(xml_content::String, pmids::Vector)
    publications = []
    article_pattern = r"<PubmedArticle>(.*?)</PubmedArticle>"s
    articles = eachmatch(article_pattern, xml_content)
    
    for (i, article_match) in enumerate(articles)
        if i > length(pmids)
            break
        end
        
        # Get the full PubmedArticle content which includes MedlineCitation
        full_article_xml = String(article_match.captures[1])
        pmid = String(pmids[i])
        
        # Extract title
        title = ""
        title_match = match(r"<ArticleTitle>(.*?)</ArticleTitle>"s, full_article_xml)
        if title_match !== nothing
            title = String(title_match.captures[1])
            # Clean HTML entities
            title = replace(title, "&lt;" => "<", "&gt;" => ">", "&amp;" => "&", "&quot;" => "\"")
        end
        
        # Extract abstract
        abstract = ""
        abstract_match = match(r"<AbstractText[^>]*>(.*?)</AbstractText>"s, full_article_xml)
        if abstract_match !== nothing
            abstract = String(abstract_match.captures[1])
            # Clean HTML entities
            abstract = replace(abstract, "&lt;" => "<", "&gt;" => ">", "&amp;" => "&", "&quot;" => "\"")
        end
        
        # Extract ALL MeSH descriptors (no filtering)
        mesh_descriptors = extract_mesh_descriptors_from_xml(full_article_xml)
        
        publication = Dict(
            "pmid" => pmid,
            "title" => title,
            "abstract" => abstract,
            "mesh_descriptors" => mesh_descriptors
        )
        
        push!(publications, publication)
    end
    
    return publications
end

# Search PubMed for a specific drug with comprehensive results
function search_pubmed_for_drug_comprehensive(drug_name::String)
    println("$drug_name: Starting comprehensive PubMed search...")
    
    encoded_term = HTTP.URIs.escapeuri("\"$drug_name\"[tw] OR \"$drug_name\"[tiab] OR \"$drug_name\"[ot]")
    
    # Step 1: Get total count first
    count_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=$encoded_term&retmax=0&retmode=json"
    
    try
        response = HTTP.get(count_url)
        if response.status != 200
            println("$drug_name: Error getting count (status: $(response.status))")
            return nothing
        end
        
        data = JSON3.read(response.body)
        total_count = parse(Int, data.esearchresult.count)
        
        if total_count == 0
            println("$drug_name: No publications found")
            return Dict(
                "drug_name" => drug_name,
                "timestamp" => string(now()),
                "result" => Dict(
                    "total_publications_found" => 0,
                    "publications_analyzed" => [],
                    "search_strategy" => "comprehensive_pubmed_search"
                )
            )
        end
        
        println("$drug_name: Found $total_count publications, retrieving ALL...")
        
        # Step 2: Retrieve ALL PMIDs using pagination
        max_retmax = 9999  # Maximum per request
        all_pmids = String[]
        
        for start_pos in 0:max_retmax:(total_count-1)
            current_retmax = min(max_retmax, total_count - start_pos)
            search_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=$encoded_term&retstart=$start_pos&retmax=$current_retmax&retmode=json"
            
            try
                search_response = HTTP.get(search_url)
                if search_response.status == 429
                    println("$drug_name: Rate limited, waiting 3 seconds...")
                    sleep(3)
                    search_response = HTTP.get(search_url)
                end
                
                if search_response.status != 200
                    println("$drug_name: Error in search batch (status: $(search_response.status))")
                    continue
                end
                
                data = JSON3.read(search_response.body)
                if haskey(data.esearchresult, "idlist") && !isempty(data.esearchresult.idlist)
                    # Ensure PMIDs are converted to strings
                    pmid_strings = [String(pmid) for pmid in data.esearchresult.idlist]
                    append!(all_pmids, pmid_strings)
                end
                
                # Rate limiting between pagination requests
                sleep(0.5)
            catch e
                println("$drug_name: Error fetching batch starting at $start_pos: $e")
                continue
            end
        end
        
        println("$drug_name: Retrieved $(length(all_pmids)) PMIDs, fetching publication details...")
        
        # Step 3: Fetch publication details for ALL PMIDs
        publications = []
        fetch_batch_size = 100  # Conservative batch size for efetch
        
        for i in 1:fetch_batch_size:length(all_pmids)
            batch_end = min(i + fetch_batch_size - 1, length(all_pmids))
            batch_pmids = all_pmids[i:batch_end]
            pmid_string = join(batch_pmids, ",")
            
            fetch_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=$pmid_string&retmode=xml"
            
            try
                fetch_response = HTTP.get(fetch_url)
                if fetch_response.status == 429
                    println("$drug_name: Rate limited during fetch, waiting 3 seconds...")
                    sleep(3)
                    fetch_response = HTTP.get(fetch_url)
                end
                
                if fetch_response.status != 200
                    println("Warning: Error fetching batch for $drug_name: HTTP $(fetch_response.status)")
                    continue
                end
                
                xml_content = String(fetch_response.body)
                batch_publications = parse_pubmed_xml_content(xml_content, batch_pmids)
                append!(publications, batch_publications)
                
                # Progress update for large datasets
                if length(all_pmids) > 100
                    println("$drug_name: Processed $(length(publications)) / $(length(all_pmids)) publications...")
                end
                
                # Aggressive rate limiting to avoid API issues
                sleep(1.0)
                
            catch e
                println("Warning: Error fetching batch for $drug_name: $e")
                continue
            end
        end
        
        println("$drug_name: Completed! Retrieved $(length(publications)) publications with full content")
        
        return Dict(
            "drug_name" => drug_name,
            "timestamp" => string(now()),
            "result" => Dict(
                "total_publications_found" => total_count,
                "publications_analyzed" => publications,
                "search_strategy" => "comprehensive_pubmed_search"
            )
        )
        
    catch e
        println("$drug_name: Error in comprehensive search: $e")
        return nothing
    end
end

# Validate result completeness
function validate_result(result, drug_name::String)
    if result === nothing
        return (false, "no_result_returned")
    end
    
    if !haskey(result, "result")
        return (false, "missing_result_key")
    end
    
    result_data = result["result"]
    total_found = get(result_data, "total_publications_found", 0)
    pubs_analyzed = get(result_data, "publications_analyzed", [])
    
    # If publications were found but none analyzed, it's incomplete
    if total_found > 0 && length(pubs_analyzed) == 0
        return (false, "empty_publications_despite_results")
    end
    
    # For drugs with many publications, check if we got a reasonable portion
    if total_found > 100 && length(pubs_analyzed) < (total_found * 0.1)
        return (false, "too_few_publications_retrieved")
    end
    
    return (true, "complete")
end

# Process each drug in the batch
println("🚀 Starting drug processing with validation...")

processed_count = 0
for drug_name in drugs_to_process
    try
        safe_filename = replace(drug_name, " " => "_")
        output_file = "phase1_drug_pubmed_refs/$(safe_filename).json"
        
        # Check if file already exists and is valid
        skip_processing = false
        if isfile(output_file)
            try
                existing_content = read(output_file, String)
                existing_data = JSON3.read(existing_content)
                is_valid, reason = validate_result(existing_data, drug_name)
                
                if is_valid
                    println("✅ $drug_name: Already processed with valid data, skipping...")
                    processed_count += 1
                    skip_processing = true
                else
                    println("🔄 $drug_name: Found incomplete result ($reason), reprocessing...")
                end
            catch e
                println("🔄 $drug_name: Found corrupted file, reprocessing...")
            end
        end
        
        if !skip_processing
            max_retries = 2
            result = nothing
            
            for attempt in 1:max_retries
                if attempt > 1
                    println("🔄 $drug_name: Retry attempt $attempt...")
                    sleep(5.0)  # Extra delay before retry
                end
                
                # Search PubMed for this drug
                result = search_pubmed_for_drug_comprehensive(drug_name)
                
                # Validate the result
                is_valid, reason = validate_result(result, drug_name)
                
                if is_valid
                    break
                else
                    println("⚠️  $drug_name: Incomplete result on attempt $attempt ($reason)")
                    if attempt == max_retries
                        println("❌ $drug_name: Failed after $max_retries attempts")
                    end
                end
            end
            
            if result !== nothing
                # Create output directory if it doesn't exist
                mkpath("phase1_drug_pubmed_refs")
                
                # Write result to JSON file
                open(output_file, "w") do f
                    JSON3.pretty(f, result)
                end
                
                is_valid, reason = validate_result(result, drug_name)
                if is_valid
                    processed_count += 1
                    println("✅ $drug_name: Saved complete results to $output_file")
                else
                    println("⚠️  $drug_name: Saved incomplete results ($reason) to $output_file")
                end
            else
                println("❌ $drug_name: Failed to process")
            end
        end
        
        # Rate limiting between drugs
        sleep(2.0)  # Increased delay for better API compliance
        
    catch e
        println("❌ Error processing $drug_name: $e")
        continue
    end
end

println("\n🎉 Batch cleanup worker completed!")
println("📊 Processed $processed_count drugs successfully")
println("📂 Results saved in phase1_drug_pubmed_refs/")