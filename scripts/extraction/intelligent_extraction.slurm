#!/bin/bash
#SBATCH --job-name=intelligent_drug_extraction
#SBATCH --account=default
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=/users/isarkar/sarkarcode/thera/logs/intelligent_extraction_%j.out
#SBATCH --error=/users/isarkar/sarkarcode/thera/logs/intelligent_extraction_%j.err

# Drug name can be passed as a command line argument
DRUG_NAME="${1:-Levothyroxine}"  # Default to Levothyroxine if no argument provided

echo "=== Intelligent Drug Indication Extraction Job Started ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start time: $(date)"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo "Drug: $DRUG_NAME"

# Change to working directory
cd /users/isarkar/sarkarcode/thera

# Ensure logs directory exists
mkdir -p /users/isarkar/sarkarcode/thera/logs

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

# Load the model
echo "Loading Llama 3.2 model..."
ollama pull llama3.2
if [ $? -ne 0 ]; then
    echo "❌ Failed to load Llama 3.2 model"
    kill $OLLAMA_PID 2>/dev/null
    exit 1
fi

echo "✓ Model loaded successfully"

# Install required Julia packages
echo "Installing required Julia packages..."
julia -e 'using Pkg; Pkg.add(["ArgParse", "HTTP", "JSON3", "Dates"])'

# Run the intelligent extraction script
echo "Starting intelligent drug extraction for $DRUG_NAME..."
echo "Running: julia scripts/extraction/intelligent_drug_extractor.jl \"$DRUG_NAME\""
julia scripts/extraction/intelligent_drug_extractor.jl "$DRUG_NAME"

# Capture exit code
EXTRACTION_EXIT_CODE=$?

# Clean up
echo "Cleaning up..."
kill $OLLAMA_PID 2>/dev/null
wait $OLLAMA_PID 2>/dev/null

# Final status
echo "=== Job Complete ==="
echo "End time: $(date)"
echo "Exit code: $EXTRACTION_EXIT_CODE"

if [ $EXTRACTION_EXIT_CODE -eq 0 ]; then
    echo "✅ Intelligent extraction completed successfully!"
    echo "📁 Check results in: /users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/"
else
    echo "❌ Intelligent extraction failed with exit code: $EXTRACTION_EXIT_CODE"
fi
