#!/usr/bin/env julia

"""
Dual GPU Batch Enhanced Naive Llama Drug Indication Extractor

This script processes multiple drugs across two GPUs simultaneously for maximum efficiency.
Each GPU processes a separate batch of drugs concurrently.

Usage:
    julia dual_gpu_batch_enhanced_naive.jl [start_index] [batch_size]

Example:
    julia dual_gpu_batch_enhanced_naive.jl 1 400  # Process drugs 1-400 (200 per GPU)

Arguments:
    start_index: Starting index of drugs to process (default: 1)
    batch_size: Total number of drugs to process (will be split across 2 GPUs, default: 400)
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/prompts/llm_prompt_naive.txt"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera-ie/llama_naive_extracted_indications"
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/approved_drugs_dict.json"

# GPU Server Configuration
const GPU1_HOST = "http://localhost:11434"
const GPU2_HOST = "http://localhost:11435"

# Include the data structures and functions from enhanced_naive_llama_extractor.jl
include("enhanced_naive_llama_extractor.jl")

function test_ollama_connection_gpu(host::String, gpu_name::String)
    """Test if Ollama server is accessible on specified host"""
    try
        response = HTTP.get("$(host)/api/tags"; connect_timeout=5, readtimeout=10)
        if response.status == 200
            println("✓ $gpu_name Ollama server accessible at $host")
            return true
        else
            println("❌ $gpu_name Ollama server returned status $(response.status)")
            return false
        end
    catch e
        println("❌ Cannot connect to $gpu_name Ollama at $host: $e")
        return false
    end
end

function query_llama_gpu(prompt::String, host::String, gpu_name::String; temperature=0.3, max_tokens=1000)
    """Query the Llama model on a specific GPU/host"""
    try
        payload = Dict(
            "model" => MODEL_NAME,
            "prompt" => prompt,
            "stream" => false,
            "options" => Dict(
                "temperature" => temperature,
                "num_predict" => max_tokens
            )
        )
        
        response = HTTP.post(
            "$(host)/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=10,
            readtimeout=120
        )
        
        result = JSON3.read(String(response.body))
        return get(result, "response", "")
    catch e
        println("❌ [$gpu_name] Llama query failed: $e")
        return nothing
    end
end

function get_unprocessed_drugs_dual()
    """Get list of all unprocessed drugs for dual GPU processing"""
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

function process_gpu_batch(gpu_batch_drugs::Vector{String}, gpu_host::String, gpu_name::String, prompt_template::String)
    """Process a batch of drugs on a specific GPU"""
    
    println("🚀 [$gpu_name] Starting batch processing of $(length(gpu_batch_drugs)) drugs...")
    
    successful = 0
    failed = 0
    total_indications = 0
    total_confirmed = 0
    batch_start_time = time()
    
    for (i, drug_name) in enumerate(gpu_batch_drugs)
        println("\\n[$gpu_name] [$(i)/$(length(gpu_batch_drugs))] Processing $drug_name...")
        
        try
            # Check if already processed (in case of concurrent runs)
            output_file = joinpath(OUTPUT_DIR, "$(drug_name)_enhanced_naive_extracted_indications.json")
            if isfile(output_file)
                println("✓ [$gpu_name] Already processed, skipping")
                successful += 1
                continue
            end
            
            # Format the prompt with drug name
            formatted_prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
            
            # Query Llama on this GPU
            drug_start_time = time()
            response = query_llama_gpu(formatted_prompt, gpu_host, gpu_name)
            
            if response === nothing
                println("❌ [$gpu_name] Failed to get response from Llama")
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
                "enhanced_naive_knowledge_based_dual_gpu_batch",
                response,           # Raw LLM response
                formatted_prompt    # Prompt used
            )
            
            # Save results
            if save_enhanced_results(result, output_file)
                println("✅ [$gpu_name] Successfully extracted $(length(indications)) indications ($(confirmed_count) confirmed)")
                println("   📄 Raw response: $(length(response)) characters")
                println("   ⏱️  Processing time: $(round(processing_time, digits=2)) seconds")
                successful += 1
                total_indications += length(indications)
                total_confirmed += confirmed_count
            else
                println("⚠️  [$gpu_name] Extraction completed but failed to save")
                failed += 1
            end
            
        catch e
            println("❌ [$gpu_name] Error processing $drug_name: $e")
            failed += 1
        end
        
        # Small delay to avoid overwhelming the API
        sleep(0.3)
    end
    
    # Calculate batch statistics
    batch_processing_time = time() - batch_start_time
    
    println("\\n=== [$gpu_name] Batch Processing Summary ===")
    println("✅ Successful: $successful")
    println("❌ Failed: $failed")
    println("📊 Total processed: $(successful + failed)/$(length(gpu_batch_drugs))")
    println("📋 Total indications extracted: $total_indications")
    println("✅ Total confirmed indications: $total_confirmed")
    println("📈 Average indications per drug: $(successful > 0 ? round(total_indications / successful, digits=1) : 0.0)")
    println("📈 Average confirmed per drug: $(successful > 0 ? round(total_confirmed / successful, digits=1) : 0.0)")
    println("⏱️  Total batch time: $(round(batch_processing_time, digits=2)) seconds")
    println("⏱️  Average time per drug: $(successful > 0 ? round(batch_processing_time / successful, digits=2) : 0.0) seconds")
    
    return (successful, failed, total_indications, total_confirmed, batch_processing_time)
end

function dual_gpu_batch_process_drugs(start_idx::Int, total_batch_size::Int)
    """Process drugs using both GPUs simultaneously"""
    
    println("=== Dual GPU Batch Enhanced Naive Drug Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    println("GPU1 host: $GPU1_HOST")
    println("GPU2 host: $GPU2_HOST")
    
    # Test both Ollama connections
    println("\\n=== Testing Ollama Connections ===")
    if !test_ollama_connection_gpu(GPU1_HOST, "GPU1")
        println("❌ Exiting due to GPU1 Ollama connection failure")
        exit(1)
    end
    
    if !test_ollama_connection_gpu(GPU2_HOST, "GPU2")
        println("❌ Exiting due to GPU2 Ollama connection failure")
        exit(1)
    end
    
    println("✓ Both Ollama servers are accessible")
    
    # Load prompt template once
    prompt_template = load_prompt_template()
    if prompt_template === nothing
        println("❌ Failed to load prompt template")
        exit(1)
    end
    
    # Get unprocessed drugs
    unprocessed = get_unprocessed_drugs_dual()
    println("\\n📊 Total unprocessed drugs: $(length(unprocessed))")
    
    # Calculate batch range
    end_idx = min(start_idx + total_batch_size - 1, length(unprocessed))
    
    if start_idx > length(unprocessed)
        println("⚠️  Start index ($start_idx) exceeds unprocessed count ($(length(unprocessed)))")
        return
    end
    
    batch_drugs = unprocessed[start_idx:end_idx]
    actual_batch_size = length(batch_drugs)
    
    # Split drugs across two GPUs
    gpu1_batch_size = div(actual_batch_size, 2)
    gpu2_batch_size = actual_batch_size - gpu1_batch_size
    
    gpu1_drugs = batch_drugs[1:gpu1_batch_size]
    gpu2_drugs = batch_drugs[gpu1_batch_size+1:end]
    
    println("📦 Processing batch: drugs $start_idx to $end_idx ($actual_batch_size total drugs)")
    println("🎯 GPU1 batch: $(length(gpu1_drugs)) drugs")
    println("🎯 GPU2 batch: $(length(gpu2_drugs)) drugs")
    
    # Start parallel processing
    println("\\n=== Starting Dual GPU Processing ===")
    dual_start_time = time()
    
    # Create tasks for parallel execution
    task1 = @async process_gpu_batch(gpu1_drugs, GPU1_HOST, "GPU1", prompt_template)
    task2 = @async process_gpu_batch(gpu2_drugs, GPU2_HOST, "GPU2", prompt_template)
    
    # Wait for both tasks to complete
    result1 = fetch(task1)
    result2 = fetch(task2)
    
    # Calculate combined results
    dual_processing_time = time() - dual_start_time
    
    total_successful = result1[1] + result2[1]
    total_failed = result1[2] + result2[2]
    total_indications = result1[3] + result2[3]
    total_confirmed = result1[4] + result2[4]
    
    println("\\n=== DUAL GPU BATCH PROCESSING COMPLETE ===")
    println("✅ Total successful: $total_successful")
    println("❌ Total failed: $total_failed")
    println("📊 Total processed: $(total_successful + total_failed)/$actual_batch_size")
    println("📋 Total indications extracted: $total_indications")
    println("✅ Total confirmed indications: $total_confirmed")
    println("📈 Average indications per drug: $(total_successful > 0 ? round(total_indications / total_successful, digits=1) : 0.0)")
    println("📈 Average confirmed per drug: $(total_successful > 0 ? round(total_confirmed / total_successful, digits=1) : 0.0)")
    println("⏱️  Total dual GPU time: $(round(dual_processing_time, digits=2)) seconds")
    println("⏱️  Average time per drug: $(total_successful > 0 ? round(dual_processing_time / total_successful, digits=2) : 0.0) seconds")
    println("🚀 Effective speedup: ~2x vs single GPU processing")
    println("⏱️  End time: $(now())")
    
    # Calculate theoretical vs actual time
    gpu1_time = result1[5]
    gpu2_time = result2[5]
    sequential_time = gpu1_time + gpu2_time
    speedup = sequential_time / dual_processing_time
    
    println("\\n📊 Performance Analysis:")
    println("   GPU1 processing time: $(round(gpu1_time, digits=2)) seconds")
    println("   GPU2 processing time: $(round(gpu2_time, digits=2)) seconds")
    println("   Sequential time would be: $(round(sequential_time, digits=2)) seconds")
    println("   Actual parallel time: $(round(dual_processing_time, digits=2)) seconds")
    println("   Speedup achieved: $(round(speedup, digits=2))x")
end

function show_dual_gpu_status()
    """Show current status and suggest dual GPU batch commands"""
    println("=== Dual GPU Batch Processing Status ===")
    
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
        println("\\n💡 Suggested dual GPU batch commands (400 drugs per job = 200 per GPU):")
        batch_size = 400
        batches_needed = ceil(Int, unprocessed / batch_size)
        
        for batch_num in 1:min(batches_needed, 5)
            start_idx = processed + ((batch_num - 1) * batch_size) + 1
            println("   julia dual_gpu_batch_enhanced_naive.jl $start_idx $batch_size")
        end
        
        if batches_needed > 5
            println("   ... and $(batches_needed - 5) more batches")
        end
        
        println("\\n⚡ With dual GPU processing:")
        println("   Estimated batches needed: $batches_needed")
        println("   Estimated total time: ~$(batches_needed * 2) GPU hours")
        println("   Effective processing rate: ~200 drugs per GPU hour")
    end
end

function main()
    """Main function for dual GPU batch processing"""
    
    # Parse command line arguments
    if length(ARGS) == 0
        show_dual_gpu_status()
        return
    end
    
    start_idx = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1
    total_batch_size = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 400
    
    # Create output directory if needed
    mkpath(OUTPUT_DIR)
    
    # Process the batch
    dual_gpu_batch_process_drugs(start_idx, total_batch_size)
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end