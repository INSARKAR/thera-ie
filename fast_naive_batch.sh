#!/bin/bash

# Fast batch submission for naive extraction - submit all at once

SCRIPT_DIR="/oscar/home/isarkar/sarkarcode/thera"
SLURM_SCRIPT="$SCRIPT_DIR/scripts/slurm/dual_gpu_naive_extraction.slurm"
OUTPUT_DIR="$SCRIPT_DIR/llama_naive_extracted_indications"
APPROVED_DRUGS_FILE="$SCRIPT_DIR/approved_drugs_dict.json"

echo "=== Fast Batch Naive Extraction ==="
echo "Time: $(date)"

# Get all unprocessed drugs
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

# Print pairs
for i in range(0, len(unprocessed), 2):
    if i+1 < len(unprocessed):
        print(f'{unprocessed[i]}|{unprocessed[i+1]}')
    else:
        print(f'{unprocessed[i]}|{unprocessed[i]}')
" > /tmp/unprocessed_drugs.txt

total_pairs=$(wc -l < /tmp/unprocessed_drugs.txt)
echo "Total pairs to process: $total_pairs"

# Submit all jobs with minimal delay
count=0
while IFS='|' read -r drug1 drug2; do
    if [ -n "$drug1" ]; then
        sbatch "$SLURM_SCRIPT" "$drug1" "$drug2" >/dev/null
        count=$((count + 1))
        
        # Brief pause every 100 jobs to avoid overwhelming scheduler
        if [ $((count % 100)) -eq 0 ]; then
            echo "Submitted $count pairs..."
            sleep 2
        fi
    fi
done < /tmp/unprocessed_drugs.txt

echo ""
echo "Submitted $count job pairs"
echo "Monitor with: squeue -u $USER | grep -c dual_gpu_naive"

rm -f /tmp/unprocessed_drugs.txt