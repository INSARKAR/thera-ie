#!/usr/bin/env julia

"""
PubMed Drug Search

This program searches PubMed using the Entrez API for each drug using the 
pre-formatted queries from the pubmed_queries.json file. It retrieves publication 
counts and basic information about the search results.

Usage:
    julia pubmed_drug_search.jl

Input:
    - pubmed_queries.json (Drug queries file with drug names, indications, and pre-formatted queries)

Output:
    - pubmed_search_results.json (Search results in JSON format)
    - pubmed_search_results.txt (Human-readable summary)

The program uses the NCBI Entrez E-utilities API:
- esearch: to search PubMed and get publication counts
- efetch: to retrieve publication details (optional, for detailed analysis)

Note: This version limits searches to the first 10 drugs for testing purposes.
Uses the pre-formatted 'query' field from the JSON data for optimal search results.
"""

using HTTP
using JSON3
using Dates

"""
    load_drug_queries(filename::String) -> Vector{Dict}

Load drug queries from a JSON file.

# Arguments
- `filename::String`: Path to the JSON file containing drug queries

# Returns
- `Vector{Dict}`: Array of drug objects with drug_name, indication, etc.
"""
function load_drug_queries(filename::String)
    if !isfile(filename)
        error("Drug queries file not found: $filename")
    end
    
    try
        data = JSON3.read(read(filename, String))
        return data.drugs
    catch e
        error("Error reading drug queries file: $e")
    end
end

"""
    search_pubmed(query::String; retmax::Int=20) -> Dict

Search PubMed using the Entrez esearch API.

# Arguments
- `query::String`: Search query string
- `retmax::Int=20`: Maximum number of results to return (default: 20)

# Returns
- `Dict`: Search results containing count, IDs, and metadata
"""
function search_pubmed(query::String; retmax::Int=20)
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    
    # Prepare search parameters
    params = Dict(
        "db" => "pubmed",
        "term" => query,
        "retmode" => "json",
        "retmax" => string(retmax),
        "sort" => "relevance",
        "tool" => "julia_pubmed_search",
        "email" => "researcher@example.com"  # Replace with actual email
    )
    
    try
        # Make HTTP request
        response = HTTP.get(base_url, query=params)
        
        # Check if request was successful
        if response.status == 200
            # Parse JSON response
            result = JSON3.read(response.body)
            
            # Extract relevant information
            esearch_result = result.esearchresult
            
            search_data = Dict(
                "query" => query,
                "count" => parse(Int, esearch_result.count),
                "retmax" => parse(Int, esearch_result.retmax),
                "pmids" => esearch_result.idlist,
                "translation_set" => get(esearch_result, :translationset, []),
                "query_translation" => get(esearch_result, :querytranslation, ""),
                "search_time" => now(),
                "status" => "success"
            )
            
            return search_data
            
        else
            return Dict(
                "query" => query,
                "status" => "error",
                "error" => "HTTP $(response.status)",
                "search_time" => now()
            )
        end
        
    catch e
        return Dict(
            "query" => query,
            "status" => "error",
            "error" => string(e),
            "search_time" => now()
        )
    end
end

"""
    extract_search_term_from_url(url::String) -> String

Extract the search term from a PubMed URL.

# Arguments
- `url::String`: PubMed URL containing the search term

# Returns
- `String`: Decoded search term suitable for API use
"""
function extract_search_term_from_url(url::String)
    try
        # Extract the term parameter from the URL
        if occursin("?term=", url)
            # Split on ?term= and take the part after it
            term_part = split(url, "?term=")[2]
            
            # URL decode the search term
            decoded_term = HTTP.URIs.unescapeuri(term_part)
            
            return decoded_term
        else
            error("URL does not contain a term parameter")
        end
    catch e
        # Fallback: return empty string if URL parsing fails
        println("Warning: Could not extract search term from URL: $url")
        return ""
    end
end

"""
    save_results_json(results::Vector, filename::String)

Save search results to a JSON file.
"""
function save_results_json(results::Vector, filename::String)
    open(filename, "w") do file
        write(file, JSON3.write(results))
    end
    println("Saved JSON results to: $filename")
end

