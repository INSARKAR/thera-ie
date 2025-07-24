#!/bin/bash
#SBATCH --job-name=phase2_pubmed_single
#SBATCH --output=logs/phase2_pubmed_%A_%a.out
#SBATCH --error=logs/phase2_pubmed_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1

# Get drug name from array index
DRUG_INDEX=$SLURM_ARRAY_TASK_ID
ALL_DRUGS=($(ls /oscar/home/isarkar/sarkarcode/thera/phase1_drug_pubmed_mesh/*.json | sed 's|.*/||' | sed 's|\.json$||' | sort))
DRUG_NAME=${ALL_DRUGS[$((DRUG_INDEX-1))]}

echo "=== Phase 2 Step 4: Single Drug Processing ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task: $SLURM_ARRAY_TASK_ID"
echo "Drug: $DRUG_NAME"
echo "Node: $(hostname)"
echo "Start time: $(date)"

# Load modules
module load julia
module load ollama

cd /oscar/home/isarkar/sarkarcode/thera

# Check if already processed
OUTPUT_FILE="phase2_indications_llama_pubmed/${DRUG_NAME}_pubmed_llama_indications.json"
if [[ -f "$OUTPUT_FILE" ]]; then
    echo "✅ Already processed: $DRUG_NAME"
    exit 0
fi

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
ollama serve > ollama_${SLURM_JOB_ID}.log 2>&1 &
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

# Process single drug
echo "🧪 Processing: $DRUG_NAME"
julia --project=. scripts/extraction/phase2_step4_pubmed_llama_extractor.jl $DRUG_INDEX 1

EXIT_CODE=$?

# Cleanup
kill $OLLAMA_PID 2>/dev/null || true
pkill -f "ollama serve" || true

if [[ -f "$OUTPUT_FILE" ]]; then
    echo "✅ SUCCESS: $DRUG_NAME processed"
else
    echo "❌ FAILED: $DRUG_NAME"
fi

echo "Completed: $(date)"
exit $EXIT_CODE