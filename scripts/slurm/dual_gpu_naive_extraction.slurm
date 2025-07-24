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
mkdir -p $OLLAMA_MODELS

# Start Ollama servers on different ports for each GPU
echo "Starting Ollama servers..."

# GPU 0 - Port 11434
CUDA_VISIBLE_DEVICES=0 OLLAMA_HOST=http://127.0.0.1:11434 ollama serve &
OLLAMA_PID1=$!
echo "Ollama server 1 started with PID: $OLLAMA_PID1"

# GPU 1 - Port 11435  
CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST=http://127.0.0.1:11435 ollama serve &
OLLAMA_PID2=$!
echo "Ollama server 2 started with PID: $OLLAMA_PID2"

# Wait for both Ollama servers to start
echo "Waiting for Ollama servers to start..."

# Wait for server 1
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        echo "✓ Ollama server 1 (GPU 0) is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Ollama server 1 failed to start within 30 seconds"
        kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
        exit 1
    fi
    sleep 1
done

# Wait for server 2
for i in {1..30}; do
    if curl -s http://127.0.0.1:11435/api/tags > /dev/null 2>&1; then
        echo "✓ Ollama server 2 (GPU 1) is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Ollama server 2 failed to start within 30 seconds"
        kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
        exit 1
    fi
    sleep 1
done

# Check and load models on both GPUs
echo "Loading Llama 3.2 models..."

# Check server 1
if OLLAMA_HOST=http://127.0.0.1:11434 ollama list | grep -q "llama3.2"; then
    echo "✓ Llama 3.2 model is available on server 1"
else
    echo "Llama 3.2 model not found on server 1, pulling..."
    OLLAMA_HOST=http://127.0.0.1:11434 ollama pull llama3.2
    if [ $? -eq 0 ]; then
        echo "✓ Llama 3.2 model pulled successfully on server 1"
    else
        echo "❌ Failed to pull Llama 3.2 model on server 1"
        kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
        exit 1
    fi
fi

# Check server 2
if OLLAMA_HOST=http://127.0.0.1:11435 ollama list | grep -q "llama3.2"; then
    echo "✓ Llama 3.2 model is available on server 2"
else
    echo "Llama 3.2 model not found on server 2, pulling..."
    OLLAMA_HOST=http://127.0.0.1:11435 ollama pull llama3.2
    if [ $? -eq 0 ]; then
        echo "✓ Llama 3.2 model pulled successfully on server 2"
    else
        echo "❌ Failed to pull Llama 3.2 model on server 2"
        kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
        exit 1
    fi
fi

# Test both Ollama servers
echo "Testing Ollama servers..."

# Test server 1
TEST_RESPONSE1=$(curl -s -X POST http://127.0.0.1:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model": "llama3.2", "prompt": "Say TEST GPU1", "stream": false, "options": {"max_tokens": 10}}' \
    --connect-timeout 10 --max-time 30)

if [ $? -eq 0 ] && [ ! -z "$TEST_RESPONSE1" ]; then
    echo "✓ Ollama server 1 test successful"
else
    echo "❌ Ollama server 1 test failed"
    kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
    exit 1
fi

# Test server 2
TEST_RESPONSE2=$(curl -s -X POST http://127.0.0.1:11435/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model": "llama3.2", "prompt": "Say TEST GPU2", "stream": false, "options": {"max_tokens": 10}}' \
    --connect-timeout 10 --max-time 30)

if [ $? -eq 0 ] && [ ! -z "$TEST_RESPONSE2" ]; then
    echo "✓ Ollama server 2 test successful"
else
    echo "❌ Ollama server 2 test failed"
    kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
    exit 1
fi

# Run the dual GPU coordinator
echo "Running dual GPU naive extraction..."
julia /oscar/home/isarkar/sarkarcode/thera-ie/scripts/extraction/dual_gpu_naive_coordinator.jl "$1" "$2"

# Cleanup
echo "Cleaning up..."
kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null

echo "=== Dual GPU Naive Extraction Job Completed ==="
echo "End time: $(date)"