#!/bin/bash

# Submit batch naive extraction jobs

SCRIPT_DIR="/oscar/home/isarkar/sarkarcode/thera"
SLURM_SCRIPT="$SCRIPT_DIR/scripts/slurm/batch_naive_extraction.slurm"
OUTPUT_DIR="$SCRIPT_DIR/llama_naive_extracted_indications"

# Configuration
BATCH_SIZE=200  # Process 200 drugs per job
MAX_CONCURRENT_JOBS=10  # Max jobs to have running

echo "=== Batch Naive Extraction Submission ==="
echo "Time: $(date)"

# Count total unprocessed
total_unprocessed=$(python3 -c "
import json
import os

output_dir = '$OUTPUT_DIR'
with open('approved_drugs_dict.json', 'r') as f:
    data = json.load(f)
    drugs = data['drugs']
    
count = 0
for drug in drugs:
    if not os.path.exists(f'{output_dir}/{drug}_naive_extracted_indications.json'):
        count += 1
        
print(count)
")

echo "Total unprocessed drugs: $total_unprocessed"
echo "Batch size: $BATCH_SIZE drugs per job"

# Calculate number of jobs needed
num_jobs=$(( (total_unprocessed + BATCH_SIZE - 1) / BATCH_SIZE ))
echo "Jobs needed: $num_jobs"

# Submit jobs
submitted=0
for ((i=0; i<$num_jobs; i++)); do
    start_idx=$((i * BATCH_SIZE + 1))
    
    # Check current job count
    current_jobs=$(squeue -u $USER -n batch_naive | wc -l)
    
    # Wait if too many jobs
    while [ $current_jobs -ge $MAX_CONCURRENT_JOBS ]; do
        echo "Waiting for jobs to complete (current: $current_jobs)..."
        sleep 30
        current_jobs=$(squeue -u $USER -n batch_naive | wc -l)
    done
    
    echo "Submitting job $((i+1))/$num_jobs: drugs $start_idx to $((start_idx + BATCH_SIZE - 1))"
    sbatch "$SLURM_SCRIPT" "$start_idx" "$BATCH_SIZE"
    submitted=$((submitted + 1))
    
    # Small delay
    sleep 2
done

echo ""
echo "Submitted $submitted batch jobs"
echo "Each job processes $BATCH_SIZE drugs"
echo "Monitor with: squeue -u $USER | grep batch_naive"