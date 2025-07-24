#!/bin/bash
#SBATCH --job-name=phase2_drugbank_llama
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=logs/phase2_drugbank_llama_%j.out
#SBATCH --error=logs/phase2_drugbank_llama_%j.err

# Phase 2 Step 1: DrugBank Llama Indication Extraction with Dual GPUs
# Extracts therapeutic indications from DrugBank text using Llama 3.2

# Load required modules
module load julia
module load ollama

# Create logs directory
mkdir -p logs

echo "=== Phase 2 Step 1: DrugBank Llama Indication Extraction ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "GPUs allocated: $SLURM_GPUS_ON_NODE"
echo "Start Time: $(date)"
echo ""

# Change to the correct directory
cd /oscar/home/isarkar/sarkarcode/thera-ie

# Verify required files exist
if [[ ! -f "scripts/extraction/phase2_step1_drugbank_llama_coordinator.jl" ]]; then
    echo "❌ Error: Coordinator script not found"
    exit 1
fi

if [[ ! -f "scripts/extraction/phase2_step1_drugbank_llama_extractor.jl" ]]; then
    echo "❌ Error: Worker script not found"
    exit 1
fi

if [[ ! -f "generated_dependency_files/approved_drugs_dict.jl" ]]; then
    echo "❌ Error: Approved drugs dictionary not found"
    exit 1
fi

if [[ ! -f "prompts/llm_prompt_drugbank.txt" ]]; then
    echo "❌ Error: DrugBank prompt template not found"
    exit 1
fi

# Set up Ollama models directory (use home directory like working scripts)
export OLLAMA_MODELS="$HOME/.ollama/models"
mkdir -p "$OLLAMA_MODELS"
export OLLAMA_HOST="http://127.0.0.1:11434"

# Check GPU availability
echo "🔍 Checking GPU availability..."
nvidia-smi --query-gpu=index,name,memory.total --format=csv
echo ""

# Set GPU visibility for Ollama
export CUDA_VISIBLE_DEVICES=0

# Start Ollama server
echo "🚀 Starting Ollama server with GPU access..."
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
ollama serve > ollama_server.log 2>&1 &
OLLAMA_PID=$!
echo "Ollama server started with PID: $OLLAMA_PID"

# Wait for Ollama to be ready
echo "⏳ Waiting for Ollama server to start..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama server is ready"
        break
    fi
    echo "Attempt $i/30..."
    sleep 2
done

# Verify Ollama connection and show debug info
echo "🔍 Testing Ollama connection..."
if ! curl -s http://localhost:11434/api/tags; then
    echo "❌ Failed to connect to Ollama"
    echo "📋 Checking Ollama server log:"
    tail -10 ollama_server.log || echo "No log file found"
    echo "📋 Checking if Ollama process is running:"
    ps aux | grep ollama || echo "No ollama processes found"
    exit 1
fi
echo ""

# Ensure llama3.2 model is available
echo "📦 Checking llama3.2 model..."
ollama list | grep llama3.2 || { echo "❌ llama3.2 model not found"; ollama pull llama3.2; }
echo ""

# Create output directory
mkdir -p phase2_indications_llama_drugbank

# Count existing progress
EXISTING_COUNT=$(ls phase2_indications_llama_drugbank/*_drugbank_extracted_indications.json 2>/dev/null | wc -l)
echo "📊 Existing progress: $EXISTING_COUNT drugs already processed"
echo ""

echo "🚀 Starting simple DrugBank extractor..."
echo "This will:"
echo "  • Process up to 2,915 approved drugs from DrugBank"
echo "  • Use single GPU for reliability"
echo "  • Skip already processed drugs"
echo "  • Extract therapeutic indications using Llama 3.2"
echo "  • Save results to phase2_indications_llama_drugbank/"
echo ""

# Run the fixed extractor (no path conflicts)
julia --project=. scripts/extraction/phase2_step1_fixed_drugbank_extractor.jl

# Check exit status
if [[ $? -eq 0 ]]; then
    echo "✅ Phase 2 Step 1 DrugBank Llama extraction completed successfully"
    
    # Count final results
    FINAL_COUNT=$(ls phase2_indications_llama_drugbank/*_drugbank_extracted_indications.json 2>/dev/null | wc -l)
    echo "📊 Final count: $FINAL_COUNT/2915 drugs processed"
else
    echo "❌ Phase 2 Step 1 DrugBank Llama extraction failed"
fi

# Cleanup Ollama server
echo "🧹 Shutting down Ollama server..."
if [[ -n "$OLLAMA_PID" ]]; then
    kill $OLLAMA_PID 2>/dev/null || true
fi

echo ""
echo "End Time: $(date)"
echo "=== Job Complete ===">