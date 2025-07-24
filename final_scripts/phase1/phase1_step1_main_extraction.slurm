#!/bin/bash
#SBATCH --job-name=phase1_cleanup
#SBATCH --array=1-8
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=12:00:00
#SBATCH --output=logs/batch_phase1_cleanup_%A_%a.out
#SBATCH --error=logs/batch_phase1_cleanup_%A_%a.err

# Batch Phase 1 PubMed Search Cleanup
# Fresh extraction of all drugs with fixed worker

# Load required modules
module load julia/1.8.5

# Create logs directory
mkdir -p logs

# Job array parameters
TOTAL_DRUGS=2915
BATCH_SIZE=370  # Conservative batch size for thorough processing

# Calculate start index for this array task
START_INDEX=$(( ($SLURM_ARRAY_TASK_ID - 1) * $BATCH_SIZE + 1 ))

echo "=== SLURM Job Array Task $SLURM_ARRAY_TASK_ID ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Start Index: $START_INDEX"
echo "Batch Size: $BATCH_SIZE"
echo "Total Drugs: $TOTAL_DRUGS"
echo "Node: $SLURMD_NODENAME"
echo "Start Time: $(date)"
echo ""

# Change to the correct directory
cd /oscar/home/isarkar/sarkarcode/thera

# Verify files exist
if [[ ! -f "batch_phase1_pubmed_cleanup_worker.jl" ]]; then
    echo "❌ Error: batch_phase1_pubmed_cleanup_worker.jl not found"
    exit 1
fi

if [[ ! -f "all_drugs_for_cleanup.txt" ]]; then
    echo "❌ Error: all_drugs_for_cleanup.txt not found"
    exit 1
fi

echo "🚀 Starting batch cleanup worker..."

# Run the Julia cleanup worker
julia --project=. batch_phase1_pubmed_cleanup_worker.jl $START_INDEX $BATCH_SIZE

# Check exit status
if [[ $? -eq 0 ]]; then
    echo "✅ Batch cleanup completed successfully"
else
    echo "❌ Batch cleanup failed"
    exit 1
fi

echo ""
echo "End Time: $(date)"
echo "=== Job Array Task $SLURM_ARRAY_TASK_ID Complete ==="