#!/bin/bash
#SBATCH --job-name=phase2_analysis
#SBATCH --account=default
#SBATCH --partition=batch
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --output=logs/phase2_analysis_%A_%a.out
#SBATCH --error=logs/phase2_analysis_%A_%a.err

# Phase2 Drug-Indication Analysis SLURM Job
# This script processes individual drugs for phase2 analysis

echo "=================================================================="
echo "Phase2 Drug-Indication Analysis"
echo "=================================================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Node: $(hostname)"
echo "Start time: $(date)"
echo "Working directory: $(pwd)"
echo ""

# Validate environment
if [ ! -f "phase2_drug_indication_analyzer.jl" ]; then
    echo "❌ Error: phase2_drug_indication_analyzer.jl not found in current directory"
    exit 1
fi

if [ ! -d "phase1_results" ]; then
    echo "❌ Error: phase1_results directory not found"
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p logs

# Get drug name from array task ID
echo "🔍 Determining drug to process..."

# Get list of remaining drugs and select based on array task ID
DRUG_NAME=$(julia --project=. -e "
include(\"phase2_drug_indication_analyzer.jl\")
status = get_processing_status()
remaining_drugs = status[\"remaining_drugs\"]

if length(ARGS) > 0 && parse(Int, ARGS[1]) <= length(remaining_drugs)
    drug_index = parse(Int, ARGS[1])
    println(remaining_drugs[drug_index])
else
    println(\"ERROR: Invalid array index\")
    exit(1)
end
" $SLURM_ARRAY_TASK_ID)

if [ "$DRUG_NAME" = "ERROR: Invalid array index" ]; then
    echo "❌ Error: Invalid array task ID $SLURM_ARRAY_TASK_ID"
    exit 1
fi

echo "📋 Processing drug: $DRUG_NAME"
echo ""

# Run phase2 analysis for the specific drug
echo "🚀 Starting phase2 analysis..."
julia --project=. phase2_drug_indication_analyzer.jl "$DRUG_NAME"

# Check if the analysis completed successfully
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Phase2 analysis completed successfully for: $DRUG_NAME"
else
    echo ""
    echo "❌ Phase2 analysis failed for: $DRUG_NAME"
    exit 1
fi

echo ""
echo "Job completed at: $(date)"
echo "=================================================================="