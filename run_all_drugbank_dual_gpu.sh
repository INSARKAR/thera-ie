#!/bin/bash

# Batch processing script for all DrugBank drugs using dual GPU system
# Processes drugs in pairs using the dual GPU setup

echo "=== Dual GPU Batch Processing for All DrugBank Drugs ==="
echo "Start time: $(date)"
echo ""

# Configuration
APPROVED_DRUGS_FILE="/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.json"
OUTPUT_DIR="/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications"
BATCH_LOG_DIR="logs/drugbank_batch_processing"
MAX_CONCURRENT_JOBS=3
DELAY_BETWEEN_SUBMISSIONS=10  # seconds

# Create directories
mkdir -p "$BATCH_LOG_DIR"
mkdir -p "$OUTPUT_DIR"

# Function to get list of all available drugs
get_all_drugs() {
    jq -r '.drugs | keys[]' "$APPROVED_DRUGS_FILE" | sort
}

# Function to get list of already processed drugs
get_processed_drugs() {
    if [ -d "$OUTPUT_DIR" ]; then
        ls "$OUTPUT_DIR"/*_drugbank_extracted_indications.json 2>/dev/null | \
        xargs -I {} basename {} _drugbank_extracted_indications.json | sort
    fi
}

# Function to get pending drugs (not yet processed)
get_pending_drugs() {
    comm -23 <(get_all_drugs) <(get_processed_drugs)
}

# Function to check if a job is still running
is_job_running() {
    local jobid=$1
    squeue -j "$jobid" -h &>/dev/null
}

# Function to wait for job completion
wait_for_job() {
    local jobid=$1
    local drug1=$2
    local drug2=$3
    
    echo "Waiting for job $jobid ($drug1 + $drug2) to complete..."
    
    while is_job_running "$jobid"; do
        sleep 30
    done
    
    # Check job status
    if [ -f "logs/dual_gpu_drugbank_${jobid}.out" ]; then
        if grep -q "✅ All extractions completed successfully!" "logs/dual_gpu_drugbank_${jobid}.out"; then
            echo "✅ Job $jobid completed successfully"
            return 0
        else
            echo "❌ Job $jobid failed"
            return 1
        fi
    else
        echo "⚠️  Job $jobid - log file not found"
        return 1
    fi
}

# Function to submit a dual GPU job
submit_dual_gpu_job() {
    local drug1=$1
    local drug2=$2
    
    echo "Submitting dual GPU job: $drug1 + $drug2"
    
    # Set environment variables and submit job
    export DRUGBANK_DRUG1="$drug1"
    export DRUGBANK_DRUG2="$drug2"
    
    local jobid=$(sbatch dual_gpu_drugbank_extraction.slurm | grep -o '[0-9]\+$')
    
    if [ ! -z "$jobid" ]; then
        echo "  Job ID: $jobid"
        echo "$jobid:$drug1:$drug2:$(date)" >> "$BATCH_LOG_DIR/submitted_jobs.log"
        echo "$jobid"
    else
        echo "  ❌ Failed to submit job"
        return 1
    fi
}

# Function to process drugs in batches
process_all_drugs() {
    local pending_drugs=($(get_pending_drugs))
    local total_pending=${#pending_drugs[@]}
    local total_pairs=$((($total_pending + 1) / 2))
    
    echo "📊 Drugs pending processing: $total_pending"
    echo "📊 Estimated dual GPU jobs needed: $total_pairs"
    echo ""
    
    if [ $total_pending -eq 0 ]; then
        echo "✅ All drugs have been processed!"
        return 0
    fi
    
    local current_jobs=()
    local completed_pairs=0
    local failed_pairs=0
    
    # Process drugs in pairs
    for ((i=0; i<$total_pending; i+=2)); do
        drug1="${pending_drugs[$i]}"
        drug2="${pending_drugs[$((i+1))]:-}"  # Second drug might not exist for odd numbers
        
        # Wait if we have too many concurrent jobs
        while [ ${#current_jobs[@]} -ge $MAX_CONCURRENT_JOBS ]; do
            echo "Waiting for running jobs to complete (currently ${#current_jobs[@]} running)..."
            sleep 30
            
            # Check and remove completed jobs
            for j in "${!current_jobs[@]}"; do
                job_info="${current_jobs[$j]}"
                jobid=$(echo "$job_info" | cut -d: -f1)
                job_drug1=$(echo "$job_info" | cut -d: -f2)
                job_drug2=$(echo "$job_info" | cut -d: -f3)
                
                if ! is_job_running "$jobid"; then
                    # Job completed, check status
                    if wait_for_job "$jobid" "$job_drug1" "$job_drug2"; then
                        ((completed_pairs++))
                    else
                        ((failed_pairs++))
                    fi
                    
                    # Remove from current jobs array
                    unset current_jobs[$j]
                    current_jobs=("${current_jobs[@]}")  # Reindex array
                fi
            done
        done
        
        # Submit new job
        if [ -n "$drug2" ]; then
            # Pair of drugs
            jobid=$(submit_dual_gpu_job "$drug1" "$drug2")
            if [ $? -eq 0 ]; then
                current_jobs+=("$jobid:$drug1:$drug2")
            else
                echo "❌ Failed to submit job for $drug1 + $drug2"
                ((failed_pairs++))
            fi
        else
            # Single drug (odd number) - still submit but with empty second drug
            echo "Processing single remaining drug: $drug1"
            jobid=$(submit_dual_gpu_job "$drug1" "")
            if [ $? -eq 0 ]; then
                current_jobs+=("$jobid:$drug1:")
            else
                echo "❌ Failed to submit job for $drug1"
                ((failed_pairs++))
            fi
        fi
        
        # Progress update
        local pairs_submitted=$(((i/2) + 1))
        echo "Progress: $pairs_submitted/$total_pairs pairs submitted"
        echo ""
        
        # Delay between submissions to avoid overwhelming the queue
        if [ $i -lt $((total_pending - 2)) ]; then
            echo "Waiting $DELAY_BETWEEN_SUBMISSIONS seconds before next submission..."
            sleep $DELAY_BETWEEN_SUBMISSIONS
        fi
    done
    
    # Wait for all remaining jobs to complete
    echo "Waiting for all remaining jobs to complete..."
    for job_info in "${current_jobs[@]}"; do
        jobid=$(echo "$job_info" | cut -d: -f1)
        job_drug1=$(echo "$job_info" | cut -d: -f2)
        job_drug2=$(echo "$job_info" | cut -d: -f3)
        
        if wait_for_job "$jobid" "$job_drug1" "$job_drug2"; then
            ((completed_pairs++))
        else
            ((failed_pairs++))
        fi
    done
    
    echo ""
    echo "=== Batch Processing Complete ==="
    echo "✅ Successfully completed: $completed_pairs pairs"
    echo "❌ Failed: $failed_pairs pairs"
    echo "📊 Total drugs processed: $((completed_pairs * 2))"
    echo "End time: $(date)"
}

# Function to show status
show_status() {
    local total_drugs=$(get_all_drugs | wc -l)
    local processed_drugs=$(get_processed_drugs | wc -l)
    local pending_drugs=$(get_pending_drugs | wc -l)
    
    echo "=== DrugBank Processing Status ==="
    echo "Total drugs available: $total_drugs"
    echo "Drugs processed: $processed_drugs"
    echo "Drugs pending: $pending_drugs"
    echo "Progress: $(echo "scale=1; $processed_drugs * 100 / $total_drugs" | bc -l)%"
    echo ""
    
    # Show current running jobs
    echo "Current jobs:"
    squeue -u $USER -o "%.10i %.12j %.8T %.10M %.6D %R" | grep drugbank
    echo ""
    
    # Show recent completions
    if ls "$OUTPUT_DIR"/*.json &>/dev/null; then
        echo "Recent completions:"
        ls -lt "$OUTPUT_DIR"/*.json | head -5
    fi
}

# Main execution
case "${1:-run}" in
    "status")
        show_status
        ;;
    "run")
        process_all_drugs
        ;;
    "help")
        echo "Usage: $0 [command]"
        echo "Commands:"
        echo "  run     - Process all pending drugs (default)"
        echo "  status  - Show current processing status"
        echo "  help    - Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac