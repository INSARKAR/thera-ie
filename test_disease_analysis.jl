#!/usr/bin/env julia

"""
Simple test to isolate the disease analysis functionality
"""

using HTTP
using JSON3
using Dates

# Load the mesh headings
include("mesh_t047_headings.jl")

function test_fetch_details()
    pmids = ["17323171", "19167304", "10600889"]
    
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    
    pmid_string = join(pmids, ",")
    params = Dict(
        "db" => "pubmed",
        "id" => pmid_string,
        "retmode" => "xml",
        "tool" => "julia_pubmed_search",
        "email" => "researcher@example.com"
    )
    
    try
        response = HTTP.get(base_url, query=params)
        
        if response.status == 200
            println("✓ Successfully fetched XML data")
            xml_data = String(response.body)
            
            # Extract publications with basic regex
            article_pattern = r"<PubmedArticle>(.*?)</PubmedArticle>"s
            article_matches = eachmatch(article_pattern, xml_data)
            
            println("Found $(length(collect(article_matches))) articles")
            
            return true
        else
            println("✗ HTTP error: $(response.status)")
            return false
        end
        
    catch e
        println("✗ Error: $e")
        return false
    end
end

# Test the function
if test_fetch_details()
    println("Test successful!")
else
    println("Test failed!")
end
