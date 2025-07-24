#!/bin/bash
#SBATCH --job-name=phase2_naive_llama
#SBATCH --output=logs/phase2_step3_naive_llama_%A_%a.out
#SBATCH --error=logs/phase2_step3_naive_llama_%A_%a.err
#SBATCH --array=1-30
#SBATCH --time=02:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --nodes=1

# Phase 2 Step 3: Naive Llama Drug Indication Extraction
# Processes approved drugs using Llama 3.2 knowledge-based extraction

echo "=== Phase 2 Step 3: Naive Llama Extraction ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Node: $(hostname)"
echo "Start time: $(date)"

# Load required modules
module load ollama
module load julia/1.11.1s-kueea5s

# Set Ollama configuration
export OLLAMA_HOST="http://127.0.0.1:11434"
export OLLAMA_MODELS="/oscar/home/isarkar/.ollama/models"

# Batch configuration
TOTAL_REMAINING_DRUGS=2915  # Will be filtered by already processed drugs
BATCH_SIZE=100
START_INDEX=$(( ($SLURM_ARRAY_TASK_ID - 1) * $BATCH_SIZE + 1 ))

echo "Batch configuration:"
echo "  - Total remaining drugs (max): $TOTAL_REMAINING_DRUGS"
echo "  - Batch size: $BATCH_SIZE"
echo "  - Start index: $START_INDEX"

# Create logs directory
mkdir -p logs

# Start Ollama server in background
echo "🚀 Starting Ollama server..."
ollama serve &
OLLAMA_PID=$!
echo "Ollama PID: $OLLAMA_PID"

# Wait for Ollama to start
sleep 10

# Check if Ollama is running
if ! curl -s http://127.0.0.1:11434/api/tags > /dev/null; then
    echo "❌ Ollama server failed to start"
    kill $OLLAMA_PID 2>/dev/null || true
    exit 1
fi

# Load Llama model if not already loaded
echo "🤖 Loading Llama 3.2 model..."
ollama run llama3.2 "Hello" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Llama 3.2 model loaded successfully"
else
    echo "❌ Failed to load Llama 3.2 model"
    kill $OLLAMA_PID 2>/dev/null || true
    exit 1
fi

# Run the naive extraction script
echo "🎯 Starting Phase 2 Step 3 naive extraction..."
julia --project=. scripts/extraction/phase2_step3_naive_llama_extractor.jl $START_INDEX $BATCH_SIZE

# Check execution status
if [ $? -eq 0 ]; then
    echo "✅ Phase 2 Step 3 batch processing completed successfully"
    EXIT_STATUS=0
else
    echo "❌ Phase 2 Step 3 batch processing failed"
    EXIT_STATUS=1
fi

# Clean up Ollama server
echo "🧹 Cleaning up Ollama server..."
kill $OLLAMA_PID 2>/dev/null || true
sleep 5

# Force kill if still running
if ps -p $OLLAMA_PID > /dev/null 2>&1; then
    echo "Force killing Ollama server..."
    kill -9 $OLLAMA_PID 2>/dev/null || true
fi

echo "End time: $(date)"
echo "=== Phase 2 Step 3 Complete ==="

exit $EXIT_STATUS