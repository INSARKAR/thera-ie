#!/bin/bash

# Batch processing script for all drugs using dual GPU naive extraction

# Configuration
SCRIPT_DIR="/oscar/home/isarkar/sarkarcode/thera"
SLURM_SCRIPT="$SCRIPT_DIR/scripts/slurm/dual_gpu_naive_extraction.slurm"
OUTPUT_DIR="$SCRIPT_DIR/llama_naive_extracted_indications"
APPROVED_DRUGS_FILE="$SCRIPT_DIR/approved_drugs_dict.json"
DELAY_BETWEEN_JOBS=10  # seconds

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$SCRIPT_DIR/logs"

# Function to count processed drugs
count_processed() {
    if [ -d "$OUTPUT_DIR" ]; then
        find "$OUTPUT_DIR" -name "*_naive_extracted_indications.json" | wc -l
    else
        echo 0
    fi
}

# Function to get all drug names
get_all_drugs() {
    python3 -c "
import json
with open('$APPROVED_DRUGS_FILE', 'r') as f:
    data = json.load(f)
    drugs = data['drugs']
    for drug in sorted(drugs.keys()):
        print(drug)
"
}

# Function to check if drug is already processed
is_processed() {
    local drug="$1"
    [ -f "$OUTPUT_DIR/${drug}_naive_extracted_indications.json" ]
}

# Function to get next unprocessed drug pair
get_next_pair() {
    local all_drugs=($(get_all_drugs))
    local drug1=""
    local drug2=""
    
    for drug in "${all_drugs[@]}"; do
        if ! is_processed "$drug"; then
            if [ -z "$drug1" ]; then
                drug1="$drug"
            else
                drug2="$drug"
                echo "$drug1 $drug2"
                return
            fi
        fi
    done
    
    # If only one drug left
    if [ -n "$drug1" ]; then
        echo "$drug1"
    fi
}

# Main execution
case "$1" in
    "status")
        echo "=== Dual GPU Batch Processing for All Naive Drugs ==="
        echo "Start time: $START_TIME"
        echo ""
        echo "=== Naive Processing Status ==="
        
        total_drugs=$(get_all_drugs | wc -l)
        processed_drugs=$(count_processed)
        pending_drugs=$((total_drugs - processed_drugs))
        progress=$(echo "scale=1; $processed_drugs * 100 / $total_drugs" | bc)
        
        echo "Total drugs available: $total_drugs"
        echo "Drugs processed: $processed_drugs"
        echo "Drugs pending: $pending_drugs"
        echo "Progress: $progress%"
        echo ""
        
        echo "Current jobs:"
        squeue -u $USER | grep "dual_gpu_naive"
        echo ""
        
        echo "Recent completions:"
        ls -lt "$OUTPUT_DIR"/*.json 2>/dev/null | head -5
        ;;
        
    "start"|"")
        START_TIME=$(date)
        echo "=== Starting Dual GPU Batch Processing for All Naive Drugs ==="
        echo "Start time: $START_TIME"
        echo "Total drugs to process: $(get_all_drugs | wc -l)"
        echo "Delay between jobs: ${DELAY_BETWEEN_JOBS}s"
        echo ""
        
        job_count=0
        
        while true; do
            # Get next drug pair
            next_pair=$(get_next_pair)
            
            if [ -z "$next_pair" ]; then
                echo "All drugs have been processed or submitted!"
                break
            fi
            
            # Parse the pair
            read -r drug1 drug2 <<< "$next_pair"
            
            if [ -z "$drug2" ]; then
                # Only one drug left - run it alone
                echo "Submitting final drug: $drug1"
                sbatch "$SLURM_SCRIPT" "$drug1" "$drug1"
                job_count=$((job_count + 1))
                break
            else
                # Submit drug pair
                echo "Submitting job $((job_count + 1)): $drug1 and $drug2"
                sbatch "$SLURM_SCRIPT" "$drug1" "$drug2"
                job_count=$((job_count + 1))
                
                # Small delay between submissions
                sleep $DELAY_BETWEEN_JOBS
            fi
            
            # Check job limit (max 20 jobs in queue at once)
            while [ $(squeue -u $USER | grep -c "dual_gpu_naive") -ge 20 ]; do
                echo "Job queue full, waiting..."
                sleep 30
            done
        done
        
        echo ""
        echo "=== Batch submission complete ==="
        echo "Total jobs submitted: $job_count"
        echo "Monitor progress with: $0 status"
        ;;
        
    *)
        echo "Usage: $0 [start|status]"
        echo "  start  - Start processing all drugs (default)"
        echo "  status - Show current processing status"
        exit 1
        ;;
esac