#!/usr/bin/env julia

"""
Batch Enhanced Naive Llama Drug Indication Extractor

This script processes multiple drugs in a single job to avoid repeated model loading
and includes raw LLM responses for later analysis.

Usage:
    julia batch_enhanced_naive_extractor.jl [start_index] [batch_size]

Example:
    julia batch_enhanced_naive_extractor.jl 1 100  # Process drugs 1-100

Arguments:
    start_index: Starting index of drugs to process (default: 1)
    batch_size: Number of drugs to process in this batch (default: 100)
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera/prompts/llm_prompt_naive.txt"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera/phase1_llama_naive_extracted_indications"
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.json"

# Get Ollama host from environment
function get_ollama_host()
    return get(ENV, "OLLAMA_HOST", "http://localhost:11434")
end

# Include the data structures and functions from enhanced_naive_llama_extractor.jl
include("enhanced_naive_llama_extractor.jl")

function get_unprocessed_drugs()
    """Get list of all unprocessed drugs"""
    # Load approved drugs
    data = JSON3.read(read(APPROVED_DRUGS_FILE, String))
    all_drugs = sort(collect(keys(data.drugs)))
    
    # Filter unprocessed (check for enhanced version)
    unprocessed = String[]
    for drug in all_drugs
        output_file = joinpath(OUTPUT_DIR, "$(drug)_enhanced_naive_extracted_indications.json")
        if !isfile(output_file)
            push!(unprocessed, String(drug))
        end
    end
    
    return unprocessed
end

function batch_process_drugs_enhanced(start_idx::Int, batch_size::Int)
    """Process a batch of drugs efficiently with enhanced features"""
    
    println("=== Batch Enhanced Naive Drug Indication Extractor ===")
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
    
    # Convert 0-based start_idx to 1-based for Julia
    julia_start_idx = start_idx + 1
    
    # Calculate batch range
    end_idx = min(julia_start_idx + batch_size - 1, length(unprocessed))
    
    if julia_start_idx > length(unprocessed)
        println("⚠️  Start index ($julia_start_idx) exceeds unprocessed count ($(length(unprocessed)))")
        return
    end
    
    batch_drugs = unprocessed[julia_start_idx:end_idx]
    println("📦 Processing batch: drugs $start_idx to $end_idx ($(length(batch_drugs)) drugs)")
    
    # Process each drug in the batch
    successful = 0
    failed = 0
    total_indications = 0
    total_confirmed = 0
    batch_start_time = time()
    
    for (i, drug_name) in enumerate(batch_drugs)
        println("\\n[$start_idx + $(i-1)/$(length(batch_drugs))] Processing $drug_name...")
        
        try
            # Check if already processed (in case of concurrent runs)
            output_file = joinpath(OUTPUT_DIR, "$(drug_name)_enhanced_naive_extracted_indications.json")
            if isfile(output_file)
                println("✓ Already processed, skipping")
                successful += 1
                continue
            end
            
            # Format the prompt with drug name
            formatted_prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
            
            # Query Llama
            drug_start_time = time()
            response = query_llama(formatted_prompt)
            
            if response === nothing
                println("❌ Failed to get response from Llama")
                failed += 1
                continue
            end
            
            # Parse response
            indications = parse_naive_response(response)
            
            # Count confirmed indications
            confirmed_count = count(ind -> ind.confidence >= CONFIDENCE_THRESHOLD, indications)
            
            # Create enhanced result with raw response
            processing_time = time() - drug_start_time
            result = EnhancedNaiveExtractionResult(
                drug_name,
                length(indications),
                confirmed_count,
                indications,
                processing_time,
                string(now()),
                MODEL_NAME,
                "enhanced_naive_knowledge_based_batch",
                response,           # Raw LLM response
                formatted_prompt    # Prompt used
            )
            
            # Save results
            if save_enhanced_results(result, output_file)
                println("✅ Successfully extracted $(length(indications)) indications ($(confirmed_count) confirmed)")
                println("   📄 Raw response: $(length(response)) characters")
                println("   ⏱️  Processing time: $(round(processing_time, digits=2)) seconds")
                successful += 1
                total_indications += length(indications)
                total_confirmed += confirmed_count
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
    
    # Calculate batch statistics
    batch_processing_time = time() - batch_start_time
    
    println("\\n=== Batch Processing Summary ===")
    println("✅ Successful: $successful")
    println("❌ Failed: $failed")
    println("📊 Total processed: $(successful + failed)/$(length(batch_drugs))")
    println("📋 Total indications extracted: $total_indications")
    println("✅ Total confirmed indications: $total_confirmed")
    println("📈 Average indications per drug: $(successful > 0 ? round(total_indications / successful, digits=1) : 0.0)")
    println("📈 Average confirmed per drug: $(successful > 0 ? round(total_confirmed / successful, digits=1) : 0.0)")
    println("⏱️  Total batch time: $(round(batch_processing_time, digits=2)) seconds")
    println("⏱️  Average time per drug: $(successful > 0 ? round(batch_processing_time / successful, digits=2) : 0.0) seconds")
    println("⏱️  End time: $(now())")
end

function show_batch_status()
    """Show current batch processing status"""
    println("=== Batch Processing Status ===")
    
    # Load approved drugs
    data = JSON3.read(read(APPROVED_DRUGS_FILE, String))
    all_drugs = sort(collect(keys(data.drugs)))
    total_drugs = length(all_drugs)
    
    # Count processed drugs
    processed = 0
    for drug in all_drugs
        output_file = joinpath(OUTPUT_DIR, "$(drug)_enhanced_naive_extracted_indications.json")
        if isfile(output_file)
            processed += 1
        end
    end
    
    unprocessed = total_drugs - processed
    completion_rate = round(processed / total_drugs * 100, digits=1)
    
    println("📊 Total drugs: $total_drugs")
    println("✅ Processed: $processed ($completion_rate%)")
    println("⏳ Remaining: $unprocessed")
    
    if unprocessed > 0
        println("\\n💡 Suggested batch commands:")
        batch_size = 200
        batches_needed = ceil(Int, unprocessed / batch_size)
        
        for batch_num in 1:min(batches_needed, 3)
            start_idx = processed + ((batch_num - 1) * batch_size) + 1
            println("   julia batch_enhanced_naive_extractor.jl $start_idx $batch_size")
        end
        
        if batches_needed > 3
            println("   ... and $(batches_needed - 3) more batches")
        end
    end
end

function main()
    """Main function for batch processing"""
    
    # Parse command line arguments
    if length(ARGS) == 0
        show_batch_status()
        return
    end
    
    start_idx = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1
    batch_size = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 200
    
    # Create output directory if needed
    mkpath(OUTPUT_DIR)
    
    # Process the batch
    batch_process_drugs_enhanced(start_idx, batch_size)
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end