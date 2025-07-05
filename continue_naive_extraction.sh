#!/bin/bash

# Continue naive extraction from where it left off

SCRIPT_DIR="/oscar/home/isarkar/sarkarcode/thera"
SLURM_SCRIPT="$SCRIPT_DIR/scripts/slurm/dual_gpu_naive_extraction.slurm"
OUTPUT_DIR="$SCRIPT_DIR/llama_naive_extracted_indications"
APPROVED_DRUGS_FILE="$SCRIPT_DIR/approved_drugs_dict.json"
DELAY_BETWEEN_JOBS=10

echo "=== Continuing Naive Extraction ==="
echo "Current time: $(date)"

# Count processed
processed=$(ls "$OUTPUT_DIR"/*.json 2>/dev/null | wc -l)
echo "Already processed: $processed drugs"

# Submit next 50 jobs
submitted=0
max_jobs=50

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
for i in range(0, min(len(unprocessed), $max_jobs * 2), 2):
    if i+1 < len(unprocessed):
        print(f'{unprocessed[i]}|{unprocessed[i+1]}')
    else:
        print(f'{unprocessed[i]}|{unprocessed[i]}')
" | while IFS='|' read -r drug1 drug2; do
    if [ -n "$drug1" ]; then
        echo "Submitting: $drug1 and $drug2"
        sbatch "$SLURM_SCRIPT" "$drug1" "$drug2"
        submitted=$((submitted + 1))
        sleep $DELAY_BETWEEN_JOBS
    fi
done

echo ""
echo "Submitted $submitted jobs"
echo "Run './run_all_drugs_naive_dual_gpu_v2.sh status' to check progress"