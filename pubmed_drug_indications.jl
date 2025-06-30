#!/usr/bin/env julia

"""
PubMed Drug Indications Analysis

This program combines PubMed search and disease association analysis into a single workflow.
It searches PubMed for approved drugs, fetches publication details, and analyzes MeSH descriptors
to identify disease associations from the MeSH T047 (Disease or Syndrome) semantic type.

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

# Configuration
const MAX_DRUGS = 10  # Limit searches for demonstration
const MAX_RESULTS_PER_DRUG = 50  # Maximum PMIDs to retrieve per drug
const MAX_PMIDS_TO_ANALYZE = 10  # Maximum PMIDs to analyze per drug

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
    search_pubmed(drug_name::String; retmax::Int=50) -> Dict

Search PubMed for publications mentioning a drug name.
"""
function search_pubmed(drug_name::String; retmax::Int=50)
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
        # Make the API request
        response = HTTP.get(url)
        
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
    fetch_publication_details(pmids) -> Dict

Fetch detailed publication information including MeSH descriptors.
"""
function fetch_publication_details(pmids)
    if isempty(pmids)
        return Dict("status" => "error", "error" => "No PMIDs provided")
    end
    
    # Convert to regular array and limit PMIDs for analysis
    pmid_array = collect(pmids)
    limited_pmids = pmid_array[1:min(MAX_PMIDS_TO_ANALYZE, length(pmid_array))]
    pmid_string = join(limited_pmids, ",")
    
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    
    params = Dict(
        "db" => "pubmed",
        "id" => pmid_string,
        "retmode" => "xml",
        "tool" => "julia_pubmed_drug_indications",
        "email" => "researcher@example.com"
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
    extract_mesh_descriptors(xml_data::String) -> Vector{Dict}

Extract MeSH descriptors from PubMed XML data.
"""
function extract_mesh_descriptors(xml_data::String)
    publications = []
    
    try
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
    analyze_disease_associations(publications::Vector, disease_headings::Set{String}) -> Dict

Analyze publications to find disease associations based on MeSH descriptors.
"""
function analyze_disease_associations(publications::Vector, disease_headings::Set{String})
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
    process_drug(drug_name::String, indication::String, disease_headings::Set{String}) -> Dict

Complete processing pipeline for a single drug: search, fetch, and analyze.
"""
function process_drug(drug_name::String, indication::String, disease_headings::Set{String})
    println("  Searching PubMed...")
    
    # Step 1: Search PubMed
    search_result = search_pubmed(drug_name; retmax=MAX_RESULTS_PER_DRUG)
    
    if search_result["status"] != "success"
        return Dict(
            "drug_name" => drug_name,
            "indication" => indication,
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
            "indication" => indication,
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
            "indication" => indication,
            "search_status" => "success",
            "count" => count,
            "pmids" => pmids,
            "fetch_status" => fetch_result["status"],
            "fetch_error" => get(fetch_result, "error", "Unknown error"),
            "disease_analysis" => Dict("status" => "fetch_failed")
        )
    end
    
    # Step 3: Extract MeSH descriptors
    println("  Extracting MeSH descriptors...")
    publications = extract_mesh_descriptors(fetch_result["xml_data"])
    println("    ✓ Analyzed $(length(publications)) publications")
    
    # Step 4: Analyze disease associations
    println("  Analyzing disease associations...")
    disease_analysis = analyze_disease_associations(publications, disease_headings)
    
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
        "indication" => indication,
        "search_status" => "success",
        "count" => count,
        "pmids" => pmids,
        "fetch_status" => "success",
        "pmids_analyzed" => fetch_result["pmids_fetched"],
        "publications_analyzed" => publications,
        "disease_analysis" => disease_analysis
    )
end

