#!/bin/bash
#SBATCH --job-name=llama_drug_extract
#SBATCH --account=default
#SBATCH --partition=gpu
#SBATCH --qos=norm-gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=2:00:00
#SBATCH --output=logs/llama_extraction_%j.out
#SBATCH --error=logs/llama_extraction_%j.err
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
export LLAMA_SINGLE_DRUG="${LLAMA_SINGLE_DRUG:-Levothyroxine}"
export LLAMA_TEST_MODE="${LLAMA_TEST_MODE:-false}"
export LLAMA_MAX_FILES="${LLAMA_MAX_FILES:-5}"

echo "=== Configuration ==="
echo "Drug to process: $LLAMA_SINGLE_DRUG"
echo "Test mode: $LLAMA_TEST_MODE"
if [ "$LLAMA_TEST_MODE" = "true" ]; then
    echo "Max files in test mode: $LLAMA_MAX_FILES"
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

if [ ! -f "llama_drug_indication_extractor.jl" ]; then
    echo "❌ llama_drug_indication_extractor.jl not found"
    exit 1
fi

if [ ! -d "drug_pubmed_refs" ]; then
    echo "❌ drug_pubmed_refs directory not found"
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

# Choose which script to run based on test mode
if [ "$LLAMA_TEST_MODE" = "true" ]; then
    echo "=== Running Quick Test ==="
    SCRIPT_TO_RUN="quick_test_levothyroxine.jl"
    if [ ! -f "$SCRIPT_TO_RUN" ]; then
        echo "❌ Test script not found: $SCRIPT_TO_RUN"
        exit 1
    fi
    echo "Running: julia --project=. $SCRIPT_TO_RUN"
    julia --project=. "$SCRIPT_TO_RUN"
else
    echo "=== Running Full Drug Indication Extraction ==="
    echo "Processing drug: $LLAMA_SINGLE_DRUG"
    echo "Running: julia --project=. scripts/extraction/intelligent_drug_extractor.jl \"$LLAMA_SINGLE_DRUG\""
    julia --project=. scripts/extraction/intelligent_drug_extractor.jl "$LLAMA_SINGLE_DRUG"
fi

EXTRACTION_EXIT_CODE=$?

echo ""
echo "=== Results ==="
if [ $EXTRACTION_EXIT_CODE -eq 0 ]; then
    echo "✓ Extraction completed successfully"
    
    # Show output files
    echo ""
    echo "Output files created:"
    ls -la llama_pubmed_extracted_indications/
    
    # Show a summary if available
    if [ -f "llama_pubmed_extracted_indications/${LLAMA_SINGLE_DRUG}_llama_extracted.json" ]; then
        echo ""
        echo "Summary for $LLAMA_SINGLE_DRUG:"
        jq '.metadata' "llama_pubmed_extracted_indications/${LLAMA_SINGLE_DRUG}_llama_extracted.json" 2>/dev/null || echo "Summary not available"
    fi
    
    if [ -f "llama_pubmed_extracted_indications/levothyroxine_quick_test.json" ]; then
        echo ""
        echo "Quick test results:"
        jq '.test_info' "llama_pubmed_extracted_indications/levothyroxine_quick_test.json" 2>/dev/null || echo "Test results not available"
    fi
else
    echo "❌ Extraction failed with exit code: $EXTRACTION_EXIT_CODE"
fi

echo ""
echo "=== Job Summary ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Drug processed: $LLAMA_SINGLE_DRUG"
echo "Test mode: $LLAMA_TEST_MODE"
echo "End time: $(date)"
echo "Exit code: $EXTRACTION_EXIT_CODE"

exit $EXTRACTION_EXIT_CODE
