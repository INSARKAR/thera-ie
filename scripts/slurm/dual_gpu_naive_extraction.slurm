#!/bin/bash
#SBATCH --job-name=dual_gpu_naive
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:2
#SBATCH --partition=gpu
#SBATCH --output=logs/dual_gpu_naive_extraction_%j.out
#SBATCH --error=logs/dual_gpu_naive_extraction_%j.err

# Load required modules
module load ollama julia

# Print job information
echo "=== Dual GPU Naive Extraction Job Started ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $HOSTNAME"
echo "Date: $(date)"
echo "Drug 1: $1"
echo "Drug 2: $2"

# Set up Ollama directories
export OLLAMA_MODELS=/users/isarkar/ollama_models

# Start Ollama servers on different ports for each GPU
echo "Starting Ollama servers..."

# GPU 0 - Port 11434
CUDA_VISIBLE_DEVICES=0 ollama serve --host 127.0.0.1:11434 > /tmp/ollama_gpu0_$SLURM_JOB_ID.log 2>&1 &
OLLAMA_PID1=$!

# GPU 1 - Port 11435  
CUDA_VISIBLE_DEVICES=1 ollama serve --host 127.0.0.1:11435 > /tmp/ollama_gpu1_$SLURM_JOB_ID.log 2>&1 &
OLLAMA_PID2=$!

# Wait for both Ollama servers to start
echo "Waiting for Ollama servers to start..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1 && \
       curl -s http://127.0.0.1:11435/api/tags > /dev/null 2>&1; then
        echo "Both Ollama servers started successfully"
        break
    fi
    sleep 2
done

# Load models on both GPUs
echo "Loading Llama 3.2 models..."
OLLAMA_HOST=http://127.0.0.1:11434 ollama run llama3.2 "test" > /dev/null 2>&1
OLLAMA_HOST=http://127.0.0.1:11435 ollama run llama3.2 "test" > /dev/null 2>&1

# Run the dual GPU coordinator
echo "Running dual GPU naive extraction..."
julia /oscar/home/isarkar/sarkarcode/thera/scripts/extraction/dual_gpu_naive_coordinator.jl "$1" "$2"

# Cleanup
echo "Cleaning up..."
kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null

echo "=== Dual GPU Naive Extraction Job Completed ==="
echo "End time: $(date)"