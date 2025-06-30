#!/usr/bin/env julia

"""
PubMed Disease Association Analyzer

This program takes the results from pubmed_drug_search.jl and analyzes the 
MeSH descriptors in the retrieved publications to identify disease associations
from the MeSH T047 (Disease or Syndrome) semantic type.

Usage:
    julia pubmed_disease_analyzer.jl

Input:
    - pubmed_search_results.json (Results from previous PubMed search)
    - mesh_t047_headings.jl (MeSH T047 disease headings)

Output:
    - drug_disease_associations.json (Disease associations in JSON format)
    - drug_disease_associations.txt (Human-readable summary)
"""

using HTTP
using JSON3
using Dates

"""
    load_search_results(filename::String) -> Vector{Dict}

Load previous PubMed search results from JSON file.
"""
function load_search_results(filename::String)
    if !isfile(filename)
        error("Search results file not found: $filename")
    end
    
    try
        data = JSON3.read(read(filename, String))
        # Handle both old and new format
        if haskey(data, "results")
            return data.results  # New format with metadata
        else
            return data  # Old format
        end
    catch e
        error("Error reading search results file: $e")
    end
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
    fetch_publication_details(pmids) -> Dict

Fetch detailed publication information including MeSH descriptors.
"""
function fetch_publication_details(pmids)
    if isempty(pmids)
        return Dict("status" => "error", "error" => "No PMIDs provided")
    end
    
    # Convert to regular array and limit to first 10 PMIDs for analysis
    pmid_array = collect(pmids)
    limited_pmids = pmid_array[1:min(10, length(pmid_array))]
    pmid_string = join(limited_pmids, ",")
    
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    
    params = Dict(
        "db" => "pubmed",
        "id" => pmid_string,
        "retmode" => "xml",
        "tool" => "julia_pubmed_disease_analyzer",
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
    save_disease_analysis(results::Vector, filename_json::String, filename_txt::String)

Save disease association analysis to both JSON and text files.
"""
function save_disease_analysis(results::Vector, filename_json::String, filename_txt::String)
    # Save JSON
    open(filename_json, "w") do file
        write(file, JSON3.write(results))
    end
    println("Saved JSON results to: $filename_json")
    
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
    end
    println("Saved summary to: $filename_txt")
end

"""
    main()

Main function to analyze disease associations from existing PubMed search results.
"""
function main()
    println("PubMed Disease Association Analyzer")
    println("=" ^ 35)
    println("Analyzing MeSH descriptors for disease associations...")
    println("Loading data from previous search results.\n")
    
    # Load MeSH T047 disease headings
    mesh_file = "mesh_t047_headings.jl"
    println("Loading MeSH T047 disease headings from: $mesh_file")
    
    try
        disease_headings = load_mesh_disease_headings(mesh_file)
        println("Loaded $(length(disease_headings)) disease headings\n")
        
        # Load previous search results
        results_file = "pubmed_search_results.json"
        println("Loading previous search results from: $results_file")
        
        search_results = load_search_results(results_file)
        println("Loaded results for $(length(search_results)) drugs\n")
        
        # Analyze disease associations for each drug
        analyzed_results = []
        
        for (i, result) in enumerate(search_results)
            drug_name = result["drug_name"]
            pmids = result["pmids"]
            
            println("[$i/$(length(search_results))] Analyzing: $drug_name")
            println("  PMIDs to analyze: $(join(pmids[1:min(3, length(pmids))], ", "))...")
            
            if length(pmids) > 0
                # Fetch detailed publication data
                fetch_result = fetch_publication_details(pmids)
                
                if fetch_result["status"] == "success"
                    # Extract MeSH descriptors
                    publications = extract_mesh_descriptors(fetch_result["xml_data"])
                    println("  ✓ Analyzed $(length(publications)) publications")
                    
                    # Analyze disease associations
                    disease_analysis = analyze_disease_associations(publications, disease_headings)
                    
                    # Add to result - create new dict to avoid type issues
                    result_copy = Dict{String, Any}()
                    for (k, v) in pairs(result)
                        result_copy[string(k)] = v
                    end
                    result_copy["disease_analysis"] = disease_analysis
                    result_copy["publications_analyzed"] = publications
                    
                    # Display findings
                    disease_count = disease_analysis["summary"]["unique_diseases_found"]
                    if disease_count > 0
                        println("  🔬 Found associations with $disease_count disease(s):")
                        for disease in disease_analysis["summary"]["matched_diseases"][1:min(3, length(disease_analysis["summary"]["matched_diseases"]))]
                            pub_count = length(disease_analysis["disease_associations"][disease])
                            println("    - $disease ($pub_count publications)")
                        end
                        if disease_count > 3
                            println("    ... and $(disease_count - 3) more diseases")
                        end
                    else
                        println("  ℹ️  No disease associations found")
                    end
                    
                    push!(analyzed_results, result_copy)
                else
                    println("  ✗ Failed to fetch details: $(fetch_result["error"])")
                    result_copy = Dict(pairs(result))
                    result_copy["disease_analysis"] = Dict("status" => "fetch_failed", "error" => fetch_result["error"])
                    push!(analyzed_results, result_copy)
                end
            else
                println("  ⚠️  No PMIDs to analyze")
                result_copy = Dict(pairs(result))
                result_copy["disease_analysis"] = Dict("status" => "no_pmids")
                push!(analyzed_results, result_copy)
            end
            
            # Small delay to be respectful to NCBI servers
            sleep(0.5)
            println()
        end
        
        # Save results
        output_json = "drug_disease_associations.json"
        output_txt = "drug_disease_associations.txt"
        
        save_disease_analysis(analyzed_results, output_json, output_txt)
        
        # Final summary
        successful = sum(1 for r in analyzed_results if haskey(r, "disease_analysis") && 
                        haskey(r["disease_analysis"], "summary"))
        total_diseases = sum(r["disease_analysis"]["summary"]["unique_diseases_found"] 
                           for r in analyzed_results if haskey(r, "disease_analysis") && 
                           haskey(r["disease_analysis"], "summary"))
        
        println("\nANALYSIS COMPLETED!")
        println("=" ^ 20)
        println("Drugs analyzed: $(length(search_results))")
        println("Successful analyses: $successful")
        println("Total disease associations found: $total_diseases")
        println("\nOutput files:")
        println("  ✓ $output_json - Detailed JSON results")
        println("  ✓ $output_txt - Human-readable summary")
        
    catch e
        println("Error: $e")
        exit(1)
    end
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
