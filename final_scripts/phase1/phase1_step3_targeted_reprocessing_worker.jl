#!/usr/bin/env julia

# Batch Phase 1 PubMed Search Worker for Empty Results
# Reprocesses only drugs with empty publications_analyzed arrays
# Usage: julia batch_phase1_empty_results_worker.jl <start_index> <batch_size>

using HTTP, JSON3, Dates

# Get the job parameters
if length(ARGS) != 2
    println("Usage: julia batch_phase1_empty_results_worker.jl <start_index> <batch_size>")
    exit(1)
end

start_index = parse(Int, ARGS[1])
batch_size = parse(Int, ARGS[2])

println("Starting empty results worker:")
println("  Start index: $start_index")
println("  Batch size: $batch_size")

# Load empty results drugs from file
empty_results_drugs = String[]
if isfile("empty_results_drugs.txt")
    empty_results_drugs = readlines("empty_results_drugs.txt")
else
    println("Error: empty_results_drugs.txt not found.")
    exit(1)
end

println("Total drugs with empty results: $(length(empty_results_drugs))")

# Calculate the subset to process for this worker
end_index = min(start_index + batch_size - 1, length(empty_results_drugs))
if start_index > length(empty_results_drugs)
    println("Start index $start_index exceeds empty results drugs ($(length(empty_results_drugs))). Nothing to process.")
    exit(0)
end

drugs_to_process = empty_results_drugs[start_index:end_index]
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
                    println("$drug_name: Rate limited, waiting 5 seconds...")
                    sleep(5)
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
                sleep(1.0)
            catch e
                println("$drug_name: Error fetching batch starting at $start_pos: $e")
                continue
            end
        end
        
        println("$drug_name: Retrieved $(length(all_pmids)) PMIDs, fetching publication details...")
        
        # Step 3: Fetch publication details for ALL PMIDs with aggressive rate limiting
        publications = []
        fetch_batch_size = 50  # Smaller batch size for more reliable processing
        
        for i in 1:fetch_batch_size:length(all_pmids)
            batch_end = min(i + fetch_batch_size - 1, length(all_pmids))
            batch_pmids = all_pmids[i:batch_end]
            pmid_string = join(batch_pmids, ",")
            
            fetch_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=$pmid_string&retmode=xml"
            
            try
                fetch_response = HTTP.get(fetch_url)
                if fetch_response.status == 429
                    println("$drug_name: Rate limited during fetch, waiting 5 seconds...")
                    sleep(5)
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
                
                # Very aggressive rate limiting to avoid API issues
                sleep(2.0)
                
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

# Process each drug in the batch
println("🚀 Starting empty results reprocessing...")

processed_count = 0
for drug_name in drugs_to_process
    try
        # Search PubMed for this drug
        result = search_pubmed_for_drug_comprehensive(drug_name)
        
        if result !== nothing
            # Create output directory if it doesn't exist
            mkpath("phase1_drug_pubmed_refs")
            
            # Write result to JSON file (overwrite existing)
            safe_filename = replace(drug_name, " " => "_")
            output_file = "phase1_drug_pubmed_refs/$(safe_filename).json"
            
            open(output_file, "w") do f
                JSON3.pretty(f, result)
            end
            
            processed_count += 1
            total_found = result["result"]["total_publications_found"]
            pubs_analyzed = length(result["result"]["publications_analyzed"])
            println("✅ $drug_name: Saved $pubs_analyzed/$total_found publications to $output_file")
        else
            println("❌ $drug_name: Failed to process")
        end
        
        # Aggressive rate limiting between drugs
        sleep(3.0)
        
    catch e
        println("❌ Error processing $drug_name: $e")
        continue
    end
end

println("\n🎉 Empty results worker completed!")
println("📊 Processed $processed_count drugs successfully")
println("📂 Results saved in phase1_drug_pubmed_refs/")