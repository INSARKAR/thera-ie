#!/bin/bash
#SBATCH --job-name=phase1_mesh_filter
#SBATCH --array=1-8
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=6:00:00
#SBATCH --output=logs/phase1_mesh_filter_%A_%a.out
#SBATCH --error=logs/phase1_mesh_filter_%A_%a.err

# Phase 1 Step 5: MeSH Filtering and Reorganization
# Filters publications by semantic relevance and frequency, organizes by MeSH descriptor

# Load required modules
module load julia/1.11.1s-kueea5s

# Create logs directory
mkdir -p logs

# Job array parameters
TOTAL_FILES=2623
BATCH_SIZE=330  # Process ~330 files per job for efficient parallel processing

# Calculate start index for this array task
START_INDEX=$(( ($SLURM_ARRAY_TASK_ID - 1) * $BATCH_SIZE + 1 ))

echo "=== SLURM Job Array Task $SLURM_ARRAY_TASK_ID ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Start Index: $START_INDEX"
echo "Batch Size: $BATCH_SIZE"
echo "Total Files: $TOTAL_FILES"
echo "Node: $SLURMD_NODENAME"
echo "Start Time: $(date)"
echo ""

# Change to the correct directory
cd /oscar/home/isarkar/sarkarcode/thera

# Verify required files exist
if [[ ! -f "scripts/extraction/phase1_step5_mesh_filtering_worker.jl" ]]; then
    echo "❌ Error: scripts/extraction/phase1_step5_mesh_filtering_worker.jl not found"
    exit 1
fi

if [[ ! -f "mesh_semantic_headings.jl" ]]; then
    echo "❌ Error: mesh_semantic_headings.jl not found"
    exit 1
fi

if [[ ! -d "phase1_drug_pubmed_refs" ]]; then
    echo "❌ Error: phase1_drug_pubmed_refs directory not found"
    exit 1
fi

echo "🚀 Starting MeSH filtering worker..."

# Run the Julia MeSH filtering worker
julia --project=. scripts/extraction/phase1_step5_mesh_filtering_worker.jl $START_INDEX $BATCH_SIZE

# Check exit status
if [[ $? -eq 0 ]]; then
    echo "✅ MeSH filtering completed successfully"
else
    echo "❌ MeSH filtering failed"
    exit 1
fi

echo ""
echo "End Time: $(date)"
echo "=== Job Array Task $SLURM_ARRAY_TASK_ID Complete ==="