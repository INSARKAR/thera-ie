#!/usr/bin/env julia

"""
Dual GPU Naive Extraction Coordinator

This script manages parallel processing of two drugs simultaneously using
two different GPUs with separate Ollama instances for naive knowledge-based extraction.

Usage:
    julia dual_gpu_naive_coordinator.jl drug1 drug2

The script will:
1. Process drug1 using GPU 0 with Ollama on port 11434
2. Process drug2 using GPU 1 with Ollama on port 11435
3. Run both extractions in parallel
"""

using Distributed
using JSON3
using Dates

# Add worker processes
addprocs(2)

# Load required modules on all workers
@everywhere begin
    include("/oscar/home/isarkar/sarkarcode/thera-ie/scripts/extraction/naive_llama_extractor.jl")
end

# Function to process a drug on a specific GPU
@everywhere function process_drug_on_gpu(drug_name::String, gpu_id::Int)
    """Process a drug using a specific GPU and Ollama instance"""
    
    # Set environment for this worker
    port = gpu_id == 0 ? 11434 : 11435
    ENV["CUDA_VISIBLE_DEVICES"] = string(gpu_id)
    ENV["OLLAMA_HOST"] = "http://localhost:$port"
    
    println("[GPU $gpu_id] Processing $drug_name on port $port...")
    
    try
        # Define output file
        output_dir = "/oscar/home/isarkar/sarkarcode/thera-ie/llama_naive_extracted_indications"
        output_file = joinpath(output_dir, "$(drug_name)_naive_extracted_indications.json")
        
        # Skip if already processed
        if isfile(output_file)
            println("[GPU $gpu_id] ✓ $drug_name already processed, skipping")
            return true
        end
        
        # Process the drug
        result = process_drug_naive(drug_name)
        
        if result !== nothing
            # Save results
            if save_results(result, output_file)
                println("[GPU $gpu_id] ✓ $drug_name completed successfully")
                return true
            else
                println("[GPU $gpu_id] ⚠️ $drug_name completed but failed to save")
                return false
            end
        else
            println("[GPU $gpu_id] ❌ $drug_name extraction failed")
            return false
        end
    catch e
        println("[GPU $gpu_id] ❌ Error processing $drug_name: $e")
        return false
    end
end

function main()
    """Main coordinator function"""
    
    if length(ARGS) < 2
        println("Usage: julia dual_gpu_naive_coordinator.jl drug1 drug2")
        exit(1)
    end
    
    drug1 = ARGS[1]
    drug2 = ARGS[2]
    
    println("=== Dual GPU Naive Extraction Coordinator ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    println("Processing: $drug1 (GPU 0) and $drug2 (GPU 1)")
    println("=" ^ 50)
    
    start_time = time()
    
    # Launch parallel processing
    task1 = @spawnat 2 process_drug_on_gpu(drug1, 0)
    task2 = @spawnat 3 process_drug_on_gpu(drug2, 1)
    
    # Wait for both tasks to complete
    result1 = fetch(task1)
    result2 = fetch(task2)
    
    processing_time = time() - start_time
    
    # Print summary
    println("\n=== DUAL GPU PROCESSING COMPLETE ===")
    println("Total processing time: $(round(processing_time, digits=2)) seconds")
    println("Drug 1 ($drug1): $(result1 ? "✓ Success" : "✗ Failed")")
    println("Drug 2 ($drug2): $(result2 ? "✓ Success" : "✗ Failed")")
    
    # Exit with appropriate code
    if result1 && result2
        exit(0)
    else
        exit(1)
    end
end

# Run the coordinator
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end