"""
    save_results(results::Vector, filename_json::String, filename_txt::String)

Save comprehensive drug-disease association results to both JSON and text files.
"""
function save_results(results::Vector, filename_json::String, filename_txt::String)
    # Prepare output data with metadata
    output_data = Dict(
        "metadata" => Dict(
            "generated_on" => string(now()),
            "total_drugs_analyzed" => length(results),
            "max_drugs_limit" => MAX_DRUGS,
            "max_results_per_drug" => MAX_RESULTS_PER_DRUG,
            "max_pmids_analyzed_per_drug" => MAX_PMIDS_TO_ANALYZE,
            "description" => "Comprehensive PubMed drug-disease association analysis"
        ),
        "results" => results
    )
    
    # Save JSON
    open(filename_json, "w") do file
        write(file, JSON3.write(output_data))
    end
    println("Saved comprehensive results to: $filename_json")
    
    # Save human-readable summary
    open(filename_txt, "w") do file
        write(file, "Drug-Disease Association Analysis\n")
        write(file, "Generated on: $(now())\n")
        write(file, "Total drugs analyzed: $(length(results))\n")
        write(file, "=" ^ 50 * "\n\n")
        
        successful_analyses = filter(r -> haskey(r, "disease_analysis") && 
                                        haskey(r["disease_analysis"], "summary"), results)
        
        if !isempty(successful_analyses)
            write(file, "DRUG-DISEASE ASSOCIATIONS\n")
            write(file, "=" ^ 25 * "\n\n")
            
            for (i, result) in enumerate(successful_analyses)
                drug_name = result["drug_name"]
                pub_count = result["count"]
                indication = result["indication"]
                disease_analysis = result["disease_analysis"]
                summary = disease_analysis["summary"]
                
                write(file, "$i. $drug_name\n")
                write(file, "   FDA Indication: $(indication[1:min(100, length(indication))])...\n")
                write(file, "   Publications found: $pub_count\n")
                write(file, "   Publications analyzed: $(summary["total_publications_analyzed"])\n")
                write(file, "   Disease associations found: $(summary["unique_diseases_found"])\n")
                
                if summary["unique_diseases_found"] > 0
                    write(file, "\n   Associated diseases (MeSH T047):\n")
                    
                    disease_assocs = disease_analysis["disease_associations"]
                    # Sort diseases by number of publications
                    sorted_diseases = sort(collect(keys(disease_assocs)), 
                                         by = d -> length(disease_assocs[d]), rev=true)
                    
                    for disease in sorted_diseases
                        pubs = disease_assocs[disease]
                        write(file, "   - $disease ($(length(pubs)) publications)\n")
                        
                        # Show one sample publication
                        if !isempty(pubs)
                            pub = pubs[1]
                            pmid = pub["pmid"]
                            title = length(pub["title"]) > 60 ? pub["title"][1:60] * "..." : pub["title"]
                            write(file, "     Example: [$pmid] $title\n")
                        end
                    end
                else
                    write(file, "   No disease associations found.\n")
                end
                
                write(file, "\n")
            end
            
            # Overall statistics
            total_diseases = sum(r["disease_analysis"]["summary"]["unique_diseases_found"] 
                               for r in successful_analyses)
            total_analyzed_pubs = sum(r["disease_analysis"]["summary"]["total_publications_analyzed"] 
                                    for r in successful_analyses)
            
            write(file, "\nOVERALL STATISTICS:\n")
            write(file, "-" ^ 20 * "\n")
            write(file, "Total publications analyzed: $total_analyzed_pubs\n")
            write(file, "Total unique disease associations: $total_diseases\n")
            write(file, "Average disease associations per drug: $(round(total_diseases / length(successful_analyses), digits=1))\n")
        end
        
        # Error summary
        failed_searches = filter(r -> get(r, "search_status", "") != "success", results)
        failed_fetches = filter(r -> get(r, "search_status", "") == "success" && 
                               get(r, "fetch_status", "") != "success", results)
        no_pmids = filter(r -> get(r, "search_status", "") == "success" && 
                         isempty(get(r, "pmids", [])), results)
        
        if !isempty(failed_searches) || !isempty(failed_fetches) || !isempty(no_pmids)
            write(file, "\nERRORS AND WARNINGS:\n")
            write(file, "-" ^ 20 * "\n")
            write(file, "Failed searches: $(length(failed_searches))\n")
            write(file, "Failed fetches: $(length(failed_fetches))\n")
            write(file, "Drugs with no PMIDs: $(length(no_pmids))\n")
        end
    end
    println("Saved summary to: $filename_txt")
end

"""
    main()

Main function to run the complete PubMed drug indications analysis pipeline.
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
        
        println("✓ Limiting analysis to first $MAX_DRUGS drugs for demonstration")
        println()
        
        # Convert to array and limit
        drug_list = collect(drugs_dict)[1:min(MAX_DRUGS, length(drugs_dict))]
        
        # Process each drug
        results = Vector{Dict}()
        
        for (i, (drug_name, indication)) in enumerate(drug_list)
            println("[$i/$MAX_DRUGS] Processing: $drug_name")
            
            result = process_drug(drug_name, indication, disease_headings)
            push!(results, result)
            
            # Small delay to be respectful to NCBI servers
            sleep(0.5)
            println()
        end
        
        # Save comprehensive results
        output_json = "drug_disease_associations.json"
        output_txt = "drug_disease_associations.txt"
        
        save_results(results, output_json, output_txt)
        
        # Final summary
        successful_searches = sum(1 for r in results if get(r, "search_status", "") == "success")
        successful_analyses = sum(1 for r in results if haskey(r, "disease_analysis") && 
                                haskey(r["disease_analysis"], "summary"))
        total_diseases = sum(r["disease_analysis"]["summary"]["unique_diseases_found"] 
                           for r in results if haskey(r, "disease_analysis") && 
                           haskey(r["disease_analysis"], "summary"))
        total_pubs_analyzed = sum(r["disease_analysis"]["summary"]["total_publications_analyzed"] 
                                for r in results if haskey(r, "disease_analysis") && 
                                haskey(r["disease_analysis"], "summary"))
        
        println()
        println("ANALYSIS COMPLETED!")
        println("=" ^ 20)
        println("Drugs processed: $(length(results))")
        println("Successful PubMed searches: $successful_searches")
        println("Successful disease analyses: $successful_analyses")
        println("Total publications analyzed: $total_pubs_analyzed")
        println("Total disease associations found: $total_diseases")
        println()
        println("Output files:")
        println("  ✓ $output_json - Comprehensive JSON results with metadata")
        println("  ✓ $output_txt - Human-readable summary")
        println()
        println("This unified pipeline has successfully:")
        println("  • Searched PubMed for approved drug publications")
        println("  • Fetched detailed publication data including MeSH descriptors")
        println("  • Analyzed disease associations using MeSH T047 terms")
        println("  • Generated comprehensive drug-disease association data")
        
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