"""
    save_results_summary(results::Vector, filename::String)

Save a human-readable summary of search results.
"""
function save_results_summary(results::Vector, filename::String)
    open(filename, "w") do file
        write(file, "PubMed Drug Search Results Summary\n")
        write(file, "Generated on: $(now())\n")
        write(file, "Total drugs searched: $(length(results))\n")
        write(file, "=" ^ 50 * "\n\n")
        
        successful_searches = filter(r -> r["status"] == "success", results)
        failed_searches = filter(r -> r["status"] == "error", results)
        
        write(file, "Successful searches: $(length(successful_searches))\n")
        write(file, "Failed searches: $(length(failed_searches))\n\n")
        
        if !isempty(successful_searches)
            # Sort by publication count (descending)
            sorted_results = sort(successful_searches, by = r -> r["count"], rev=true)
            
            write(file, "Top Results by Publication Count:\n")
            write(file, "-" ^ 40 * "\n")
            
            for (i, result) in enumerate(sorted_results[1:min(10, length(sorted_results))])
                drug_name = split(result["query"], '"')[2]  # Extract drug name from query
                write(file, "$i. $drug_name\n")
                write(file, "   Publications: $(result["count"])\n")
                write(file, "   Query: $(result["query"])\n")
                if !isempty(result["query_translation"])
                    write(file, "   Translation: $(result["query_translation"])\n")
                end
                write(file, "\n")
            end
        end
        
        if !isempty(failed_searches)
            write(file, "\nFailed Searches:\n")
            write(file, "-" ^ 20 * "\n")
            for result in failed_searches
                drug_name = result["query"]
                write(file, "- $drug_name: $(result["error"])\n")
            end
        end
        
        # Summary statistics
        if !isempty(successful_searches)
            total_pubs = sum(r["count"] for r in successful_searches)
            avg_pubs = total_pubs / length(successful_searches)
            max_pubs = maximum(r["count"] for r in successful_searches)
            min_pubs = minimum(r["count"] for r in successful_searches)
            
            write(file, "\nStatistics:\n")
            write(file, "-" ^ 15 * "\n")
            write(file, "Total publications found: $total_pubs\n")
            write(file, "Average publications per drug: $(round(avg_pubs, digits=1))\n")
            write(file, "Maximum publications for a drug: $max_pubs\n")
            write(file, "Minimum publications for a drug: $min_pubs\n")
        end
    end
    println("Saved summary to: $filename")
end

"""
    load_mesh_disease_headings(filename::String) -> Set{String}

Load MeSH T047 disease headings from a Julia file.

# Arguments
- `filename::String`: Path to the Julia file containing MESH_T047_HEADINGS

# Returns
- `Set{String}`: Set of MeSH disease headings
"""
function load_mesh_disease_headings(filename::String)
    if !isfile(filename)
        error("MeSH disease headings file not found: $filename")
    end
    
    try
        # Include the file to load the MESH_T047_HEADINGS constant
        include(filename)
        return MESH_T047_HEADINGS
    catch e
        error("Error loading MeSH disease headings: $e")
    end
end

"""
    fetch_publication_details(pmids::Vector{String}, retmax::Int=10) -> Dict

Fetch detailed publication information including MeSH descriptors using efetch API.

# Arguments
- `pmids::Vector{String}`: List of PubMed IDs to fetch
- `retmax::Int=10`: Maximum number of publications to fetch (default: 10)

# Returns
- `Dict`: Publication details including MeSH descriptors
"""
function fetch_publication_details(pmids::Vector{String}, retmax::Int=10)
    if isempty(pmids)
        return Dict("status" => "error", "error" => "No PMIDs provided")
    end
    
    # Limit the number of PMIDs to fetch
    limited_pmids = pmids[1:min(retmax, length(pmids))]
    pmid_string = join(limited_pmids, ",")
    
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    
    params = Dict(
        "db" => "pubmed",
        "id" => pmid_string,
        "retmode" => "xml",
        "tool" => "julia_pubmed_search",
        "email" => "researcher@example.com"  # Replace with actual email
    )
    
    try
        response = HTTP.get(base_url, query=params)
        
        if response.status == 200
            return Dict(
                "status" => "success",
                "xml_data" => String(response.body),
                "pmids_fetched" => limited_pmids,
                "fetch_time" => now()
            )
        else
            return Dict(
                "status" => "error",
                "error" => "HTTP $(response.status)",
                "fetch_time" => now()
            )
        end
        
    catch e
        return Dict(
            "status" => "error",
            "error" => string(e),
            "fetch_time" => now()
        )
    end
end

"""
    safe_fetch_publication_details(pmids::Vector{String}) -> Dict

Wrapper function to safely fetch publication details.
"""
function safe_fetch_publication_details(pmids::Vector{String})
    try
        return fetch_publication_details(pmids)
    catch e
        return Dict("status" => "error", "error" => "Function call failed: $e")
    end
end

"""
    extract_mesh_descriptors(xml_data::String) -> Vector{Dict}

Extract MeSH descriptors from PubMed XML data.

# Arguments
- `xml_data::String`: XML response from efetch API

# Returns
- `Vector{Dict}`: List of publications with their MeSH descriptors
"""
function extract_mesh_descriptors(xml_data::String)
    publications = []
    
    try
        # Simple regex-based extraction (could be enhanced with proper XML parsing)
        # Extract individual PubmedArticle elements
        article_pattern = r"<PubmedArticle>(.*?)</PubmedArticle>"s
        article_matches = eachmatch(article_pattern, xml_data)
        
        for article_match in article_matches
            article_xml = article_match.captures[1]
            
            # Extract PMID
            pmid_match = match(r"<PMID[^>]*>(\d+)</PMID>", article_xml)
            pmid = pmid_match !== nothing ? pmid_match.captures[1] : "unknown"
            
            # Extract article title
            title_match = match(r"<ArticleTitle>(.*?)</ArticleTitle>"s, article_xml)
            title = title_match !== nothing ? title_match.captures[1] : "No title"
            
            # Extract MeSH descriptors
            mesh_descriptors = []
            mesh_pattern = r"<MeshHeading>(.*?)</MeshHeading>"s
            mesh_matches = eachmatch(mesh_pattern, article_xml)
            
            for mesh_match in mesh_matches
                mesh_xml = mesh_match.captures[1]
                
                # Extract descriptor name
                descriptor_match = match(r"<DescriptorName[^>]*>(.*?)</DescriptorName>", mesh_xml)
                if descriptor_match !== nothing
                    descriptor_name = descriptor_match.captures[1]
                    
                    # Extract qualifiers if any
                    qualifiers = []
                    qualifier_pattern = r"<QualifierName[^>]*>(.*?)</QualifierName>"
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
                "mesh_descriptors" => mesh_descriptors
            ))
        end
        
    catch e
        println("Warning: Error parsing XML data: $e")
    end
    
    return publications
end

"""
    analyze_disease_associations(publications::Vector{Dict}, disease_headings::Set{String}) -> Dict

Analyze publications to find disease associations based on MeSH descriptors.

# Arguments
- `publications::Vector{Dict}`: List of publications with MeSH descriptors
- `disease_headings::Set{String}`: Set of MeSH T047 disease headings

# Returns
- `Dict`: Analysis results with disease associations
"""
function analyze_disease_associations(publications::Vector{Dict}, disease_headings::Set{String})
    disease_associations = Dict{String, Vector{Dict}}()
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
    main()

