#!/usr/bin/env julia

# Phase 2 Step 1: Simple DrugBank Llama Indication Extractor
# Processes remaining drugs sequentially using single GPU
# Usage: julia phase2_step1_simple_drugbank_extractor.jl

using HTTP
using JSON3
using Dates

# Configuration - use existing drugbank extractor logic
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const OLLAMA_HOST = get(ENV, "OLLAMA_HOST", "http://localhost:11434")

# File paths
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/generated_dependency_files/approved_drugs_dict.jl"
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/prompts/llm_prompt_drugbank.txt"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera-ie/phase2_indications_llama_drugbank"

# Include all the existing DrugBank extractor functions
include("/oscar/home/isarkar/sarkarcode/thera-ie/scripts/extraction/drugbank_llama_extractor.jl")

function check_existing_output(drug_name::String)
    """Check if output file already exists for this drug"""
    output_file = joinpath(OUTPUT_DIR, "$(drug_name)_drugbank_extracted_indications.json")
    return isfile(output_file)
end

function process_remaining_drugs()
    """Process all remaining unprocessed drugs"""
    
    println("=== Phase 2 Step 1: Simple DrugBank Llama Extractor ===")
    println("Start time: $(now())")
    println("")
    
    # Load approved drugs data
    drugs_data = load_approved_drugs()
    if drugs_data === nothing
        exit(1)
    end
    
    total_drugs = length(drugs_data)
    println("📊 Total drugs: $total_drugs")
    
    # Filter to unprocessed drugs
    drugs_to_process = []
    already_processed = 0
    
    for (drug_name, indication_text) in drugs_data
        if check_existing_output(string(drug_name))
            already_processed += 1
        else
            push!(drugs_to_process, (string(drug_name), indication_text))
        end
    end
    
    remaining_count = length(drugs_to_process)
    println("✅ Already processed: $already_processed/$total_drugs")
    println("📋 Remaining to process: $remaining_count")
    
    if remaining_count == 0
        println("\n🎉 All drugs have been processed!")
        return
    end
    
    # Test Ollama connection
    if !test_ollama_connection()
        exit(1)
    end
    
    # Load prompt template
    prompt_template = load_drugbank_prompt()
    if prompt_template === nothing
        exit(1)
    end
    
    # Process each remaining drug
    processed_count = 0
    failed_count = 0
    start_time = time()
    
    for (idx, (drug_name, indication_text)) in enumerate(drugs_to_process)
        println("\n=== Processing $idx/$remaining_count ===")
        println("🔍 Drug: $drug_name")
        
        # Process the drug
        result = process_drug_indication(drug_name, indication_text, prompt_template)
        if result === nothing
            failed_count += 1
            continue
        end
        
        # Save results
        if save_drug_result(result)
            processed_count += 1
            println("✅ Extracted $(result.total_indications) indications ($(result.confirmed_indications) confirmed)")
        else
            failed_count += 1
        end
        
        # Progress report every 25 drugs
        if idx % 25 == 0
            elapsed = time() - start_time
            rate = processed_count / elapsed
            remaining = remaining_count - idx
            eta = remaining / rate
            println("")
            println("📊 Progress Report:")
            println("  Processed: $processed_count")
            println("  Failed: $failed_count")
            println("  Rate: $(round(rate * 60, digits=1)) drugs/min")
            println("  ETA: $(round(eta / 60, digits=1)) minutes")
            println("")
        end
        
        # Small delay to avoid overwhelming the API
        sleep(1)
    end
    
    # Final summary
    total_time = time() - start_time
    println("")
    println("=== EXTRACTION COMPLETE ===")
    println("✅ Successfully processed: $processed_count drugs")
    println("❌ Failed: $failed_count drugs")
    println("📊 Total remaining: $remaining_count drugs")
    println("⏱️  Total time: $(round(total_time / 60, digits=1)) minutes")
    println("📈 Processing rate: $(round(processed_count / (total_time / 60), digits=1)) drugs/min")
    println("End time: $(now())")
end

# Run the processor
if abspath(PROGRAM_FILE) == @__FILE__
    process_remaining_drugs()
end