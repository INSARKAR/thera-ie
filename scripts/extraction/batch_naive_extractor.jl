#!/usr/bin/env julia

"""
Batch Naive Llama Drug Indication Extractor

This script processes multiple drugs in a single job to avoid repeated model loading.

Usage:
    julia batch_naive_extractor.jl [start_index] [batch_size]

Example:
    julia batch_naive_extractor.jl 1 100  # Process drugs 1-100
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera/prompts/llm_prompt_naive.txt"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications"
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.json"

# Get Ollama host from environment
function get_ollama_host()
    return get(ENV, "OLLAMA_HOST", "http://localhost:11434")
end

# Include the data structures and functions from naive_llama_extractor.jl
include("naive_llama_extractor.jl")

function get_unprocessed_drugs()
    """Get list of all unprocessed drugs"""
    # Load approved drugs
    data = JSON3.read(read(APPROVED_DRUGS_FILE, String))
    all_drugs = sort(collect(keys(data.drugs)))
    
    # Filter unprocessed
    unprocessed = String[]
    for drug in all_drugs
        output_file = joinpath(OUTPUT_DIR, "$(drug)_naive_extracted_indications.json")
        if !isfile(output_file)
            push!(unprocessed, String(drug))
        end
    end
    
    return unprocessed
end

function batch_process_drugs(start_idx::Int, batch_size::Int)
    """Process a batch of drugs efficiently"""
    
    println("=== Batch Naive Drug Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    println("Ollama host: $(get_ollama_host())")
    
    # Test Ollama connection once
    if !test_ollama_connection()
        println("❌ Exiting due to Ollama connection failure")
        exit(1)
    end
    
    # Load prompt template once
    prompt_template = load_prompt_template()
    if prompt_template === nothing
        println("❌ Failed to load prompt template")
        exit(1)
    end
    
    # Get unprocessed drugs
    unprocessed = get_unprocessed_drugs()
    println("📊 Total unprocessed drugs: $(length(unprocessed))")
    
    # Calculate batch range
    end_idx = min(start_idx + batch_size - 1, length(unprocessed))
    
    if start_idx > length(unprocessed)
        println("⚠️  Start index ($start_idx) exceeds unprocessed count ($(length(unprocessed)))")
        return
    end
    
    batch_drugs = unprocessed[start_idx:end_idx]
    println("📦 Processing batch: drugs $start_idx to $end_idx ($(length(batch_drugs)) drugs)")
    
    # Process each drug in the batch
    successful = 0
    failed = 0
    
    for (i, drug_name) in enumerate(batch_drugs)
        println("\n[$start_idx + $(i-1)/$(length(batch_drugs))] Processing $drug_name...")
        
        try
            # Check if already processed (in case of concurrent runs)
            output_file = joinpath(OUTPUT_DIR, "$(drug_name)_naive_extracted_indications.json")
            if isfile(output_file)
                println("✓ Already processed, skipping")
                successful += 1
                continue
            end
            
            # Format the prompt with drug name
            prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
            
            # Query Llama
            response = query_llama(prompt)
            
            if response === nothing
                println("❌ Failed to get response from Llama")
                failed += 1
                continue
            end
            
            # Parse response
            indications = parse_naive_response(response)
            
            # Count confirmed indications
            confirmed_count = count(ind -> ind.confidence >= CONFIDENCE_THRESHOLD, indications)
            
            # Create result
            result = NaiveExtractionResult(
                drug_name,
                length(indications),
                confirmed_count,
                indications,
                0.0,  # Will update with actual time
                string(now()),
                MODEL_NAME,
                "naive_knowledge_based_batch"
            )
            
            # Save results
            if save_results(result, output_file)
                println("✅ Successfully extracted $(length(indications)) indications ($(confirmed_count) confirmed)")
                successful += 1
            else
                println("⚠️  Extraction completed but failed to save")
                failed += 1
            end
            
        catch e
            println("❌ Error processing $drug_name: $e")
            failed += 1
        end
        
        # Small delay to avoid overwhelming the API
        sleep(0.5)
    end
    
    println("\n=== Batch Processing Summary ===")
    println("✅ Successful: $successful")
    println("❌ Failed: $failed")
    println("📊 Total processed: $(successful + failed)/$(length(batch_drugs))")
    println("⏱️  End time: $(now())")
end

function main()
    """Main function for batch processing"""
    
    # Parse command line arguments
    start_idx = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1
    batch_size = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 100
    
    # Create output directory if needed
    mkpath(OUTPUT_DIR)
    
    # Process the batch
    batch_process_drugs(start_idx, batch_size)
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end