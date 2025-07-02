#!/bin/bash
#SBATCH --job-name=optimized_levothyroxine
#SBATCH --account=default
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=/users/isarkar/sarkarcode/thera/logs/optimized_extraction_%j.out
#SBATCH --error=/users/isarkar/sarkarcode/thera/logs/optimized_extraction_%j.err

echo "=== OPTIMIZED Levothyroxine Extraction Job Started ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start time: $(date)"
echo "GPU: $CUDA_VISIBLE_DEVICES"

# Change to working directory
cd /users/isarkar/sarkarcode/thera

# Load required modules
echo "Loading modules..."
module load ollama
module load julia

# Set environment variables for Ollama
export OLLAMA_MODELS=$HOME/.ollama/models
export OLLAMA_HOST=http://127.0.0.1:11434

# Create models directory if it doesn't exist
mkdir -p $OLLAMA_MODELS

# Start Ollama server in background
echo "Starting Ollama server..."
ollama serve &
OLLAMA_PID=$!

# Wait for server to start
echo "Waiting for Ollama server to start..."
sleep 10

# Check if server is responding
echo "Testing Ollama server connection..."
max_attempts=10
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "✓ Ollama server is responding"
        break
    else
        echo "Waiting for Ollama server... (attempt $((attempt+1))/$max_attempts)"
        sleep 5
        attempt=$((attempt+1))
    fi
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Failed to connect to Ollama server after $max_attempts attempts"
    kill $OLLAMA_PID 2>/dev/null
    exit 1
fi

# Load the model (if not already loaded)
echo "Ensuring Llama 3.2 model is loaded..."
ollama pull llama3.2
if [ $? -ne 0 ]; then
    echo "❌ Failed to load Llama 3.2 model"
    kill $OLLAMA_PID 2>/dev/null
    exit 1
fi

echo "✓ Model loaded successfully"

# Run the optimized extraction script
echo "Starting OPTIMIZED Levothyroxine extraction..."
echo "Optimizations:"
echo "  - Reduced API delay: 0.05s (vs 0.5s)"
echo "  - Shorter prompts and faster parsing"
echo "  - Reduced timeouts and retry logic"
echo "  - Periodic checkpoints every 500 publications"
echo "  - Less verbose logging"
echo ""
echo "Running: julia optimized_levothyroxine_extractor.jl"

julia optimized_levothyroxine_extractor.jl

# Capture exit code
EXTRACTION_EXIT_CODE=$?

# Clean up
echo "Cleaning up..."
kill $OLLAMA_PID 2>/dev/null
wait $OLLAMA_PID 2>/dev/null

# Final status
echo "=== Optimized Job Complete ==="
echo "End time: $(date)"
echo "Exit code: $EXTRACTION_EXIT_CODE"

if [ $EXTRACTION_EXIT_CODE -eq 0 ]; then
    echo "✅ Optimized extraction completed successfully!"
    echo "📁 Check results in: /users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/"
    echo "📊 Look for checkpoints and final results"
else
    echo "❌ Optimized extraction failed with exit code: $EXTRACTION_EXIT_CODE"
fi

exit $EXTRACTION_EXIT_CODE
