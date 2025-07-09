#!/usr/bin/env julia

"""
Final corrected script to create dual GPU jobs for empty drugs
Fixed to use OLLAMA_HOST environment variable instead of --host flag
"""

using JSON3

function get_drugs_needing_processing()
    """Get drugs that need processing (no files exist)"""
    
    # Load approved drugs
    approved_drugs_file = "/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.json"
    data = JSON3.read(read(approved_drugs_file, String))
    all_drugs = sort(collect(keys(data.drugs)))
    
    # Filter unprocessed
    llama_dir = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications"
    unprocessed = String[]
    
    for drug in all_drugs
        output_file = joinpath(llama_dir, "$(drug)_naive_extracted_indications.json")
        if !isfile(output_file)
            push!(unprocessed, String(drug))
        end
    end
    
    return unprocessed
end

function create_corrected_dual_gpu_slurm_script(drugs_batch1::Vector{String}, drugs_batch2::Vector{String}, job_id::Int)
    """Create corrected SLURM script using OLLAMA_HOST environment variable"""
    
    slurm_content = """#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2
#SBATCH --time=4:00:00
#SBATCH --job-name=corrected_dual_gpu_$job_id
#SBATCH --output=corrected_dual_gpu_$(job_id)_%j.out
#SBATCH --error=corrected_dual_gpu_$(job_id)_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=20G

echo "Starting CORRECTED dual GPU job for naive LLM processing..."
echo "Job ID: \$SLURM_JOB_ID"
echo "Node: \$(hostname)"
echo "GPUs: \$CUDA_VISIBLE_DEVICES"

# Load modules
module load ollama julia

# Function to setup and start Ollama server on specific GPU
setup_ollama_server() {
    local gpu_id=\$1
    local port=\$2
    local log_file=\$3
    
    echo "Setting up Ollama server on GPU \$gpu_id, port \$port..."
    
    # Set environment for this GPU
    export CUDA_VISIBLE_DEVICES=\$gpu_id
    export OLLAMA_HOST="0.0.0.0:\$port"
    
    # Kill any existing ollama processes
    pkill -f "ollama.*:\$port" 2>/dev/null || true
    sleep 3
    
    # Start server in background
    ollama serve > \$log_file 2>&1 &
    local server_pid=\$!
    
    # Wait for server to initialize
    echo "Waiting for Ollama server on port \$port to start..."
    for i in {1..30}; do
        if curl -s http://localhost:\$port/api/tags >/dev/null 2>&1; then
            echo "✓ Ollama server on port \$port is ready"
            break
        fi
        echo "  Attempt \$i/30 - waiting..."
        sleep 5
    done
    
    # Final test
    if ! curl -s http://localhost:\$port/api/tags >/dev/null 2>&1; then
        echo "❌ Ollama server on port \$port failed to start"
        kill \$server_pid 2>/dev/null || true
        return 1
    fi
    
    # Load model
    echo "Loading llama3.2 model on port \$port..."
    OLLAMA_HOST="http://localhost:\$port" ollama pull llama3.2
    
    echo "✓ Ollama setup complete on GPU \$gpu_id, port \$port, PID \$server_pid"
    echo \$server_pid
}

# Start first Ollama server
echo "Starting first Ollama server..."
OLLAMA_PID_1=\$(setup_ollama_server 0 11434 ollama_gpu0.log)
if [ -z "\$OLLAMA_PID_1" ]; then
    echo "❌ Failed to start first Ollama server"
    exit 1
fi

# Start second Ollama server
echo "Starting second Ollama server..."
OLLAMA_PID_2=\$(setup_ollama_server 1 11435 ollama_gpu1.log)
if [ -z "\$OLLAMA_PID_2" ]; then
    echo "❌ Failed to start second Ollama server"
    kill \$OLLAMA_PID_1 2>/dev/null || true
    exit 1
fi

echo "Both Ollama servers started successfully!"
echo "GPU 0 Server PID: \$OLLAMA_PID_1"
echo "GPU 1 Server PID: \$OLLAMA_PID_2"

# Function to process drugs on a specific GPU
process_drugs_on_gpu() {
    local gpu_id=\$1
    local port=\$2
    shift 2
    local drugs=("\$@")
    
    echo "Starting processing on GPU \$gpu_id with \${#drugs[@]} drugs..."
    export CUDA_VISIBLE_DEVICES=\$gpu_id
    export OLLAMA_HOST="http://localhost:\$port"
    
    local success=0
    local failed=0
    
    for drug in "\${drugs[@]}"; do
        echo "Processing \$drug on GPU \$gpu_id..."
        
        # Process the drug
        if julia scripts/extraction/naive_llama_extractor.jl "\$drug"; then
            echo "  ✅ Successfully processed \$drug"
            ((success++))
        else
            echo "  ❌ Failed to process \$drug"
            ((failed++))
        fi
        
        # Small delay
        sleep 2
    done
    
    echo "GPU \$gpu_id completed: \$success successful, \$failed failed"
    if [ \$failed -gt 0 ]; then
        exit 1
    fi
}

# Start processing on both GPUs in parallel
(
"""

    # Add drugs for GPU 0
    slurm_content *= "    process_drugs_on_gpu 0 11434"
    for drug in drugs_batch1
        slurm_content *= " \"$drug\""
    end
    slurm_content *= "\n) &\nBATCH1_PID=\$!\n\n"
    
    slurm_content *= "(\n"
    # Add drugs for GPU 1
    slurm_content *= "    process_drugs_on_gpu 1 11435"
    for drug in drugs_batch2
        slurm_content *= " \"$drug\""
    end
    slurm_content *= "\n) &\nBATCH2_PID=\$!\n\n"
    
    slurm_content *= """# Wait for both batches to complete
echo "Waiting for both batches to complete..."
wait \$BATCH1_PID
batch1_exit=\$?
echo "Batch 1 completed with exit code \$batch1_exit"

wait \$BATCH2_PID
batch2_exit=\$?
echo "Batch 2 completed with exit code \$batch2_exit"

# Clean up Ollama servers
echo "Cleaning up Ollama servers..."
kill \$OLLAMA_PID_1 2>/dev/null || true
kill \$OLLAMA_PID_2 2>/dev/null || true

sleep 5

echo "Corrected dual GPU job completed!"
echo "Final exit codes: Batch1=\$batch1_exit, Batch2=\$batch2_exit"

# Exit with error if either batch failed
if [ \$batch1_exit -ne 0 ] || [ \$batch2_exit -ne 0 ]; then
    exit 1
fi
"""

    return slurm_content
