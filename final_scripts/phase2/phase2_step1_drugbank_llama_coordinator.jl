#!/usr/bin/env julia

# Phase 2 Step 1: Dual-GPU DrugBank Llama Coordinator
# Manages parallel extraction of DrugBank indications using two GPUs
# Usage: julia phase2_step1_drugbank_llama_coordinator.jl

using Dates

# Configuration
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/generated_dependency_files/approved_drugs_dict.jl"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera-ie/phase2_indications_llama_drugbank"
const WORKER_SCRIPT = "/oscar/home/isarkar/sarkarcode/thera-ie/scripts/extraction/phase2_step1_drugbank_llama_extractor.jl"

# GPU Configuration
const GPU0_PORT = 11434
const GPU1_PORT = 11435

function load_approved_drugs()
    """Load the approved drugs dictionary from Julia file"""
    try
        include(APPROVED_DRUGS_FILE)
        # The file defines APPROVED_DRUGS_DICT
        return APPROVED_DRUGS_DICT
    catch e
        println("❌ Failed to load approved drugs file: $e")
        return nothing
    end
end

function check_existing_output(drug_name::String)
    """Check if output file already exists for this drug"""
    output_file = joinpath(OUTPUT_DIR, "$(drug_name)_drugbank_extracted_indications.json")
    return isfile(output_file)
end

function start_ollama_server(gpu_id::Int, port::Int)
    """Start Ollama server on specified GPU and port"""
    println("🚀 Starting Ollama server on GPU $gpu_id (port $port)...")
    
    # Set environment for this GPU
    env = copy(ENV)
    env["CUDA_VISIBLE_DEVICES"] = string(gpu_id)
    env["OLLAMA_HOST"] = "http://127.0.0.1:$port"
    env["OLLAMA_MODELS"] = "/oscar/work/isarkar/thera_scratch/ollama_models"
    
    # Start Ollama serve in background
    cmd = addenv(`ollama serve`, env)
    ollama_process = run(pipeline(cmd, stdout=devnull, stderr=devnull), wait=false)
    
    # Wait for server to be ready
    println("⏳ Waiting for Ollama server to start...")
    for i in 1:30  # 30 second timeout
        try
            response = run(`curl -s http://localhost:$port/api/tags`, wait=true)
            println("✅ Ollama server ready on port $port")
            return ollama_process
        catch
            sleep(1)
        end
    end
    
    println("❌ Failed to start Ollama server on port $port")
    return nothing
end

function ensure_model_loaded(port::Int)
    """Ensure llama3.2 model is loaded on the specified server"""
    println("🔍 Checking if llama3.2 model is available on port $port...")
    
    try
        # Pull the model if needed
        run(`curl -X POST http://localhost:$port/api/pull -d '{"name":"llama3.2"}'`)
        println("✅ Model llama3.2 ready on port $port")
        return true
    catch e
        println("❌ Failed to ensure model on port $port: $e")
        return false
    end
end

