#!/bin/bash

# Submit DrugBank indication extraction job
# Usage: ./submit_drugbank_job.sh [drug_name]
# If no drug name provided, processes all drugs

DRUG_NAME=${1:-""}

echo "=== Submitting DrugBank Indication Extraction Job ==="
if [ -n "$DRUG_NAME" ]; then
    echo "Processing single drug: $DRUG_NAME"
    
    # Check if drug exists in approved_drugs_dict.json
    if ! grep -q "\"$DRUG_NAME\":" approved_drugs_dict.json; then
        echo "❌ Drug '$DRUG_NAME' not found in approved_drugs_dict.json"
        echo "Available drugs (first 10):"
        jq -r '.drugs | keys[]' approved_drugs_dict.json | head -10
        exit 1
    fi
    
    export DRUGBANK_SINGLE_DRUG="$DRUG_NAME"
else
    echo "Processing all drugs in approved_drugs_dict.json"
    total_drugs=$(jq '.drugs | length' approved_drugs_dict.json)
    echo "Total drugs to process: $total_drugs"
fi

echo ""

# Submit the job
JOB_ID=$(sbatch drugbank_extraction.slurm | grep -o '[0-9]\+$')

if [ ! -z "$JOB_ID" ]; then
    echo "✅ Job submitted successfully!"
    echo "Job ID: $JOB_ID"
    echo ""
    echo "Monitor with:"
    echo "  squeue -u $USER"
    echo "  tail -f logs/drugbank_extraction_${JOB_ID}.out"
    echo ""
    echo "Expected output directory:"
    echo "  llama_drugbank_extracted_indications/"
    if [ -n "$DRUG_NAME" ]; then
        echo "  Expected file: ${DRUG_NAME}_drugbank_extracted_indications.json"
    fi
else
    echo "❌ Failed to submit job"
    exit 1
fi