end

function main()
    """Main function to create corrected rerun jobs"""
    
    println("=== Final Corrected Dual GPU Rerun Script ===")
    
    # Get drugs that need processing
    unprocessed_drugs = get_drugs_needing_processing()
    
    println("📊 Found $(length(unprocessed_drugs)) drugs that need processing")
    
    if isempty(unprocessed_drugs)
        println("✅ No drugs need processing!")
        return
    end
    
    # Show first few drugs
    println("📋 First 10 drugs to process:")
    for (i, drug) in enumerate(unprocessed_drugs[1:min(10, length(unprocessed_drugs))])
        println("   $i. $drug")
    end
    if length(unprocessed_drugs) > 10
        println("   ... and $(length(unprocessed_drugs) - 10) more")
    end
    
    # Create smaller batches for reliability
    drugs_per_gpu_per_job = 10  # Smaller batches
    total_drugs_per_job = drugs_per_gpu_per_job * 2
    
    num_jobs = ceil(Int, length(unprocessed_drugs) / total_drugs_per_job)
    
    println("\\n📦 Creating $num_jobs corrected dual GPU jobs...")
    println("   • Drugs per GPU per job: $drugs_per_gpu_per_job")
    println("   • Total drugs per job: $total_drugs_per_job")
    
    # Create SLURM scripts
    for job_id in 1:num_jobs
        start_idx = (job_id - 1) * total_drugs_per_job + 1
        end_idx = min(job_id * total_drugs_per_job, length(unprocessed_drugs))
        
        job_drugs = unprocessed_drugs[start_idx:end_idx]
        
        # Split into two batches for dual GPU
        mid_point = ceil(Int, length(job_drugs) / 2)
        batch1 = job_drugs[1:mid_point]
        batch2 = length(job_drugs) > mid_point ? job_drugs[mid_point+1:end] : String[]
        
        # Create SLURM script
        slurm_content = create_corrected_dual_gpu_slurm_script(batch1, batch2, job_id)
        slurm_file = "corrected_dual_gpu_$job_id.slurm"
        
        open(slurm_file, "w") do file
            write(file, slurm_content)
        end
        
        println("✓ Created $slurm_file ($(length(batch1)) + $(length(batch2)) drugs)")
    end
    
    # Create submission script
    submit_script = """#!/bin/bash

echo "Submitting $num_jobs corrected dual GPU jobs..."

"""
    
    for job_id in 1:num_jobs
        submit_script *= "echo \"Submitting corrected job $job_id...\"\n"
        submit_script *= "sbatch corrected_dual_gpu_$job_id.slurm\n"
        submit_script *= "sleep 2\n\n"
    end
    
    submit_script *= """echo "All corrected jobs submitted!"
echo "Monitor with: squeue -u \$USER"
echo "Check logs: tail -f corrected_dual_gpu_*_*.out"
"""
    
    open("submit_corrected_jobs.sh", "w") do file
        write(file, submit_script)
    end
    
    run(`chmod +x submit_corrected_jobs.sh`)
    
    println("\\n🚀 Created corrected submission script: submit_corrected_jobs.sh")
    println("\\n📝 Summary:")
    println("   • Total drugs to process: $(length(unprocessed_drugs))")
    println("   • Number of corrected dual GPU jobs: $num_jobs")
    println("   • Jobs created: corrected_dual_gpu_1.slurm to corrected_dual_gpu_$num_jobs.slurm")
    println("\\n🎯 To submit all corrected jobs: ./submit_corrected_jobs.sh")
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end