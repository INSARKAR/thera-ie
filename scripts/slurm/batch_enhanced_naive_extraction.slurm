#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=4:00:00
#SBATCH --job-name=batch_enhanced_naive
#SBATCH --output=logs/batch_enhanced_naive_%j.out
#SBATCH --error=logs/batch_enhanced_naive_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G

# Default values
START_INDEX=${1:-1}
BATCH_SIZE=${2:-200}

echo "=== Batch Enhanced Naive Extraction ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start Index: $START_INDEX"
echo "Batch Size: $BATCH_SIZE"
echo "Start Time: $(date)"

# Load modules
module load ollama julia

# Set Ollama models directory to avoid permission issues
export OLLAMA_MODELS="/tmp/ollama_models_$SLURM_JOB_ID"
mkdir -p $OLLAMA_MODELS

# Start Ollama server
echo "Starting Ollama server..."
ollama serve > logs/ollama_batch_$SLURM_JOB_ID.log 2>&1 &
OLLAMA_PID=$!

# Wait for server to start
echo "Waiting for Ollama server to start..."
sleep 15

# Test server connectivity
echo "Testing Ollama server connectivity..."
curl -s http://localhost:11434/api/tags > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Ollama server is running"
else
    echo "❌ Ollama server failed to start"
    exit 1
fi

# Load model
echo "Loading llama3.2 model..."
ollama pull llama3.2

# Run batch extraction
echo "Starting batch enhanced naive extraction..."
julia scripts/extraction/batch_enhanced_naive_extractor.jl $START_INDEX $BATCH_SIZE

# Clean up
echo "Cleaning up..."
kill $OLLAMA_PID 2>/dev/null || true
rm -rf $OLLAMA_MODELS 2>/dev/null || true

echo "Batch extraction completed at $(date)"