Main function to search PubMed for drugs using pre-formatted queries from pubmed_queries.json
and analyze MeSH descriptors for disease associations.
"""
function main()
    println("PubMed Drug Search with Disease Association Analysis")
    println("=" ^ 50)
    println("Searching PubMed using pre-formatted queries from pubmed_queries.json...")
    println("Analyzing MeSH descriptors for disease associations...")
    println("Limiting to first 5 drugs for testing.\n")
    
    # Load MeSH T047 disease headings
    mesh_file = "mesh_t047_headings.jl"
    println("Loading MeSH T047 disease headings from: $mesh_file")
    
    try
        disease_headings = load_mesh_disease_headings(mesh_file)
        println("Loaded $(length(disease_headings)) disease headings\n")
        
        # Load drug data from JSON file
        queries_file = "pubmed_queries.json"
        println("Loading drug data from: $queries_file")
        
        drug_data = load_drug_queries(queries_file)
        println("Loaded $(length(drug_data)) drugs from file\n")
        
        # Limit to first 5 drugs for testing (reduced due to additional analysis)
        test_drugs = drug_data[1:min(5, length(drug_data))]
        
        println("Drugs to search:")
        for (i, drug) in enumerate(test_drugs)
            println("  $i. $(drug.drug_name)")
        end
        println()
        
        # Store all results
        all_results = []
        
        # Search for each drug
        for (i, drug_entry) in enumerate(test_drugs)
            drug_name = drug_entry.drug_name
            indication = drug_entry.indication
            query_field = drug_entry.query
            url_field = drug_entry.url
            
            println("[$i/$(length(test_drugs))] Searching for: $drug_name")
            
            # Use the pre-formatted query from the JSON data
            search_query = query_field
            println("  Query: $search_query")
            
            # Perform the search
            result = search_pubmed(search_query, retmax=20)  # Get more results for analysis
            
            # Add drug information for reference
            result["drug_name"] = drug_name
            result["indication"] = indication
            result["original_url"] = url_field
            result["original_query"] = query_field
            
            # Display search result
            if result["status"] == "success"
                println("  ✓ Found $(result["count"]) publications")
                if result["count"] > 0
                    println("    Sample PMIDs: $(join(result["pmids"][1:min(3, length(result["pmids"]))], ", "))")
                    
                    # Fetch detailed publication data for disease analysis
                    println("  📋 Fetching publication details for disease analysis...")
                    println("    PMIDs: $(join(result["pmids"][1:min(3, length(result["pmids"]))], ", "))...")
                    fetch_result = safe_fetch_publication_details(result["pmids"])
                    
                    if fetch_result["status"] == "success"
                        # Extract MeSH descriptors
                        publications = extract_mesh_descriptors(fetch_result["xml_data"])
                        println("    ✓ Analyzed $(length(publications)) publications")
                        
                        # Analyze disease associations
                        disease_analysis = analyze_disease_associations(publications, disease_headings)
                        
                        # Add disease analysis to result
                        result["disease_analysis"] = disease_analysis
                        result["publications_analyzed"] = publications
                        
                        # Display disease associations
                        disease_count = disease_analysis["summary"]["unique_diseases_found"]
                        if disease_count > 0
                            println("    🔬 Found associations with $disease_count disease(s):")
                            for disease in disease_analysis["summary"]["matched_diseases"][1:min(3, length(disease_analysis["summary"]["matched_diseases"]))]
                                pub_count = length(disease_analysis["disease_associations"][disease])
                                println("      - $disease ($pub_count publications)")
                            end
                            if disease_count > 3
                                println("      ... and $(disease_count - 3) more diseases")
                            end
                        else
                            println("    ℹ️  No disease associations found in analyzed publications")
                        end
                    else
                        println("    ✗ Failed to fetch publication details: $(fetch_result["error"])")
                        result["disease_analysis"] = Dict("status" => "fetch_failed", "error" => fetch_result["error"])
                    end
                end
            else
                println("  ✗ Search failed: $(result["error"])")
            end
            
            push!(all_results, result)
            
            # Small delay to be respectful to NCBI servers
            sleep(1.0)  # Increased delay due to additional API calls
            println()
        end
        
        # Save results
        output_json = "pubmed_disease_analysis_results.json"
        output_summary = "pubmed_disease_analysis_results.txt"
        
        save_results_json(all_results, output_json)
        save_disease_analysis_summary(all_results, output_summary)
        
        # Display final summary
        successful = sum(1 for r in all_results if r["status"] == "success")
        total_pubs = sum(r["count"] for r in all_results if r["status"] == "success")
        
        # Count total disease associations
        total_diseases = 0
        for result in all_results
            if haskey(result, "disease_analysis") && haskey(result["disease_analysis"], "summary")
                total_diseases += result["disease_analysis"]["summary"]["unique_diseases_found"]
            end
        end
        
        println("\nSEARCH AND ANALYSIS COMPLETED!")
        println("=" ^ 35)
        println("Drugs searched: $(length(test_drugs))")
        println("Successful searches: $successful")
        println("Total publications found: $total_pubs")
        println("Total disease associations identified: $total_diseases")
        println("\nOutput files:")
        println("  ✓ $output_json - Detailed JSON results with disease analysis")
        println("  ✓ $output_summary - Human-readable summary with disease associations")
        
        if successful < length(test_drugs)
            println("\n⚠️  Some searches failed. Check the summary file for details.")
        end
        
    catch e
        println("Error: $e")
        exit(1)
    end
end

"""
    save_disease_analysis_summary(results::Vector, filename::String)

