#!/bin/bash
#SBATCH --job-name=phase2_pubmed_batch
#SBATCH --output=logs/phase2_pubmed_batch_%A_%a.out
#SBATCH --error=logs/phase2_pubmed_batch_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1

# Configuration - process multiple drugs per job
DRUGS_PER_JOB=10

# Calculate drug indices for this job
BATCH_START=$(( (SLURM_ARRAY_TASK_ID - 1) * DRUGS_PER_JOB + 1 ))
BATCH_END=$(( SLURM_ARRAY_TASK_ID * DRUGS_PER_JOB ))

echo "=== Phase 2 Step 4: Single GPU Batch Processing ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task: $SLURM_ARRAY_TASK_ID"
echo "Processing drugs: $BATCH_START to $BATCH_END"
echo "Drugs per job: $DRUGS_PER_JOB"
echo "Node: $(hostname)"
echo "Start time: $(date)"

# Load modules
module load julia
module load ollama

cd /oscar/home/isarkar/sarkarcode/thera

# Environment setup
export JULIA_PROJECT="."
export OLLAMA_HOST="http://127.0.0.1:11434"
export OLLAMA_MODELS="$HOME/.ollama/models"
export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID

# Create directories
mkdir -p phase2_indications_llama_pubmed
mkdir -p logs

# Start Ollama
echo "🚀 Starting Ollama server..."
ollama serve > ollama_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.log 2>&1 &
OLLAMA_PID=$!

# Wait for Ollama
sleep 10
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama ready"
        break
    fi
    sleep 2
done

# Load model
echo "📦 Loading llama3.2..."
ollama list | grep llama3.2 || ollama pull llama3.2

# Process batch of drugs
echo "🧪 Processing drugs $BATCH_START to $BATCH_END"
julia --project=. scripts/extraction/phase2_step4_pubmed_llama_extractor.jl $BATCH_START $DRUGS_PER_JOB

EXIT_CODE=$?

# Cleanup
kill $OLLAMA_PID 2>/dev/null || true
pkill -f "ollama serve" || true

# Count successful outputs
SUCCESS_COUNT=0
for ((i=BATCH_START; i<=BATCH_END; i++)); do
    ALL_DRUGS=($(ls /oscar/home/isarkar/sarkarcode/thera/phase1_drug_pubmed_mesh/*.json | sed 's|.*/||' | sed 's|\.json$||' | sort))
    if [ $i -le ${#ALL_DRUGS[@]} ]; then
        DRUG_NAME=${ALL_DRUGS[$((i-1))]}
        SAFE_NAME=$(echo "$DRUG_NAME" | sed 's/[^a-zA-Z0-9]/_/g')
        OUTPUT_FILE="phase2_indications_llama_pubmed/${SAFE_NAME}_pubmed_llama_indications.json"
        if [[ -f "$OUTPUT_FILE" ]]; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    fi
done

echo "🏁 Batch Complete"
echo "Successful outputs: $SUCCESS_COUNT/$DRUGS_PER_JOB"
echo "Completed: $(date)"

if [ $SUCCESS_COUNT -eq $DRUGS_PER_JOB ]; then
    echo "✅ All drugs in batch processed successfully"
    exit 0
elif [ $SUCCESS_COUNT -gt 0 ]; then
    echo "⚠️ Partial success: $SUCCESS_COUNT/$DRUGS_PER_JOB"
    exit 0
else
    echo "❌ Batch failed: no successful outputs"
    exit 1
fi