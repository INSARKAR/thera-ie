#!/bin/bash
#SBATCH --job-name=phase2_mesh_indications
#SBATCH --array=1-8
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=4:00:00
#SBATCH --output=logs/phase2_mesh_indications_%A_%a.out
#SBATCH --error=logs/phase2_mesh_indications_%A_%a.err

# Phase 2 Step 2: MeSH-Based Indication Extraction
# Extracts unique MeSH descriptors as indications from Phase 1 filtered publications

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
if [[ ! -f "scripts/extraction/phase2_step2_mesh_indication_extractor.jl" ]]; then
    echo "❌ Error: scripts/extraction/phase2_step2_mesh_indication_extractor.jl not found"
    exit 1
fi

if [[ ! -d "phase1_drug_pubmed_mesh" ]]; then
    echo "❌ Error: phase1_drug_pubmed_mesh directory not found"
    exit 1
fi

echo "🚀 Starting Phase 2 Step 2: MeSH indication extraction worker..."

# Run the Julia MeSH indication extraction worker
julia --project=. scripts/extraction/phase2_step2_mesh_indication_extractor.jl $START_INDEX $BATCH_SIZE

# Check exit status
if [[ $? -eq 0 ]]; then
    echo "✅ Phase 2 Step 2 MeSH indication extraction completed successfully"
else
    echo "❌ Phase 2 Step 2 MeSH indication extraction failed"
    exit 1
fi

echo ""
echo "End Time: $(date)"
echo "=== Job Array Task $SLURM_ARRAY_TASK_ID Complete ==="