Save a human-readable summary of search results with disease association analysis.
"""
function save_disease_analysis_summary(results::Vector, filename::String)
    open(filename, "w") do file
        write(file, "PubMed Drug Search Results with Disease Association Analysis\n")
        write(file, "Generated on: $(now())\n")
        write(file, "Total drugs searched: $(length(results))\n")
        write(file, "=" ^ 60 * "\n\n")
        
        successful_searches = filter(r -> r["status"] == "success", results)
        failed_searches = filter(r -> r["status"] == "error", results)
        
        write(file, "Successful searches: $(length(successful_searches))\n")
        write(file, "Failed searches: $(length(failed_searches))\n\n")
        
        if !isempty(successful_searches)
            write(file, "DRUG-DISEASE ASSOCIATION ANALYSIS\n")
            write(file, "=" ^ 40 * "\n\n")
            
            for (i, result) in enumerate(successful_searches)
                drug_name = result["drug_name"]
                pub_count = result["count"]
                indication = result["indication"]
                
                write(file, "$i. $drug_name\n")
                write(file, "   FDA Indication: $indication\n")
                write(file, "   Publications found: $pub_count\n")
                
                if haskey(result, "disease_analysis")
                    disease_analysis = result["disease_analysis"]
                    
                    if haskey(disease_analysis, "summary")
                        summary = disease_analysis["summary"]
                        pubs_analyzed = summary["total_publications_analyzed"]
                        diseases_found = summary["unique_diseases_found"]
                        
                        write(file, "   Publications analyzed: $pubs_analyzed\n")
                        write(file, "   Disease associations found: $diseases_found\n")
                        
                        if diseases_found > 0
                            write(file, "   \n   Associated diseases (from MeSH T047 list):\n")
                            
                            disease_assocs = disease_analysis["disease_associations"]
                            # Sort diseases by number of publications
                            sorted_diseases = sort(collect(keys(disease_assocs)), 
                                                 by = d -> length(disease_assocs[d]), rev=true)
                            
                            for disease in sorted_diseases
                                pubs = disease_assocs[disease]
                                write(file, "   - $disease ($(length(pubs)) publications)\n")
                                
                                # Show sample publications
                                for (j, pub) in enumerate(pubs[1:min(2, length(pubs))])
                                    pmid = pub["pmid"]
                                    title = length(pub["title"]) > 80 ? pub["title"][1:80] * "..." : pub["title"]
                                    write(file, "     [$pmid] $title\n")
                                end
                                
                                if length(pubs) > 2
                                    write(file, "     ... and $(length(pubs) - 2) more publications\n")
                                end
                            end
                        else
                            write(file, "   No disease associations found in analyzed publications.\n")
                        end
                    else
                        write(file, "   Disease analysis failed: $(get(disease_analysis, "error", "unknown error"))\n")
                    end
                else
                    write(file, "   No disease analysis performed.\n")
                end
                
                write(file, "\n")
            end
        end
        
        if !isempty(failed_searches)
            write(file, "\nFAILED SEARCHES:\n")
            write(file, "-" ^ 20 * "\n")
            for result in failed_searches
                drug_name = result["drug_name"]
                write(file, "- $drug_name: $(result["error"])\n")
            end
        end
        
        # Overall statistics
        if !isempty(successful_searches)
            total_pubs = sum(r["count"] for r in successful_searches)
            total_diseases = 0
            total_analyzed_pubs = 0
            
            for result in successful_searches
                if haskey(result, "disease_analysis") && haskey(result["disease_analysis"], "summary")
                    total_diseases += result["disease_analysis"]["summary"]["unique_diseases_found"]
                    total_analyzed_pubs += result["disease_analysis"]["summary"]["total_publications_analyzed"]
                end
            end
            
            avg_pubs = total_pubs / length(successful_searches)
            
            write(file, "\nOVERALL STATISTICS:\n")
            write(file, "-" ^ 20 * "\n")
            write(file, "Total publications found: $total_pubs\n")
            write(file, "Total publications analyzed: $total_analyzed_pubs\n")
            write(file, "Average publications per drug: $(round(avg_pubs, digits=1))\n")
            write(file, "Total unique disease associations: $total_diseases\n")
            write(file, "Average disease associations per drug: $(round(total_diseases / length(successful_searches), digits=1))\n")
        end
    end
    println("Saved disease analysis summary to: $filename")
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
