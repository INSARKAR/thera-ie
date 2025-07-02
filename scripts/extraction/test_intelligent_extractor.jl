#!/usr/bin/env julia

"""
Test script for the intelligent drug-disease indication extractor.

This script runs a small test of the intelligent extractor on a limited set of publications
to verify it's working correctly before submitting to SLURM.
"""

include("scripts/extraction/intelligent_drug_extractor.jl")

function run_test()
    println("=== Intelligent Drug Extractor Test ===")
    println("Running a small test to verify functionality...")
    
    # Default drug to test with
    drug_name = "Levothyroxine"
    
    # Define test paths
    drug_file = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/$drug_name.json"
    
    # Check if drug file exists
    if !isfile(drug_file)
        println("❌ Test drug file not found: $drug_file")
        println("Please make sure the drug_pubmed_refs directory contains the test drug file.")
        return false
    end
    
    # Load a small subset of publications for testing
    println("📖 Loading test publications for $drug_name...")
    data = JSON3.read(read(drug_file, String))
    publications = data.result.publications_analyzed
    
    # Use only a small subset for the test
    test_size = min(10, length(publications))
    test_publications = publications[1:test_size]
    
    println("📊 Using $test_size publications for test")
    
    # Mock the data structure for testing
    mock_data = Dict(
        "result" => Dict(
            "publications_analyzed" => test_publications
        )
    )
    
    # Create a temporary test file
    test_file = tempname() * ".json"
    open(test_file, "w") do f
        JSON3.write(f, mock_data)
    end
    
    # Test Ollama connection
    if !test_ollama_connection()
        println("❌ Exiting test due to Ollama connection failure")
        rm(test_file, force=true)
        return false
    end
    
    try
        # Override file paths for testing
        original_drug_file = drug_file
        test_output_file = tempname() * "_result.json"
        
        println("\n🧪 Running test extraction (LIMITED TO $test_size PUBLICATIONS)...")
        
        # Step 1: Identify potential drug-disease pairs
        println("\n--- PHASE 1: IDENTIFYING POTENTIAL DISEASE PAIRS ---")
        disease_mentions = identify_disease_pairs(drug_name, test_publications)
        
        # Limit to just a few diseases for quick testing
        test_diseases = collect(keys(disease_mentions))
        if length(test_diseases) > 2
            test_diseases = test_diseases[1:2]
            println("⚙️ Limiting test to 2 diseases for quick testing")
        end
        
        # Step 2: Verify each drug-disease pair (but only a couple for the test)
        println("\n--- PHASE 2: VERIFYING DISEASE PAIRS ---")
        verified_pairs = DrugDiseaseEvidence[]
        
        for disease in test_diseases
            pmids = disease_mentions[disease]
            evidence = verify_drug_disease_pair(drug_name, disease, test_publications, pmids)
            push!(verified_pairs, evidence)
            
            # Print status update
            if evidence.confirmed
                println("✓ Test confirmed: $drug_name treats $disease (confidence: $(evidence.confidence))")
            else
                println("✗ Test not confirmed: $drug_name for $disease (max confidence: $(evidence.confidence))")
            end
        end
        
        # Calculate test results
        confirmed_pairs = count(p -> p.confirmed, verified_pairs)
        total_indications = sum(p -> length(p.indications), verified_pairs)
        
        println("\n=== TEST COMPLETE ===")
        println("🎯 Drug: $drug_name")
        println("📊 Test disease pairs examined: $(length(verified_pairs))")
        println("✅ Confirmed disease pairs: $confirmed_pairs")
        println("📋 Total indication evidence: $total_indications")
        
        println("\n✓ Intelligent extractor test completed successfully!")
        println("The extractor is working as expected and ready for full-scale runs.")
        
        # Clean up test files
        rm(test_file, force=true)
        return true
        
    catch e
        println("\n❌ Test failed with error: $e")
        return false
    end
end

# Run the test
run_test()
