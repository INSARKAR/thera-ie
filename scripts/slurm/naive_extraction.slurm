#!/bin/bash
#SBATCH --job-name=naive_extrac
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1
#SBATCH --partition=gpu
#SBATCH --output=logs/naive_extraction_%j.out
#SBATCH --error=logs/naive_extraction_%j.err

# Load required modules
module load ollama julia

# Print job information
echo "=== Naive Extraction Job Started ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $HOSTNAME"
echo "Date: $(date)"
echo "Drug: $1"

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

# Load the model
echo "Loading Llama 3.2 model..."
ollama run llama3.2 "test" > /dev/null 2>&1

# Run the naive extraction
echo "Running naive extraction for $1..."
julia /oscar/home/isarkar/sarkarcode/thera/scripts/extraction/naive_llama_extractor.jl "$1"

# Cleanup
echo "Cleaning up..."
kill $OLLAMA_PID 2>/dev/null

echo "=== Naive Extraction Job Completed ==="
echo "End time: $(date)"