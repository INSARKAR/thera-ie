#!/usr/bin/env julia

"""
PubMed Drug Search

This program searches PubMed for publications mentioning approved drugs using 
the NCBI Entrez API. It focuses on finding drug-related publications for
disease association analysis.

Usage:
    julia pubmed_drug_search.jl

Input:
    - approved_drugs_dict.jl (Dictionary of approved drugs and indications)

Output:
    - pubmed_search_results.json (Search results with PMIDs)
    - pubmed_search_results.txt (Human-readable summary)

The program:
1. Loads approved drugs from the dictionary
2. Searches PubMed for each drug name
3. Retrieves PMIDs for disease association analysis
4. Limits to first 10 drugs for demonstration
"""

using HTTP
using JSON3
using Dates

# Configuration
const MAX_DRUGS = 10  # Limit searches for demonstration
const MAX_RESULTS_PER_DRUG = 50  # Maximum PMIDs to retrieve per drug

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
    save_search_results(results::Vector, filename::String)

Save search results to JSON file.
"""
function save_search_results(results::Vector, filename::String)
    output_data = Dict(
        "metadata" => Dict(
            "generated_on" => string(now()),
            "total_drugs_searched" => length(results),
            "description" => "PubMed search results for approved drugs"
        ),
        "results" => results
    )
    
    open(filename, "w") do file
        write(file, JSON3.write(output_data))
    end
    
    println("Search results saved to: $filename")
end

"""
    save_search_summary(results::Vector, filename::String)

Save human-readable summary of search results.
"""
function save_search_summary(results::Vector, filename::String)
    open(filename, "w") do file
        write(file, "PubMed Drug Search Results\\n")
        write(file, "Generated on: $(now())\\n")
        write(file, "="^50 * "\\n\\n")
        
        total_publications = sum(r["count"] for r in results)
        successful_searches = sum(1 for r in results if r["status"] == "success")
        
        write(file, "SUMMARY\\n")
        write(file, "-------\\n")
        write(file, "Drugs searched: $(length(results))\\n")
        write(file, "Successful searches: $successful_searches\\n") 
        write(file, "Total publications found: $total_publications\\n\\n")
        
        write(file, "DETAILED RESULTS\\n")
        write(file, "================\\n\\n")
        
        for (i, result) in enumerate(results)
            drug_name = result["drug_name"]
            indication = result["indication"]
            count = result["count"]
            status = result["status"]
            
            write(file, "$i. $drug_name\\n")
            write(file, "   Status: $status\\n")
            write(file, "   Publications found: $count\\n")
            write(file, "   Indication: $(indication[1:min(100, length(indication))])...\\n")
            
            if haskey(result, "pmids") && length(result["pmids"]) > 0
                pmid_sample = join(result["pmids"][1:min(3, length(result["pmids"]))], ", ")
                write(file, "   Sample PMIDs: $pmid_sample\\n")
            end
            write(file, "\\n")
        end
    end
    
    println("Search summary saved to: $filename")
end

"""
    main()

Main function to run the PubMed drug search.
"""
function main()
    println("PubMed Drug Search")
    println("==================")
    println("Searching PubMed for approved drugs...")
    println()
    
    # Load approved drugs
    try
        drugs_dict = load_approved_drugs()
        println("Loaded $(length(drugs_dict)) approved drugs")
        println("Limiting search to first $MAX_DRUGS drugs for demonstration")
        println()
        
        # Convert to array and limit
        drug_list = collect(drugs_dict)[1:min(MAX_DRUGS, length(drugs_dict))]
        
        # Search for each drug
        results = Vector{Dict}()
        
        for (i, (drug_name, indication)) in enumerate(drug_list)
            println("[$i/$MAX_DRUGS] Searching: $drug_name")
            
            # Search PubMed
            search_result = search_pubmed(drug_name; retmax=MAX_RESULTS_PER_DRUG)
            
            # Add drug info to result
            result = Dict(
                "drug_name" => drug_name,
                "indication" => indication,
                "status" => search_result["status"],
                "count" => search_result["count"],
                "pmids" => search_result["pmids"]
            )
            
            if haskey(search_result, "error")
                result["error"] = search_result["error"]
            end
            
            push!(results, result)
            
            # Display result
            if search_result["status"] == "success"
                count = search_result["count"]
                pmids_retrieved = length(search_result["pmids"])
                println("  ✓ Found $count publications ($pmids_retrieved PMIDs retrieved)")
            else
                println("  ✗ Search failed: $(search_result["error"])")
            end
            
            # Small delay to be respectful to NCBI servers
            sleep(0.5)
        end
        
        println()
        
        # Save results
        save_search_results(results, "pubmed_search_results.json")
        save_search_summary(results, "pubmed_search_results.txt")
        
        # Final summary
        total_pubs = sum(r["count"] for r in results)
        successful = sum(1 for r in results if r["status"] == "success")
        
        println()
        println("SEARCH COMPLETED!")
        println("=================")
        println("Drugs searched: $(length(results))")
        println("Successful searches: $successful")
        println("Total publications found: $total_pubs")
        println()
        println("Next step: Run pubmed_disease_analyzer.jl to analyze disease associations")
        
    catch e
        println("Error: $e")
        println()
        println("Make sure you have run approved_drugs_extractor.jl first!")
        exit(1)
    end
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
