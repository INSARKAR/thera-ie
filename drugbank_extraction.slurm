#!/bin/bash
#SBATCH --job-name=drugbank_llama_extract
#SBATCH --account=default
#SBATCH --partition=gpu
#SBATCH --qos=norm-gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=2:00:00
#SBATCH --output=logs/drugbank_extraction_%j.out
#SBATCH --error=logs/drugbank_extraction_%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=isarkar@brown.edu

# Create logs directory if it doesn't exist
mkdir -p logs

echo "=== SLURM Job Information ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Start time: $(date)"
echo "Working directory: $(pwd)"
echo ""

# Set environment variables
export DRUGBANK_SINGLE_DRUG="${DRUGBANK_SINGLE_DRUG:-}"

echo "=== Configuration ==="
if [ -n "$DRUGBANK_SINGLE_DRUG" ]; then
    echo "Processing single drug: $DRUGBANK_SINGLE_DRUG"
else
    echo "Processing all drugs in approved_drugs_dict.json"
fi
echo ""

# Load required modules
echo "=== Loading Modules ==="
module load julia
module load ollama
echo "✓ Modules loaded"
echo ""

# Check GPU availability
echo "=== GPU Information ==="
nvidia-smi
echo ""

# Start Ollama server
echo "=== Starting Ollama Server ==="
ollama serve &
OLLAMA_PID=$!
echo "Ollama server started with PID: $OLLAMA_PID"

# Wait for Ollama server to be ready
echo "Waiting for Ollama server to start..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✓ Ollama server is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Ollama server failed to start within 30 seconds"
        kill $OLLAMA_PID 2>/dev/null
        exit 1
    fi
    sleep 1
done
echo ""

# Check if Llama 3.2 model is available, pull if needed
echo "=== Checking Llama 3.2 Model ==="
if ollama list | grep -q "llama3.2"; then
    echo "✓ Llama 3.2 model is available"
else
    echo "Llama 3.2 model not found, pulling..."
    ollama pull llama3.2
    if [ $? -eq 0 ]; then
        echo "✓ Llama 3.2 model pulled successfully"
    else
        echo "❌ Failed to pull Llama 3.2 model"
        kill $OLLAMA_PID 2>/dev/null
        exit 1
    fi
fi
echo ""

# Test Ollama with a simple query
echo "=== Testing Ollama ==="
TEST_RESPONSE=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model": "llama3.2", "prompt": "Say TEST", "stream": false, "options": {"max_tokens": 10}}' \
    --connect-timeout 10 --max-time 30)

if [ $? -eq 0 ] && [ ! -z "$TEST_RESPONSE" ]; then
    echo "✓ Ollama test successful"
    echo "Test response: $(echo $TEST_RESPONSE | jq -r '.response' 2>/dev/null || echo $TEST_RESPONSE | head -c 50)..."
else
    echo "❌ Ollama test failed"
    kill $OLLAMA_PID 2>/dev/null
    exit 1
fi
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "=== Cleanup ==="
    if [ ! -z "$OLLAMA_PID" ]; then
        echo "Stopping Ollama server (PID: $OLLAMA_PID)..."
        kill $OLLAMA_PID 2>/dev/null
        wait $OLLAMA_PID 2>/dev/null
        echo "✓ Ollama server stopped"
    fi
    echo "Job completed at: $(date)"
}

# Set trap for cleanup
trap cleanup EXIT

# Change to the working directory
cd /users/isarkar/sarkarcode/thera

# Check if the project setup is correct
echo "=== Project Setup Check ==="
if [ ! -f "Project.toml" ]; then
    echo "❌ Project.toml not found"
    exit 1
fi

if [ ! -f "scripts/extraction/drugbank_llama_extractor.jl" ]; then
    echo "❌ scripts/extraction/drugbank_llama_extractor.jl not found"
    exit 1
fi

if [ ! -f "approved_drugs_dict.json" ]; then
    echo "❌ approved_drugs_dict.json not found"
    exit 1
fi

if [ ! -f "prompts/llm_prompt_drugbank.txt" ]; then
    echo "❌ prompts/llm_prompt_drugbank.txt not found"
    exit 1
fi

echo "✓ Project setup verified"
echo ""

# Install Julia dependencies
echo "=== Installing Julia Dependencies ==="
julia --project=. -e 'using Pkg; Pkg.instantiate()'
if [ $? -eq 0 ]; then
    echo "✓ Julia dependencies installed"
else
    echo "❌ Failed to install Julia dependencies"
    exit 1
fi
echo ""

# Run DrugBank indication extraction
echo "=== Running DrugBank Indication Extraction ==="
if [ -n "$DRUGBANK_SINGLE_DRUG" ]; then
    echo "Processing single drug: $DRUGBANK_SINGLE_DRUG"
    echo "Running: julia --project=. scripts/extraction/drugbank_llama_extractor.jl \"$DRUGBANK_SINGLE_DRUG\""
    julia --project=. scripts/extraction/drugbank_llama_extractor.jl "$DRUGBANK_SINGLE_DRUG"
else
    echo "Processing all drugs in approved_drugs_dict.json"
    echo "Running: julia --project=. scripts/extraction/drugbank_llama_extractor.jl"
    julia --project=. scripts/extraction/drugbank_llama_extractor.jl
fi

EXTRACTION_EXIT_CODE=$?

echo ""
echo "=== Results ==="
if [ $EXTRACTION_EXIT_CODE -eq 0 ]; then
    echo "✅ DrugBank extraction completed successfully"
    
    # Show output files
    echo ""
    echo "Output files created:"
    ls -la llama_drugbank_extracted_indications/ | head -10
    
    # Show a summary if available
    echo ""
    echo "DrugBank extraction summary:"
    total_files=$(ls llama_drugbank_extracted_indications/*.json 2>/dev/null | wc -l)
    echo "Total drugs processed: $total_files"
    
    if [ $total_files -gt 0 ]; then
        echo ""
        echo "Sample results:"
        latest_file=$(ls -t llama_drugbank_extracted_indications/*.json | head -1)
        echo "Latest file: $(basename $latest_file)"
        jq '.metadata' "$latest_file" 2>/dev/null || echo "Metadata not available"
    fi
else
    echo "❌ DrugBank extraction failed with exit code: $EXTRACTION_EXIT_CODE"
fi

echo ""
echo "=== Job Summary ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
if [ -n "$DRUGBANK_SINGLE_DRUG" ]; then
    echo "Drug processed: $DRUGBANK_SINGLE_DRUG"
else
    echo "Mode: All drugs processing"
fi
echo "End time: $(date)"
echo "Exit code: $EXTRACTION_EXIT_CODE"

exit $EXTRACTION_EXIT_CODE