#!/bin/bash

# Submit Batch Enhanced Naive Extraction Jobs
#
# Usage:
#   ./submit_batch_enhanced_naive.sh              # Submit single batch (1-50)
#   ./submit_batch_enhanced_naive.sh 101 50       # Submit specific batch
#   ./submit_batch_enhanced_naive.sh --multiple   # Submit multiple batches automatically

# Configuration
BATCH_SIZE=200
SLURM_SCRIPT="scripts/slurm/batch_enhanced_naive_extraction.slurm"

# Create logs directory
mkdir -p logs

# Function to submit a single batch job
submit_batch() {
    local start_idx=$1
    local batch_size=$2
    
    echo "Submitting batch: drugs $start_idx to $((start_idx + batch_size - 1))"
    sbatch $SLURM_SCRIPT $start_idx $batch_size
}

# Function to get batch status
get_status() {
    echo "Getting batch processing status..."
    julia scripts/extraction/batch_enhanced_naive_extractor.jl
}

# Handle command line arguments
if [ $# -eq 0 ]; then
    # Default: submit first batch
    submit_batch 1 $BATCH_SIZE
    
elif [ "$1" = "--status" ]; then
    # Show current status
    get_status
    
elif [ "$1" = "--multiple" ]; then
    # Submit multiple batches automatically
    echo "Submitting multiple batches..."
    
    # Get status first
    get_status
    
    # Submit several batches with delays
    for i in {1..5}; do
        start_idx=$(( (i - 1) * BATCH_SIZE + 1 ))
        submit_batch $start_idx $BATCH_SIZE
        echo "Waiting 30 seconds before next submission..."
        sleep 30
    done
    
    echo "Multiple batches submitted. Check with: squeue -u \$USER"
    
elif [ $# -eq 2 ]; then
    # Submit specific batch
    submit_batch $1 $2
    
else
    echo "Usage:"
    echo "  ./submit_batch_enhanced_naive.sh                    # Submit single batch (1-200)"
    echo "  ./submit_batch_enhanced_naive.sh 201 200            # Submit specific batch"
    echo "  ./submit_batch_enhanced_naive.sh --multiple         # Submit multiple batches"
    echo "  ./submit_batch_enhanced_naive.sh --status           # Show processing status"
fi