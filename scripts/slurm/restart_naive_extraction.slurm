#!/bin/bash
#SBATCH --job-name=restart_naive_extraction
#SBATCH --partition=gpu
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:2
#SBATCH --mem=32G
#SBATCH --output=logs/restart_naive_extraction_%j.out
#SBATCH --error=logs/restart_naive_extraction_%j.err

# Load modules
module load julia
module load ollama

echo "🔄 Restarting Enhanced Naive Extraction"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "GPUs: $CUDA_VISIBLE_DEVICES"
echo "Start time: $(date)"

# Navigate to project directory
cd /oscar/home/isarkar/sarkarcode/thera

# Check current status
echo "📊 Current extraction status:"
TOTAL_DRUGS=$(julia -e "include(\"approved_drugs_dict.jl\"); println(length(APPROVED_DRUGS_DICT))")
EXISTING_NAIVE=$(ls llama_naive_extracted_indications/ | wc -l)
MISSING=$((TOTAL_DRUGS - EXISTING_NAIVE))

echo "  Total drugs: $TOTAL_DRUGS"
echo "  Existing naive extractions: $EXISTING_NAIVE"
echo "  Missing extractions: $MISSING"

if [ $MISSING -eq 0 ]; then
    echo "✅ All drugs already processed!"
    exit 0
fi

# Start Ollama servers on both GPUs
echo "🚀 Starting Ollama servers..."
CUDA_VISIBLE_DEVICES=0 ollama serve > ollama_gpu0.log 2>&1 &
OLLAMA_PID_0=$!
echo "  GPU 0 Ollama PID: $OLLAMA_PID_0"

CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST=127.0.0.1:11435 ollama serve > ollama_gpu1.log 2>&1 &
OLLAMA_PID_1=$!
echo "  GPU 1 Ollama PID: $OLLAMA_PID_1"

# Wait for servers to start
sleep 30

# Load models on both GPUs
echo "📥 Loading Llama 3.2 models..."
OLLAMA_HOST=127.0.0.1:11434 ollama pull llama3.2 &
OLLAMA_HOST=127.0.0.1:11435 ollama pull llama3.2 &
wait

echo "✅ Models loaded on both GPUs"

# Calculate optimal batch processing
BATCH_SIZE=400  # Process 400 drugs per job (200 per GPU)
TOTAL_BATCHES=$(( (MISSING + BATCH_SIZE - 1) / BATCH_SIZE ))

echo "📦 Processing in batches of $BATCH_SIZE drugs"
echo "  Total batches needed: $TOTAL_BATCHES"

# Find the starting index (first missing drug)
START_INDEX=$(julia -e "
    include(\"approved_drugs_dict.jl\")
    existing_files = Set(replace.(readdir(\"llama_naive_extracted_indications\"), \"_enhanced_naive_extracted_indications.json\" => \"\"))
    drug_names = collect(keys(APPROVED_DRUGS_DICT))
    for (i, drug) in enumerate(drug_names)
        if !(replace(drug, \" \" => \"_\") in existing_files)
            println(i)
            break
        end
    end
")

echo "  Starting from drug index: $START_INDEX"

# Run dual GPU batch enhanced naive extraction
echo "🧠 Starting enhanced naive extraction..."
julia -t 8 scripts/extraction/dual_gpu_batch_enhanced_naive.jl $START_INDEX $BATCH_SIZE

echo "✅ Batch completed at $(date)"

# Check final status
FINAL_EXISTING=$(ls llama_naive_extracted_indications/ | wc -l)
FINAL_MISSING=$((TOTAL_DRUGS - FINAL_EXISTING))

echo "📊 Final status:"
echo "  Naive extractions: $FINAL_EXISTING"
echo "  Still missing: $FINAL_MISSING"

# Cleanup
echo "🧹 Cleaning up Ollama servers..."
kill $OLLAMA_PID_0 $OLLAMA_PID_1 2>/dev/null || true

if [ $FINAL_MISSING -gt 0 ]; then
    echo "⚠️  $FINAL_MISSING drugs still need processing"
    echo "   Submit additional jobs to complete extraction"
else
    echo "🎉 All naive extractions complete!"
fi

echo "✅ Job completed at $(date)"