#!/bin/bash
#SBATCH --job-name=naive_gpu_batch
#SBATCH --partition=gpu
#SBATCH --time=6:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --mem=16G
#SBATCH --output=logs/naive_gpu_batch_%j.out
#SBATCH --error=logs/naive_gpu_batch_%j.err

# Parameters: START_INDEX BATCH_SIZE
START_INDEX=${1:-1}
BATCH_SIZE=${2:-50}

# Load modules
module load julia
module load ollama

echo "🚀 Single GPU Naive Extraction Batch"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo "Start Index: $START_INDEX"
echo "Batch Size: $BATCH_SIZE"
echo "Start time: $(date)"

# Navigate to project directory
cd /oscar/home/isarkar/sarkarcode/thera-ie

# Start Ollama server on single GPU
echo "🔥 Starting Ollama server..."
ollama serve > ollama_${SLURM_JOB_ID}.log 2>&1 &
OLLAMA_PID=$!
echo "  Ollama PID: $OLLAMA_PID"

# Wait for server to start
sleep 15

# Check if model is already available, if not pull it
echo "📥 Ensuring Llama 3.2 model is available..."
if ! ollama list | grep -q llama3.2; then
    echo "  Pulling Llama 3.2 model..."
    ollama pull llama3.2
else
    echo "  ✅ Llama 3.2 model already available"
fi

# Run enhanced naive extraction for this batch
echo "🧠 Starting enhanced naive extraction..."
echo "  Processing drugs $START_INDEX to $((START_INDEX + BATCH_SIZE - 1))"

julia -t 4 scripts/extraction/batch_enhanced_naive_extractor.jl $START_INDEX $BATCH_SIZE

EXTRACTION_EXIT_CODE=$?

echo "✅ Batch extraction completed with exit code: $EXTRACTION_EXIT_CODE"
echo "Completion time: $(date)"

# Show extraction results
EXISTING_NAIVE=$(ls llama_naive_extracted_indications/ | wc -l)
echo "📊 Total naive extractions now: $EXISTING_NAIVE"

# Cleanup
echo "🧹 Cleaning up Ollama server..."
kill $OLLAMA_PID 2>/dev/null || true

echo "✅ Job completed at $(date)"
exit $EXTRACTION_EXIT_CODE