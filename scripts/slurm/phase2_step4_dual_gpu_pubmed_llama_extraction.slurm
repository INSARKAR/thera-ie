#!/bin/bash
#SBATCH --job-name=phase2_dual_gpu_pubmed_llama
#SBATCH --output=logs/phase2_step4_dual_gpu_pubmed_llama_%A_%a.out
#SBATCH --error=logs/phase2_step4_dual_gpu_pubmed_llama_%A_%a.err
#SBATCH --array=1-14%4
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2

echo "=== Phase 2 Step 4: Dual GPU MeSH-Guided PubMed Llama Extraction ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Node: $(hostname)"
echo "GPUs: $CUDA_VISIBLE_DEVICES"
echo "Start time: $(date)"

# Load required modules
module load julia
module load ollama

# Set working directory
cd /oscar/home/isarkar/sarkarcode/thera

# Verify required files
if [[ ! -f "scripts/extraction/phase2_step4_dual_gpu_pubmed_llama_extractor.jl" ]]; then
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
export JULIA_NUM_THREADS=16
export JULIA_PROJECT="."

# Ollama configuration for dual GPU
export OLLAMA_MODELS="$HOME/.ollama/models"

# Create output directory
mkdir -p phase2_indications_llama_pubmed
mkdir -p logs

# GPU setup
export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID

# Start dual Ollama servers (one per GPU)
echo "🚀 Starting dual Ollama servers..."

# GPU 0 server (port 11434)
CUDA_VISIBLE_DEVICES=0 OLLAMA_HOST="http://127.0.0.1:11434" ollama serve > ollama_gpu0_server.log 2>&1 &
OLLAMA_PID_0=$!
echo "Ollama GPU 0 server started with PID: $OLLAMA_PID_0"

# GPU 1 server (port 11435) 
CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST="http://127.0.0.1:11435" ollama serve > ollama_gpu1_server.log 2>&1 &
OLLAMA_PID_1=$!
echo "Ollama GPU 1 server started with PID: $OLLAMA_PID_1"

# Wait for both servers to be ready
echo "⏳ Waiting for dual Ollama servers to start..."
sleep 15

# Check GPU 0 server
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama GPU 0 server is ready"
        break
    fi
    echo "Waiting for Ollama GPU 0... ($i/30)"
    sleep 2
done

# Check GPU 1 server
for i in {1..30}; do
    if curl -s http://127.0.0.1:11435/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama GPU 1 server is ready"
        break
    fi
    echo "Waiting for Ollama GPU 1... ($i/30)"
    sleep 2
done

# Verify both connections
if ! curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
    echo "❌ Failed to connect to Ollama GPU 0"
    exit 1
fi

if ! curl -s http://127.0.0.1:11435/api/tags > /dev/null 2>&1; then
    echo "❌ Failed to connect to Ollama GPU 1"
    exit 1
fi

# Ensure llama3.2 model is available on both GPUs
echo "📦 Loading llama3.2 model on both GPUs..."
OLLAMA_HOST="http://127.0.0.1:11434" ollama list | grep llama3.2 || OLLAMA_HOST="http://127.0.0.1:11434" ollama pull llama3.2
OLLAMA_HOST="http://127.0.0.1:11435" ollama list | grep llama3.2 || OLLAMA_HOST="http://127.0.0.1:11435" ollama pull llama3.2

# Calculate batch parameters for dual GPU processing
# Total drugs: ~2623, distributed across 14 array jobs (each with 2 GPUs)
TOTAL_DRUGS=$(ls phase1_drug_pubmed_mesh/*.json | wc -l)
BATCH_SIZE=$(( (TOTAL_DRUGS + 13) / 14 ))  # Round up division
START_INDEX=$(( (SLURM_ARRAY_TASK_ID - 1) * BATCH_SIZE + 1 ))

echo "📊 Dual GPU processing parameters:"
echo "  • Total drugs: $TOTAL_DRUGS"
echo "  • Batch size per job: $BATCH_SIZE"
echo "  • Start index: $START_INDEX"
echo "  • Array task: $SLURM_ARRAY_TASK_ID/14"
echo "  • Each GPU processes: ~$(( BATCH_SIZE / 2 )) drugs"

# Count existing results
EXISTING_COUNT=$(ls phase2_indications_llama_pubmed/*_pubmed_llama_indications.json 2>/dev/null | wc -l)
echo "  • Existing results: $EXISTING_COUNT"

# Run dual GPU extraction in parallel
echo "🚀 Starting dual GPU Phase 2 Step 4 extraction..."

# Start GPU 0 process
julia --project=. scripts/extraction/phase2_step4_dual_gpu_pubmed_llama_extractor.jl $START_INDEX $BATCH_SIZE 0 &
GPU0_PID=$!

# Start GPU 1 process
julia --project=. scripts/extraction/phase2_step4_dual_gpu_pubmed_llama_extractor.jl $START_INDEX $BATCH_SIZE 1 &
GPU1_PID=$!

echo "🔄 GPU processes started:"
echo "  • GPU 0 PID: $GPU0_PID"
echo "  • GPU 1 PID: $GPU1_PID"

# Wait for both processes to complete
wait $GPU0_PID
GPU0_EXIT=$?

wait $GPU1_PID
GPU1_EXIT=$?

echo "🏁 GPU processes completed:"
echo "  • GPU 0 exit code: $GPU0_EXIT"
echo "  • GPU 1 exit code: $GPU1_EXIT"

# Determine overall exit code
if [ $GPU0_EXIT -eq 0 ] && [ $GPU1_EXIT -eq 0 ]; then
    EXTRACTION_EXIT_CODE=0
    echo "✅ Dual GPU Phase 2 Step 4 extraction completed successfully"
elif [ $GPU0_EXIT -eq 0 ] || [ $GPU1_EXIT -eq 0 ]; then
    EXTRACTION_EXIT_CODE=0  # Partial success
    echo "⚠️  Dual GPU Phase 2 Step 4 extraction completed with partial success"
else
    EXTRACTION_EXIT_CODE=1
    echo "❌ Dual GPU Phase 2 Step 4 extraction failed"
fi

# Final count
FINAL_COUNT=$(ls phase2_indications_llama_pubmed/*_pubmed_llama_indications.json 2>/dev/null | wc -l)
NEW_RESULTS=$(( FINAL_COUNT - EXISTING_COUNT ))
echo "📊 Results: $NEW_RESULTS new files (total: $FINAL_COUNT)"

# Cleanup Ollama servers
echo "🧹 Shutting down dual Ollama servers..."

if [ ! -z "$OLLAMA_PID_0" ] && kill -0 "$OLLAMA_PID_0" 2>/dev/null; then
    kill "$OLLAMA_PID_0"
    wait "$OLLAMA_PID_0" 2>/dev/null
    echo "Ollama GPU 0 server (PID: $OLLAMA_PID_0) terminated"
fi

if [ ! -z "$OLLAMA_PID_1" ] && kill -0 "$OLLAMA_PID_1" 2>/dev/null; then
    kill "$OLLAMA_PID_1"
    wait "$OLLAMA_PID_1" 2>/dev/null
    echo "Ollama GPU 1 server (PID: $OLLAMA_PID_1) terminated"
fi

# Force cleanup if needed
pkill -f "ollama serve" || true

echo "Dual GPU Phase 2 Step 4 job completed at: $(date)"
echo "Final exit code: $EXTRACTION_EXIT_CODE"
exit $EXTRACTION_EXIT_CODE