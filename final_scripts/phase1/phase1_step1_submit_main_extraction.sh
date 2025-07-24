#!/bin/bash

# Submit Batch Phase 1 PubMed Search Cleanup
# Fresh extraction of all 2,915 drugs with fixed worker

echo "🚀 Submitting Batch Phase1 PubMed Search Cleanup"
echo "🔧 Fresh extraction with all issues fixed"

# Check if all_drugs_for_cleanup.txt exists
if [[ ! -f "all_drugs_for_cleanup.txt" ]]; then
    echo "❌ Error: all_drugs_for_cleanup.txt not found."
    exit 1
fi

DRUG_COUNT=$(wc -l < all_drugs_for_cleanup.txt)
echo "📋 Processing all $DRUG_COUNT drugs from scratch"

# Create logs directory
mkdir -p logs

# Submit the SLURM job array
echo "📤 Submitting SLURM job array..."
JOB_OUTPUT=$(sbatch batch_phase1_pubmed_cleanup.slurm)

if [[ $? -eq 0 ]]; then
    echo "✅ Job array submitted successfully!"
    
    # Extract job ID from output
    JOB_ID=$(echo $JOB_OUTPUT | grep -o '[0-9]\+')
    echo "Job Array ID: $JOB_ID"
    echo "Individual jobs: ${JOB_ID}_1 through ${JOB_ID}_8"
    echo ""
    
    echo "📊 Monitor commands:"
    echo "  All jobs:     squeue -j $JOB_ID"
    echo "  Job status:   squeue -u \$USER"
    echo "  Progress:     ls phase1_drug_pubmed_refs/*.json | wc -l"
    echo "  View logs:    tail -f logs/batch_phase1_cleanup_${JOB_ID}_1.out"
    echo ""
    
    echo "📊 This cleanup job array will:"
    echo "  • Process all $DRUG_COUNT drugs across 8 parallel jobs"
    echo "  • Process 370 drugs per job with conservative rate limiting"
    echo "  • Retrieve ALL publications per drug with ALL MeSH descriptors"
    echo "  • Complete fresh extraction in ~10-12 hours"
    echo "  • Generate clean, complete publication dataset"
    echo ""
    
    echo "🔍 Fresh extraction benefits:"
    echo "  ✅ Fixed worker - no variable scope issues"
    echo "  ✅ Conservative batching - 370 drugs per job"
    echo "  ✅ API-friendly - proper rate limiting throughout"
    echo "  ✅ Complete coverage - all 2,915 approved drugs"
    echo "  ✅ Comprehensive data - ALL MeSH descriptors without filtering"
else
    echo "❌ Failed to submit job array"
    exit 1
fi