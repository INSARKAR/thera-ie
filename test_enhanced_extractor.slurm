#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=0:30:00
#SBATCH --job-name=test_enhanced_extractor
#SBATCH --output=test_enhanced_extractor_%j.out
#SBATCH --error=test_enhanced_extractor_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G

echo "Testing Enhanced Naive Extractor with Levothyroxine"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"

# Load modules
module load ollama julia

# Start Ollama server
echo "Starting Ollama server..."
ollama serve > ollama_test.log 2>&1 &
OLLAMA_PID=$!

# Wait for server to start
echo "Waiting for Ollama server to start..."
sleep 15

# Test server
echo "Testing Ollama server..."
curl -s http://localhost:11434/api/tags || echo "Server not responding"

# Load model
echo "Loading llama3.2 model..."
ollama pull llama3.2

# Test enhanced extractor with Levothyroxine
echo "Testing enhanced extractor with Levothyroxine..."
julia scripts/extraction/enhanced_naive_llama_extractor.jl Levothyroxine

# Clean up
echo "Cleaning up..."
kill $OLLAMA_PID 2>/dev/null || true

echo "Test completed."