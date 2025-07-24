#!/bin/bash
#SBATCH --job-name=phase2_pubmed_llama
#SBATCH --output=logs/phase2_step4_pubmed_llama_%A_%a.out
#SBATCH --error=logs/phase2_step4_pubmed_llama_%A_%a.err
#SBATCH --array=1-27
#SBATCH --time=48:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1

echo "=== Phase 2 Step 4: MeSH-Guided PubMed Llama Extraction ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Node: $(hostname)"
echo "Start time: $(date)"

# Load required modules
module load julia
module load ollama

# Set working directory
cd /oscar/home/isarkar/sarkarcode/thera-ie

# Verify required files
if [[ ! -f "scripts/extraction/phase2_step4_pubmed_llama_extractor.jl" ]]; then
    echo "❌ Main script not found"
    exit 1
fi

if [[ ! -f "prompts/llm_prompt_pubmed.txt" ]]; then
    echo "❌ Prompt file not found"
    exit 1
fi

if [[ ! -d "phase1_drug_pubmed_mesh" ]]; then
    echo "❌ Phase 1 input directory not found"
    exit 1
fi

# Environment setup
export JULIA_NUM_THREADS=8
export JULIA_PROJECT="."

# Ollama configuration
export OLLAMA_HOST="http://127.0.0.1:11434"
export OLLAMA_MODELS="$HOME/.ollama/models"

# Create output directory
mkdir -p phase2_indications_llama_pubmed
mkdir -p logs

# GPU setup
export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID

# Start Ollama server
echo "🚀 Starting Ollama server..."
ollama serve > ollama_server.log 2>&1 &
OLLAMA_PID=$!
echo "Ollama server started with PID: $OLLAMA_PID"

# Wait for Ollama to be ready
echo "⏳ Waiting for Ollama server to start..."
sleep 10
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama server is ready"
        break
    fi
    echo "Waiting for Ollama... ($i/30)"
    sleep 2
done

# Verify Ollama connection
if ! curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
    echo "❌ Failed to connect to Ollama"
    echo "📋 Checking Ollama server log:"
    tail -10 ollama_server.log || echo "No log file found"
    exit 1
fi

# Ensure llama3.2 model is available
echo "📦 Checking llama3.2 model..."
ollama list | grep llama3.2 || { echo "❌ llama3.2 model not found"; ollama pull llama3.2; }

# Calculate batch parameters
# Total drugs: ~2623, distributed across 27 array jobs
TOTAL_DRUGS=$(ls phase1_drug_pubmed_mesh/*.json | wc -l)
BATCH_SIZE=$(( (TOTAL_DRUGS + 26) / 27 ))  # Round up division
START_INDEX=$(( (SLURM_ARRAY_TASK_ID - 1) * BATCH_SIZE + 1 ))

echo "📊 Processing parameters:"
echo "  • Total drugs: $TOTAL_DRUGS"
echo "  • Batch size: $BATCH_SIZE"
echo "  • Start index: $START_INDEX"
echo "  • Array task: $SLURM_ARRAY_TASK_ID/27"

# Count existing results
EXISTING_COUNT=$(ls phase2_indications_llama_pubmed/*_pubmed_llama_indications.json 2>/dev/null | wc -l)
echo "  • Existing results: $EXISTING_COUNT"

# Run the extraction
echo "🚀 Starting Phase 2 Step 4 extraction..."
echo "Command: julia --project=. scripts/extraction/phase2_step4_pubmed_llama_extractor.jl $START_INDEX $BATCH_SIZE"

julia --project=. scripts/extraction/phase2_step4_pubmed_llama_extractor.jl $START_INDEX $BATCH_SIZE

EXTRACTION_EXIT_CODE=$?

# Final count
if [ $EXTRACTION_EXIT_CODE -eq 0 ]; then
    FINAL_COUNT=$(ls phase2_indications_llama_pubmed/*_pubmed_llama_indications.json 2>/dev/null | wc -l)
    NEW_RESULTS=$(( FINAL_COUNT - EXISTING_COUNT ))
    echo "✅ Phase 2 Step 4 extraction completed successfully"
    echo "📊 Results: $NEW_RESULTS new files (total: $FINAL_COUNT)"
else
    echo "❌ Phase 2 Step 4 extraction failed with exit code: $EXTRACTION_EXIT_CODE"
fi

# Cleanup Ollama server
echo "🧹 Shutting down Ollama server..."
if [ ! -z "$OLLAMA_PID" ] && kill -0 "$OLLAMA_PID" 2>/dev/null; then
    kill "$OLLAMA_PID"
    wait "$OLLAMA_PID" 2>/dev/null
    echo "Ollama server (PID: $OLLAMA_PID) terminated"
else
    echo "Force killing Ollama server..."
    pkill -f "ollama serve" || true
fi

echo "Phase 2 Step 4 job completed at: $(date)"
echo "Final exit code: $EXTRACTION_EXIT_CODE"
exit $EXTRACTION_EXIT_CODE