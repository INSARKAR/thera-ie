#!/bin/bash
#SBATCH --job-name=phase1_empty
#SBATCH --array=1-4
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=8:00:00
#SBATCH --output=logs/batch_phase1_empty_%A_%a.out
#SBATCH --error=logs/batch_phase1_empty_%A_%a.err

# Batch Phase 1 PubMed Search - Empty Results Reprocessing
# Reprocesses only the 373 drugs with empty publications_analyzed arrays

# Load required modules
module load julia/1.8.5

# Create logs directory
mkdir -p logs

# Job array parameters
TOTAL_EMPTY=373
BATCH_SIZE=95  # Conservative batch size for reliable processing

# Calculate start index for this array task
START_INDEX=$(( ($SLURM_ARRAY_TASK_ID - 1) * $BATCH_SIZE + 1 ))

echo "=== SLURM Job Array Task $SLURM_ARRAY_TASK_ID ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Start Index: $START_INDEX"
echo "Batch Size: $BATCH_SIZE"
echo "Total Empty Results: $TOTAL_EMPTY"
echo "Node: $SLURMD_NODENAME"
echo "Start Time: $(date)"
echo ""

# Change to the correct directory
cd /oscar/home/isarkar/sarkarcode/thera-ie

# Verify files exist
if [[ ! -f "batch_phase1_empty_results_worker.jl" ]]; then
    echo "❌ Error: batch_phase1_empty_results_worker.jl not found"
    exit 1
fi

if [[ ! -f "empty_results_drugs.txt" ]]; then
    echo "❌ Error: empty_results_drugs.txt not found"
    exit 1
fi

echo "🚀 Starting empty results reprocessing worker..."

# Run the Julia empty results worker
julia --project=. batch_phase1_empty_results_worker.jl $START_INDEX $BATCH_SIZE

# Check exit status
if [[ $? -eq 0 ]]; then
    echo "✅ Empty results reprocessing completed successfully"
else
    echo "❌ Empty results reprocessing failed"
    exit 1
fi

echo ""
echo "End Time: $(date)"
echo "=== Job Array Task $SLURM_ARRAY_TASK_ID Complete ==="