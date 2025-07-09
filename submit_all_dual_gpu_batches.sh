#!/bin/bash

# Submit All Remaining Drugs Using Dual GPU Batch Processing
#
# This script automatically queues up all remaining drugs for processing
# using dual GPU batch jobs with 400 drugs per job (200 per GPU)

# Configuration
BATCH_SIZE=400
SLURM_SCRIPT="scripts/slurm/dual_gpu_batch_enhanced_naive.slurm"
DELAY_BETWEEN_JOBS=60  # seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create logs directory
mkdir -p logs

echo -e "${BLUE}=== Dual GPU Batch Enhanced Naive Extraction Submission ===${NC}"
echo "Date: $(date)"
echo "Batch size: $BATCH_SIZE drugs per job (200 per GPU)"
echo "SLURM script: $SLURM_SCRIPT"
echo ""

# Function to get processing status
get_processing_status() {
    echo -e "${BLUE}Getting current processing status...${NC}"
    julia scripts/extraction/dual_gpu_batch_enhanced_naive.jl | grep -E "(Total drugs|Processed|Remaining)"
}

# Function to calculate batches needed
calculate_batches() {
    # Get the number of remaining drugs
    local remaining=$(julia scripts/extraction/dual_gpu_batch_enhanced_naive.jl | grep "Remaining:" | grep -oE '[0-9]+')
    if [ -z "$remaining" ]; then
        echo "0"
        return
    fi
    
    # Calculate number of batches needed
    local batches=$(( (remaining + BATCH_SIZE - 1) / BATCH_SIZE ))
    echo "$batches"
}

# Function to submit a batch job
submit_batch_job() {
    local start_idx=$1
    local job_num=$2
    local total_jobs=$3
    
    echo -e "${YELLOW}Submitting job $job_num/$total_jobs: drugs $start_idx to $((start_idx + BATCH_SIZE - 1))${NC}"
    
    local job_id=$(sbatch --parsable $SLURM_SCRIPT $start_idx $BATCH_SIZE)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Job submitted successfully: $job_id${NC}"
        echo "   Start index: $start_idx"
        echo "   Batch size: $BATCH_SIZE"
        echo "   Expected processing time: ~2 hours"
        return 0
    else
        echo -e "${RED}❌ Failed to submit job${NC}"
        return 1
    fi
}

# Function to show job queue status
show_queue_status() {
    echo -e "${BLUE}\\nCurrent job queue status:${NC}"
    squeue -u $USER -o "%.10i %.20j %.8T %.10M %.6D %.20S" | head -20
    local job_count=$(squeue -u $USER -h | wc -l)
    echo "Total jobs in queue: $job_count"
}

# Main execution
main() {
    # Get current status
    get_processing_status
    
    # Calculate how many batches we need
    batches_needed=$(calculate_batches)
    
    if [ "$batches_needed" -eq 0 ]; then
        echo -e "${GREEN}✅ All drugs have been processed!${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Batches needed: $batches_needed${NC}"
    echo -e "${YELLOW}Estimated total time: ~$((batches_needed * 2)) hours${NC}"
    echo -e "${YELLOW}Effective processing rate: ~200 drugs per GPU hour${NC}"
    echo ""
    
    # Confirm with user
    read -p "Submit all $batches_needed batch jobs? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Submission cancelled."
        return 1
    fi
    
    # Get starting index (number of already processed drugs + 1)
    local processed=$(julia scripts/extraction/dual_gpu_batch_enhanced_naive.jl | grep "Processed:" | grep -oE '[0-9]+')
    local start_idx=$((processed + 1))
    
    echo -e "${BLUE}Starting submission of $batches_needed jobs...${NC}"
    echo "First job will start at drug index: $start_idx"
    echo ""
    
    # Submit all batch jobs
    local successful_jobs=0
    local failed_jobs=0
    
    for ((job_num=1; job_num<=batches_needed; job_num++)); do
        local current_start=$((start_idx + (job_num - 1) * BATCH_SIZE))
        
        if submit_batch_job $current_start $job_num $batches_needed; then
            ((successful_jobs++))
        else
            ((failed_jobs++))
        fi
        
        # Add delay between submissions to avoid overwhelming the scheduler
        if [ $job_num -lt $batches_needed ]; then
            echo "Waiting $DELAY_BETWEEN_JOBS seconds before next submission..."
            sleep $DELAY_BETWEEN_JOBS
        fi
    done
    
    echo ""
    echo -e "${BLUE}=== Submission Complete ===${NC}"
    echo -e "${GREEN}✅ Successfully submitted: $successful_jobs jobs${NC}"
    
    if [ $failed_jobs -gt 0 ]; then
        echo -e "${RED}❌ Failed to submit: $failed_jobs jobs${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Monitor job progress: squeue -u \$USER"
    echo "2. Check job outputs: tail -f logs/dual_gpu_batch_enhanced_*.out"
    echo "3. Check processing status: ./submit_all_dual_gpu_batches.sh --status"
    echo "4. Estimated completion time: $(date -d "+$((batches_needed * 2)) hours")"
    
    # Show current queue
    show_queue_status
}

# Handle command line arguments
case "${1:-}" in
    --status)
        echo -e "${BLUE}Current Processing Status:${NC}"
        get_processing_status
        echo ""
        show_queue_status
        ;;
    --help)
        echo "Usage: $0 [--status | --help]"
        echo ""
        echo "Options:"
        echo "  (no args)  Submit all remaining drugs for processing"
        echo "  --status   Show current processing and queue status"
        echo "  --help     Show this help message"
        ;;
    *)
        main
        ;;
esac