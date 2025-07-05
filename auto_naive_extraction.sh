#!/bin/bash

# Automated naive extraction that continuously submits jobs until all drugs are processed

SCRIPT_DIR="/oscar/home/isarkar/sarkarcode/thera"
SLURM_SCRIPT="$SCRIPT_DIR/scripts/slurm/dual_gpu_naive_extraction.slurm"
OUTPUT_DIR="$SCRIPT_DIR/llama_naive_extracted_indications"
APPROVED_DRUGS_FILE="$SCRIPT_DIR/approved_drugs_dict.json"
DELAY_BETWEEN_JOBS=10
MAX_CONCURRENT_JOBS=20
BATCH_SIZE=50  # Jobs per batch
LOG_FILE="$SCRIPT_DIR/logs/auto_naive_extraction.log"

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to count processed drugs
count_processed() {
    ls "$OUTPUT_DIR"/*.json 2>/dev/null | wc -l
}

# Function to count total drugs
count_total() {
    python3 -c "
import json
with open('$APPROVED_DRUGS_FILE', 'r') as f:
    data = json.load(f)
    print(len(data['drugs']))
"
}

# Function to get unprocessed drug pairs
get_unprocessed_pairs() {
    local max_pairs=$1
    python3 -c "
import json
import os

output_dir = '$OUTPUT_DIR'
with open('$APPROVED_DRUGS_FILE', 'r') as f:
    data = json.load(f)
    drugs = sorted(data['drugs'].keys())
    
unprocessed = []
for drug in drugs:
    if not os.path.exists(f'{output_dir}/{drug}_naive_extracted_indications.json'):
        unprocessed.append(drug)

# Print pairs up to max_pairs
count = 0
for i in range(0, len(unprocessed), 2):
    if count >= $max_pairs:
        break
    if i+1 < len(unprocessed):
        print(f'{unprocessed[i]}|{unprocessed[i+1]}')
    else:
        print(f'{unprocessed[i]}|{unprocessed[i]}')
    count += 1
"
}

# Function to count current jobs in queue
count_jobs() {
    local count=$(squeue -u $USER 2>/dev/null | grep "dual_gpu_naive" | wc -l)
    echo ${count:-0}
}

# Main processing loop
main() {
    log "=== Starting Automated Naive Extraction ==="
    
    total_drugs=$(count_total)
    log "Total drugs to process: $total_drugs"
    
    while true; do
        processed=$(count_processed)
        pending=$((total_drugs - processed))
        progress=$(echo "scale=1; $processed * 100 / $total_drugs" | bc)
        
        log "Progress: $processed/$total_drugs ($progress%) - $pending remaining"
        
        # Check if all drugs are processed
        if [ "$pending" -eq 0 ]; then
            log "🎉 All drugs have been processed!"
            break
        fi
        
        # Check current job count
        current_jobs=$(count_jobs)
        log "Current jobs in queue: $current_jobs"
        
        # Wait if we have too many jobs
        if [ "$current_jobs" -ge "$MAX_CONCURRENT_JOBS" ]; then
            log "Job queue full ($current_jobs/$MAX_CONCURRENT_JOBS), waiting 60 seconds..."
            sleep 60
            continue
        fi
        
        # Calculate how many jobs to submit
        available_slots=$((MAX_CONCURRENT_JOBS - current_jobs))
        if [ "$available_slots" -lt "$BATCH_SIZE" ]; then
            jobs_to_submit=$available_slots
        else
            jobs_to_submit=$BATCH_SIZE
        fi
        
        if [ "$jobs_to_submit" -le 0 ]; then
            log "No available slots, waiting 30 seconds..."
            sleep 30
            continue
        fi
        
        log "Submitting $jobs_to_submit jobs..."
        
        # Submit jobs
        submitted=0
        get_unprocessed_pairs $jobs_to_submit | while IFS='|' read -r drug1 drug2; do
            if [ -n "$drug1" ]; then
                log "Submitting: $drug1 and $drug2"
                sbatch "$SLURM_SCRIPT" "$drug1" "$drug2" >/dev/null
                submitted=$((submitted + 1))
                sleep $DELAY_BETWEEN_JOBS
            fi
        done
        
        if [ "$submitted" -eq 0 ]; then
            log "No jobs submitted, waiting 30 seconds..."
            sleep 30
        else
            log "Submitted $submitted jobs"
            # Wait a bit before checking again
            sleep 60
        fi
    done
    
    log "=== Automated Naive Extraction Complete ==="
}

# Handle interruption
trap 'log "Script interrupted by user"; exit 1' INT TERM

# Start background monitoring
case "$1" in
    "start"|"")
        log "Starting automated processing..."
        main
        ;;
    "status")
        total_drugs=$(count_total)
        processed=$(count_processed)
        pending=$((total_drugs - processed))
        progress=$(echo "scale=1; $processed * 100 / $total_drugs" | bc)
        current_jobs=$(count_jobs)
        
        echo "=== Automated Naive Extraction Status ==="
        echo "Total drugs: $total_drugs"
        echo "Processed: $processed"
        echo "Pending: $pending"
        echo "Progress: $progress%"
        echo "Current jobs: $current_jobs"
        echo ""
        echo "Recent log entries:"
        tail -10 "$LOG_FILE" 2>/dev/null || echo "No log file found"
        ;;
    "log")
        if [ -f "$LOG_FILE" ]; then
            tail -f "$LOG_FILE"
        else
            echo "No log file found at $LOG_FILE"
        fi
        ;;
    *)
        echo "Usage: $0 [start|status|log]"
        echo "  start  - Start automated processing (default)"
        echo "  status - Show current status"
        echo "  log    - Follow the log file"
        exit 1
        ;;
esac