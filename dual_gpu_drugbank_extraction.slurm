#!/bin/bash
#SBATCH --job-name=dual_gpu_drugbank
#SBATCH --account=default
#SBATCH --partition=gpu
#SBATCH --qos=norm-gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --gres=gpu:2
#SBATCH --time=2:00:00
#SBATCH --output=logs/dual_gpu_drugbank_%j.out
#SBATCH --error=logs/dual_gpu_drugbank_%j.err
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
export DRUGBANK_DRUG1="${DRUGBANK_DRUG1:-}"
export DRUGBANK_DRUG2="${DRUGBANK_DRUG2:-}"

echo "=== Configuration ==="
echo "Drug 1 (GPU 0): ${DRUGBANK_DRUG1:-Auto-select}"
echo "Drug 2 (GPU 1): ${DRUGBANK_DRUG2:-Auto-select}"
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

if [ ! -f "scripts/extraction/dual_gpu_drugbank_coordinator.jl" ]; then
    echo "❌ scripts/extraction/dual_gpu_drugbank_coordinator.jl not found"
    exit 1
fi

if [ ! -f "approved_drugs_dict.json" ]; then
    echo "❌ approved_drugs_dict.json not found"
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
echo "=== Running Dual GPU DrugBank Extraction ==="
if [ -n "$DRUGBANK_DRUG1" ] && [ -n "$DRUGBANK_DRUG2" ]; then
    echo "Processing specified drugs: $DRUGBANK_DRUG1 (GPU 0) and $DRUGBANK_DRUG2 (GPU 1)"
    julia --project=. scripts/extraction/dual_gpu_drugbank_coordinator.jl "$DRUGBANK_DRUG1" "$DRUGBANK_DRUG2"
else
    echo "Auto-selecting next unprocessed drugs..."
    julia --project=. scripts/extraction/dual_gpu_drugbank_coordinator.jl
fi

EXTRACTION_EXIT_CODE=$?

echo ""
echo "=== Results ==="
if [ $EXTRACTION_EXIT_CODE -eq 0 ]; then
    echo "✅ Dual GPU DrugBank extraction completed successfully"
    
    # Show output files
    echo ""
    echo "Recent output files:"
    ls -lat llama_drugbank_extracted_indications/*.json | head -5
    
    # Show count
    echo ""
    echo "Total drugs processed:"
    ls llama_drugbank_extracted_indications/*.json 2>/dev/null | wc -l
else
    echo "❌ Dual GPU DrugBank extraction failed with exit code: $EXTRACTION_EXIT_CODE"
fi

echo ""
echo "=== Job Summary ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "End time: $(date)"
echo "Exit code: $EXTRACTION_EXIT_CODE"

exit $EXTRACTION_EXIT_CODE