#!/bin/bash
#SBATCH --job-name=batch_naive
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1
#SBATCH --partition=gpu
#SBATCH --output=logs/batch_naive_extraction_%j.out
#SBATCH --error=logs/batch_naive_extraction_%j.err

# Load required modules
module load ollama julia

# Print job information
echo "=== Batch Naive Extraction Job Started ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $HOSTNAME"
echo "Date: $(date)"
echo "Start Index: $1"
echo "Batch Size: $2"

# Set up Ollama
export OLLAMA_MODELS=/users/isarkar/ollama_models
export OLLAMA_HOST=http://127.0.0.1:11434

# Start Ollama server in background
echo "Starting Ollama server..."
ollama serve > /tmp/ollama_$SLURM_JOB_ID.log 2>&1 &
OLLAMA_PID=$!

# Wait for Ollama to start
echo "Waiting for Ollama to start..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        echo "Ollama server started successfully"
        break
    fi
    sleep 2
done

# Load the model ONCE
echo "Loading Llama 3.2 model..."
ollama run llama3.2 "test" > /dev/null 2>&1

# Run the batch extraction
echo "Running batch extraction..."
echo "Processing drugs $1 to $(($1 + $2 - 1))..."
julia /oscar/home/isarkar/sarkarcode/thera-ie/scripts/extraction/batch_naive_extractor.jl "$1" "$2"

# Cleanup
echo "Cleaning up..."
kill $OLLAMA_PID 2>/dev/null

echo "=== Batch Naive Extraction Job Completed ==="
echo "End time: $(date)"