function main()
    """Main coordinator function"""
    
    println("=== Phase 2 Step 1: Dual-GPU DrugBank Llama Coordinator ===")
    println("Start time: $(now())")
    println("")
    
    # Create output directory
    mkpath(OUTPUT_DIR)
    
    # Load approved drugs
    println("📚 Loading approved drugs dictionary...")
    drugs_data = load_approved_drugs()
    if drugs_data === nothing
        exit(1)
    end
    
    all_drugs = collect(drugs_data)
    total_drugs = length(all_drugs)
    println("📊 Total drugs: $total_drugs")
    
    # Check existing progress
    println("\n🔍 Scanning for existing results...")
    completed_count = 0
    drugs_to_process = []
    
    for (idx, (drug_name, indication_text)) in enumerate(all_drugs)
        if check_existing_output(drug_name)
            completed_count += 1
        else
            push!(drugs_to_process, idx)
        end
    end
    
    remaining_count = length(drugs_to_process)
    println("✅ Already completed: $completed_count/$total_drugs")
    println("📋 Remaining to process: $remaining_count")
    
    if remaining_count == 0
        println("\n🎉 All drugs have been processed!")
        exit(0)
    end
    
    # Split remaining drugs between GPUs
    midpoint = div(remaining_count, 2)
    gpu0_indices = drugs_to_process[1:midpoint]
    gpu1_indices = drugs_to_process[midpoint+1:end]
    
    # Get start and end indices for each GPU
    gpu0_start = minimum(gpu0_indices)
    gpu0_end = maximum(gpu0_indices)
    gpu1_start = minimum(gpu1_indices)
    gpu1_end = maximum(gpu1_indices)
    
    println("\n📊 Work distribution:")
    println("  GPU 0: Process indices $gpu0_start-$gpu0_end ($(length(gpu0_indices)) drugs)")
    println("  GPU 1: Process indices $gpu1_start-$gpu1_end ($(length(gpu1_indices)) drugs)")
    
    # Start Ollama servers
    println("\n🚀 Starting Ollama servers...")
    ollama_procs = []
    
    # GPU 0
    proc0 = start_ollama_server(0, GPU0_PORT)
    if proc0 === nothing
        println("❌ Failed to start GPU 0 server")
        exit(1)
    end
    push!(ollama_procs, proc0)
    
    # GPU 1
    proc1 = start_ollama_server(1, GPU1_PORT)
    if proc1 === nothing
        println("❌ Failed to start GPU 1 server")
        kill(proc0)
        exit(1)
    end
    push!(ollama_procs, proc1)
    
    # Ensure models are loaded
    println("\n📦 Ensuring models are loaded...")
    if !ensure_model_loaded(GPU0_PORT) || !ensure_model_loaded(GPU1_PORT)
        println("❌ Failed to load models")
        for proc in ollama_procs
            kill(proc)
        end
        exit(1)
    end
    
    # Start worker processes
    println("\n🚀 Starting worker processes...")
    
    # Note: We need to process ALL indices in range, workers will skip existing
    worker_procs = []
    
    # GPU 0 worker
    println("Starting GPU 0 worker...")
    env0 = copy(ENV)
    env0["CUDA_VISIBLE_DEVICES"] = "0"
    proc0 = run(addenv(`julia $WORKER_SCRIPT $gpu0_start $gpu0_end 0`, env0), wait=false)
    push!(worker_procs, proc0)
    
    # GPU 1 worker
    println("Starting GPU 1 worker...")
    env1 = copy(ENV)
    env1["CUDA_VISIBLE_DEVICES"] = "1"
    proc1 = run(addenv(`julia $WORKER_SCRIPT $gpu1_start $gpu1_end 1`, env1), wait=false)
    push!(worker_procs, proc1)
    
    println("\n⏳ Workers running... Monitoring progress...")
    
    # Monitor progress
    start_time = time()
    last_count = completed_count
    
    while true
        sleep(30)  # Check every 30 seconds
        
        # Count completed files
        current_count = 0
        for file in readdir(OUTPUT_DIR)
            if endswith(file, "_drugbank_extracted_indications.json")
                current_count += 1
            end
        end
        
        # Calculate progress
        new_completions = current_count - last_count
        elapsed = time() - start_time
        rate = new_completions / (elapsed / 60)  # drugs per minute
        
        remaining = total_drugs - current_count
        eta = remaining / rate  # minutes
        
        println("\n📊 Progress Update ($(Dates.format(now(), "HH:MM:SS"))):")
        println("  Completed: $current_count/$total_drugs ($(round(current_count/total_drugs*100, digits=1))%)")
        println("  New completions: $new_completions")
        println("  Rate: $(round(rate, digits=1)) drugs/min")
        println("  ETA: $(round(eta, digits=1)) minutes")
        
        last_count = current_count
        
        # Check if workers are still running
        all_done = true
        for (i, proc) in enumerate(worker_procs)
            if process_running(proc)
                all_done = false
            else
                println("  Worker $i has completed")
            end
        end
        
        if all_done
            println("\n✅ All workers have completed!")
            break
        end
    end
    
    # Final count
    final_count = 0
    for file in readdir(OUTPUT_DIR)
        if endswith(file, "_drugbank_extracted_indications.json")
            final_count += 1
        end
    end
    
    # Cleanup Ollama servers
    println("\n🧹 Shutting down Ollama servers...")
    for proc in ollama_procs
        try
            kill(proc, Base.SIGTERM)
        catch
            # Process may have already exited
        end
    end
    
    # Final summary
    total_time = time() - start_time
    println("\n=== COORDINATOR COMPLETE ===")
    println("✅ Total drugs processed: $final_count/$total_drugs")
    println("📈 New drugs processed in this run: $(final_count - completed_count)")
    println("⏱️  Total time: $(round(total_time / 60, digits=1)) minutes")
    println("📊 Overall rate: $(round((final_count - completed_count) / (total_time / 60), digits=1)) drugs/min")
    println("End time: $(now())")
end

# Run the coordinator
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end