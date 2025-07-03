#!/bin/bash
#SBATCH --job-name=dual_gpu_llama_extract
#SBATCH --account=default
#SBATCH --partition=gpu
#SBATCH --qos=norm-gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --gres=gpu:2
#SBATCH --time=2:00:00
#SBATCH --output=logs/dual_gpu_llama_extraction_%j.out
#SBATCH --error=logs/dual_gpu_llama_extraction_%j.err
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
export LLAMA_DRUG1="${LLAMA_DRUG1:-Levothyroxine}"
export LLAMA_DRUG2="${LLAMA_DRUG2:-Metformin}"

echo "=== Configuration ==="
echo "Drug 1 (GPU 0): $LLAMA_DRUG1"
echo "Drug 2 (GPU 1): $LLAMA_DRUG2"
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

# Start Ollama servers on both GPUs
echo "=== Starting Ollama Servers ==="

# Start first Ollama server on GPU 0, port 11434
echo "Starting Ollama server on GPU 0 (port 11434)..."
CUDA_VISIBLE_DEVICES=0 OLLAMA_HOST=http://127.0.0.1:11434 ollama serve &
OLLAMA_PID1=$!
echo "Ollama server 1 started with PID: $OLLAMA_PID1"

# Start second Ollama server on GPU 1, port 11435
echo "Starting Ollama server on GPU 1 (port 11435)..."
CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST=http://127.0.0.1:11435 ollama serve &
OLLAMA_PID2=$!
echo "Ollama server 2 started with PID: $OLLAMA_PID2"

# Wait for both Ollama servers to be ready
echo "Waiting for Ollama servers to start..."

# Wait for server 1
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
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
    if curl -s http://localhost:11435/api/tags > /dev/null 2>&1; then
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
echo ""

# Check if Llama 3.2 model is available on both servers
echo "=== Checking Llama 3.2 Models ==="

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
echo ""

# Test both Ollama servers
echo "=== Testing Ollama Servers ==="

# Test server 1
TEST_RESPONSE1=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model": "llama3.2", "prompt": "Say TEST GPU1", "stream": false, "options": {"max_tokens": 10}}' \
    --connect-timeout 10 --max-time 30)

if [ $? -eq 0 ] && [ ! -z "$TEST_RESPONSE1" ]; then
    echo "✓ Ollama server 1 test successful"
    echo "Test response 1: $(echo $TEST_RESPONSE1 | jq -r '.response' 2>/dev/null || echo $TEST_RESPONSE1 | head -c 50)..."
else
    echo "❌ Ollama server 1 test failed"
    kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
    exit 1
fi

# Test server 2
TEST_RESPONSE2=$(curl -s -X POST http://localhost:11435/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model": "llama3.2", "prompt": "Say TEST GPU2", "stream": false, "options": {"max_tokens": 10}}' \
    --connect-timeout 10 --max-time 30)

if [ $? -eq 0 ] && [ ! -z "$TEST_RESPONSE2" ]; then
    echo "✓ Ollama server 2 test successful"
    echo "Test response 2: $(echo $TEST_RESPONSE2 | jq -r '.response' 2>/dev/null || echo $TEST_RESPONSE2 | head -c 50)..."
else
    echo "❌ Ollama server 2 test failed"
    kill $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
    exit 1
fi
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "=== Cleanup ==="
    if [ ! -z "$OLLAMA_PID1" ]; then
        echo "Stopping Ollama server 1 (PID: $OLLAMA_PID1)..."
        kill $OLLAMA_PID1 2>/dev/null
    fi
    if [ ! -z "$OLLAMA_PID2" ]; then
        echo "Stopping Ollama server 2 (PID: $OLLAMA_PID2)..."
        kill $OLLAMA_PID2 2>/dev/null
    fi
    wait $OLLAMA_PID1 $OLLAMA_PID2 2>/dev/null
    echo "✓ Ollama servers stopped"
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

if [ ! -f "scripts/extraction/dual_gpu_llama_coordinator.jl" ]; then
    echo "❌ scripts/extraction/dual_gpu_llama_coordinator.jl not found"
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

# Run dual GPU coordination script
echo "=== Running Dual GPU Drug Extraction ==="
echo "Processing drugs: $LLAMA_DRUG1 (GPU 0) and $LLAMA_DRUG2 (GPU 1)"
echo "Running: julia --project=. scripts/extraction/dual_gpu_llama_coordinator.jl \"$LLAMA_DRUG1\" \"$LLAMA_DRUG2\""
julia --project=. scripts/extraction/dual_gpu_llama_coordinator.jl "$LLAMA_DRUG1" "$LLAMA_DRUG2"

EXTRACTION_EXIT_CODE=$?

echo ""
echo "=== Results ==="
if [ $EXTRACTION_EXIT_CODE -eq 0 ]; then
    echo "✓ Dual GPU extraction completed successfully"
    
    # Show output files
    echo ""
    echo "Output files created:"
    ls -la llama_pubmed_extracted_indications/
    
    # Show summaries if available
    if [ -f "llama_pubmed_extracted_indications/${LLAMA_DRUG1}_llama_extracted_indications.json" ]; then
        echo ""
        echo "Summary for $LLAMA_DRUG1:"
        jq '.metadata' "llama_pubmed_extracted_indications/${LLAMA_DRUG1}_llama_extracted_indications.json" 2>/dev/null || echo "Summary not available"
    fi
    
    if [ -f "llama_pubmed_extracted_indications/${LLAMA_DRUG2}_llama_extracted_indications.json" ]; then
        echo ""
        echo "Summary for $LLAMA_DRUG2:"
        jq '.metadata' "llama_pubmed_extracted_indications/${LLAMA_DRUG2}_llama_extracted_indications.json" 2>/dev/null || echo "Summary not available"
    fi
else
    echo "❌ Dual GPU extraction failed with exit code: $EXTRACTION_EXIT_CODE"
fi

echo ""
echo "=== Job Summary ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Drug 1: $LLAMA_DRUG1"
echo "Drug 2: $LLAMA_DRUG2"
echo "End time: $(date)"
echo "Exit code: $EXTRACTION_EXIT_CODE"

exit $EXTRACTION_EXIT_CODE