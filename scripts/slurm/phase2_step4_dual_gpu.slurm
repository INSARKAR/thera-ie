#!/bin/bash
#SBATCH --job-name=phase2_pubmed_dual
#SBATCH --output=logs/phase2_pubmed_dual_%A_%a.out
#SBATCH --error=logs/phase2_pubmed_dual_%A_%a.err
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2

# Configuration
DRUGS_PER_GPU=10
TOTAL_DRUGS_PER_JOB=$((DRUGS_PER_GPU * 2))  # 20 drugs per job (10 per GPU)

# Calculate drug indices for this job
BATCH_START=$(( (SLURM_ARRAY_TASK_ID - 1) * TOTAL_DRUGS_PER_JOB + 1 ))
BATCH_END=$(( SLURM_ARRAY_TASK_ID * TOTAL_DRUGS_PER_JOB ))

echo "=== Phase 2 Step 4: Dual GPU Processing ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task: $SLURM_ARRAY_TASK_ID"
echo "Processing drugs: $BATCH_START to $BATCH_END"
echo "Drugs per GPU: $DRUGS_PER_GPU"
echo "Total drugs this job: $TOTAL_DRUGS_PER_JOB"
echo "Node: $(hostname)"
echo "Start time: $(date)"

# Load modules
module load julia
module load ollama

cd /oscar/home/isarkar/sarkarcode/thera-ie

# Environment setup
export JULIA_PROJECT="."
export OLLAMA_MODELS="$HOME/.ollama/models"

# Create directories
mkdir -p phase2_indications_llama_pubmed
mkdir -p logs

# Start two Ollama servers (one per GPU)
echo "🚀 Starting Ollama servers on both GPUs..."

# GPU 0 server
export CUDA_VISIBLE_DEVICES=0
export OLLAMA_HOST="http://127.0.0.1:11434"
ollama serve > ollama_gpu0_${SLURM_JOB_ID}.log 2>&1 &
OLLAMA_PID_0=$!

# GPU 1 server  
export CUDA_VISIBLE_DEVICES=1
export OLLAMA_HOST="http://127.0.0.1:11435"
ollama serve > ollama_gpu1_${SLURM_JOB_ID}.log 2>&1 &
OLLAMA_PID_1=$!

# Wait for both servers
sleep 15

# Test GPU 0 server
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        echo "✅ GPU 0 Ollama ready"
        break
    fi
    sleep 2
done

# Test GPU 1 server
for i in {1..30}; do
    if curl -s http://127.0.0.1:11435/api/tags > /dev/null 2>&1; then
        echo "✅ GPU 1 Ollama ready"
        break
    fi
    sleep 2
done

# Load models on both GPUs
echo "📦 Loading llama3.2 on both GPUs..."
CUDA_VISIBLE_DEVICES=0 OLLAMA_HOST="http://127.0.0.1:11434" ollama list | grep llama3.2 || CUDA_VISIBLE_DEVICES=0 OLLAMA_HOST="http://127.0.0.1:11434" ollama pull llama3.2 &
CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST="http://127.0.0.1:11435" ollama list | grep llama3.2 || CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST="http://127.0.0.1:11435" ollama pull llama3.2 &
wait

# Calculate drug ranges for each GPU
GPU0_START=$BATCH_START
GPU0_END=$((BATCH_START + DRUGS_PER_GPU - 1))
GPU1_START=$((GPU0_END + 1))
GPU1_END=$BATCH_END

echo "🧪 Starting parallel processing..."
echo "GPU 0: drugs $GPU0_START to $GPU0_END"
echo "GPU 1: drugs $GPU1_START to $GPU1_END"

# Process drugs on GPU 0
(
    export CUDA_VISIBLE_DEVICES=0
    export OLLAMA_HOST="http://127.0.0.1:11434"
    julia --project=. scripts/extraction/phase2_step4_pubmed_llama_extractor.jl $GPU0_START $DRUGS_PER_GPU
) &
GPU0_PID=$!

# Process drugs on GPU 1
(
    export CUDA_VISIBLE_DEVICES=1
    export OLLAMA_HOST="http://127.0.0.1:11435"
    julia --project=. scripts/extraction/phase2_step4_pubmed_llama_extractor.jl $GPU1_START $DRUGS_PER_GPU
) &
GPU1_PID=$!

# Wait for both processing jobs to complete
wait $GPU0_PID
GPU0_EXIT=$?
wait $GPU1_PID
GPU1_EXIT=$?

# Cleanup
kill $OLLAMA_PID_0 $OLLAMA_PID_1 2>/dev/null || true
pkill -f "ollama serve" || true

# Check results
SUCCESS_COUNT=$(ls phase2_indications_llama_pubmed/*_pubmed_llama_indications.json 2>/dev/null | wc -l)

echo "🏁 Processing Complete"
echo "GPU 0 exit code: $GPU0_EXIT"
echo "GPU 1 exit code: $GPU1_EXIT"
echo "Total output files: $SUCCESS_COUNT"
echo "Completed: $(date)"

# Exit with error if either GPU failed
if [ $GPU0_EXIT -ne 0 ] || [ $GPU1_EXIT -ne 0 ]; then
    echo "❌ One or more GPUs failed"
    exit 1
else
    echo "✅ Dual GPU processing successful"
    exit 0
fi