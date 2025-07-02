#!/usr/bin/env julia

"""
Test the updated intelligent extractor disease identification without LLM
"""

using JSON3

# Include the functions from the intelligent extractor
include("scripts/extraction/intelligent_drug_extractor.jl")

function test_disease_identification(drug_name::String)
    """
    Test just the disease identification part without LLM queries
    """
    println("🧪 Testing disease identification for $drug_name...")
    
    # Define file paths (same as in main script)
    drug_file = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/$drug_name.json"
    
    # Validate input file
    if !isfile(drug_file)
        println("❌ Drug file not found: $drug_file")
        return false
    end
    
    # Load drug publications  
    println("📖 Loading publications for $drug_name...")
    data = JSON3.read(read(drug_file, String))
    publications = data.result.publications_analyzed
    
    println("📊 Found $(length(publications)) publications for $drug_name")
    
    # Test the disease identification function
    disease_publications = identify_disease_pairs(drug_name, publications)
    
    println("\n📋 DISEASE IDENTIFICATION RESULTS:")
    println("=" ^ 50)
    
    if !isempty(disease_publications)
        total_diseases = length(disease_publications)
        total_publications = sum(length(pubs) for pubs in values(disease_publications))
        
        println("🎯 Total diseases identified: $total_diseases")
        println("📚 Total publications ready for LLM: $total_publications")
        
        # Show top 10 diseases by publication count
        pub_counts = [(disease, length(pubs)) for (disease, pubs) in disease_publications]
        sort!(pub_counts, by=x->x[2], rev=true)
        
        println("\n🏆 Top 10 diseases by publication count:")
        for (i, (disease, count)) in enumerate(pub_counts[1:min(10, length(pub_counts))])
            println("  $i. $disease: $count publications")
        end
        
        # Show sample of one disease's publications
        if !isempty(disease_publications)
            first_disease, first_pubs = first(disease_publications)
            println("\n📄 Sample publications for '$first_disease':")
            for (i, pub) in enumerate(first_pubs[1:min(3, length(first_pubs))])
                println("  Publication $i:")
                println("    PMID: $(get(pub, "pmid", "N/A"))")
                println("    Title: $(get(pub, "title", "N/A"))")
                println("    Has Abstract: $(haskey(pub, "abstract") && !isempty(get(pub, "abstract", "")))")
                println("    Qualifiers: $(get(pub, "qualifiers", []))")
                println("    ---")
            end
        end
        
        println("\n✅ Disease identification successful!")
        return true
    else
        println("❌ No diseases identified")
        return false
    end
end

# Run the test
if length(ARGS) > 0
    drug_name = ARGS[1]
else
    drug_name = "Levothyroxine"
end

test_disease_identification(drug_name)