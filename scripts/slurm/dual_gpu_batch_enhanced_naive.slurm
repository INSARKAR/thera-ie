#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2
#SBATCH --time=4:00:00
#SBATCH --job-name=dual_gpu_batch_enhanced
#SBATCH --output=logs/dual_gpu_batch_enhanced_%j.out
#SBATCH --error=logs/dual_gpu_batch_enhanced_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G

# Default values
START_INDEX=${1:-1}
TOTAL_BATCH_SIZE=${2:-400}

echo "=== Dual GPU Batch Enhanced Naive Extraction ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start Index: $START_INDEX"
echo "Total Batch Size: $TOTAL_BATCH_SIZE"
echo "GPUs per batch: 2 ($(($TOTAL_BATCH_SIZE / 2)) drugs per GPU)"
echo "Start Time: $(date)"

# Load modules
module load ollama julia

# Start Ollama servers on both GPUs
echo "Starting Ollama servers on both GPUs..."

# GPU 0 - Port 11434
export CUDA_VISIBLE_DEVICES=0
OLLAMA_HOST=127.0.0.1:11434 ollama serve > logs/ollama_gpu0_$SLURM_JOB_ID.log 2>&1 &
OLLAMA_PID_0=$!

# GPU 1 - Port 11435  
export CUDA_VISIBLE_DEVICES=1
OLLAMA_HOST=127.0.0.1:11435 ollama serve > logs/ollama_gpu1_$SLURM_JOB_ID.log 2>&1 &
OLLAMA_PID_1=$!

# Reset CUDA_VISIBLE_DEVICES to see both GPUs
export CUDA_VISIBLE_DEVICES=0,1

# Wait for both servers to start
echo "Waiting for both Ollama servers to start..."
sleep 20

# Test server connectivity
echo "Testing Ollama server connectivity..."
GPU0_STATUS=$(curl -s http://localhost:11434/api/tags > /dev/null && echo "OK" || echo "FAIL")
GPU1_STATUS=$(curl -s http://localhost:11435/api/tags > /dev/null && echo "OK" || echo "FAIL")

echo "GPU0 (port 11434): $GPU0_STATUS"
echo "GPU1 (port 11435): $GPU1_STATUS"

if [ "$GPU0_STATUS" != "OK" ] || [ "$GPU1_STATUS" != "OK" ]; then
    echo "❌ One or both Ollama servers failed to start"
    exit 1
fi

# Load model on both GPUs
echo "Loading llama3.2 model on both GPUs..."
OLLAMA_HOST=127.0.0.1:11434 ollama pull llama3.2 &
OLLAMA_HOST=127.0.0.1:11435 ollama pull llama3.2 &
wait

echo "✅ Both Ollama servers are running with llama3.2 loaded"

# Run dual GPU batch extraction
echo "Starting dual GPU batch enhanced naive extraction..."
julia scripts/extraction/dual_gpu_batch_enhanced_naive.jl $START_INDEX $TOTAL_BATCH_SIZE

# Clean up
echo "Cleaning up..."
kill $OLLAMA_PID_0 2>/dev/null || true
kill $OLLAMA_PID_1 2>/dev/null || true

echo "Dual GPU batch extraction completed at $(date)"