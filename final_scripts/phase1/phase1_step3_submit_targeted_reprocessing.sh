#!/bin/bash

# Submit Batch Phase 1 PubMed Search - Empty Results Reprocessing
# Processes only the 373 drugs with empty publications_analyzed arrays

echo "🚀 Submitting Empty Results Reprocessing Jobs"
echo "🎯 Targeting only drugs with incomplete data"

# Check if empty_results_drugs.txt exists
if [[ ! -f "empty_results_drugs.txt" ]]; then
    echo "❌ Error: empty_results_drugs.txt not found."
    exit 1
fi

EMPTY_COUNT=$(wc -l < empty_results_drugs.txt)
echo "📋 Processing $EMPTY_COUNT drugs with empty results"

# Create logs directory
mkdir -p logs

# Submit the SLURM job array
echo "📤 Submitting SLURM job array..."
JOB_OUTPUT=$(sbatch batch_phase1_empty_results.slurm)

if [[ $? -eq 0 ]]; then
    echo "✅ Job array submitted successfully!"
    
    # Extract job ID from output
    JOB_ID=$(echo $JOB_OUTPUT | grep -o '[0-9]\+')
    echo "Job Array ID: $JOB_ID"
    echo "Individual jobs: ${JOB_ID}_1 through ${JOB_ID}_4"
    echo ""
    
    echo "📊 Monitor commands:"
    echo "  All jobs:     squeue -j $JOB_ID"
    echo "  Job status:   squeue -u \$USER"
    echo "  Progress:     julia identify_empty_results.jl"
    echo "  View logs:    tail -f logs/batch_phase1_empty_${JOB_ID}_1.out"
    echo ""
    
    echo "📊 This targeted job array will:"
    echo "  • Process only $EMPTY_COUNT drugs with empty results"
    echo "  • Process 95 drugs per job across 4 parallel jobs"
    echo "  • Use aggressive rate limiting (3s between drugs, 2s between batches)"
    echo "  • Smaller fetch batches (50 PMIDs) for better reliability"
    echo "  • Complete targeted reprocessing in ~6-8 hours"
    echo "  • Fill in missing publication data"
    echo ""
    
    echo "🎯 Targeted reprocessing benefits:"
    echo "  ✅ Focused scope - only incomplete files"
    echo "  ✅ Preserves existing valid data"
    echo "  ✅ Aggressive rate limiting for API compliance"
    echo "  ✅ Smaller batches for reliability"
    echo "  ✅ Complete coverage of missed publications"
else
    echo "❌ Failed to submit job array"
    exit 1
fi