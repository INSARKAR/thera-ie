#!/bin/bash

# Submit dual GPU Llama extraction job
# Usage: ./submit_dual_gpu_job.sh [drug1] [drug2]
# Default: Levothyroxine and Metformin

DRUG1=${1:-"Levothyroxine"}
DRUG2=${2:-"Metformin"}

echo "=== Submitting Dual GPU Llama Extraction Job ==="
echo "Drug 1 (GPU 0): $DRUG1"
echo "Drug 2 (GPU 1): $DRUG2"
echo ""

# Check if drug files exist
DRUG1_FILE="/users/isarkar/sarkarcode/thera/drug_pubmed_refs/${DRUG1}.json"
DRUG2_FILE="/users/isarkar/sarkarcode/thera/drug_pubmed_refs/${DRUG2}.json"

if [ ! -f "$DRUG1_FILE" ]; then
    echo "❌ Drug file not found: $DRUG1_FILE"
    echo "Available drugs:"
    ls -1 /users/isarkar/sarkarcode/thera/drug_pubmed_refs/*.json | head -10
    exit 1
fi

if [ ! -f "$DRUG2_FILE" ]; then
    echo "❌ Drug file not found: $DRUG2_FILE"
    echo "Available drugs:"
    ls -1 /users/isarkar/sarkarcode/thera/drug_pubmed_refs/*.json | head -10
    exit 1
fi

echo "✓ Both drug files found"

# Submit the job
export LLAMA_DRUG1="$DRUG1"
export LLAMA_DRUG2="$DRUG2"

JOB_ID=$(sbatch dual_gpu_llama_extraction.slurm | grep -o '[0-9]\+$')

if [ ! -z "$JOB_ID" ]; then
    echo "✅ Job submitted successfully!"
    echo "Job ID: $JOB_ID"
    echo ""
    echo "Monitor with:"
    echo "  squeue -u $USER"
    echo "  tail -f logs/dual_gpu_llama_extraction_${JOB_ID}.out"
    echo ""
    echo "Expected output files:"
    echo "  llama_pubmed_extracted_indications/${DRUG1}_llama_extracted_indications.json"
    echo "  llama_pubmed_extracted_indications/${DRUG2}_llama_extracted_indications.json"
else
    echo "❌ Failed to submit job"
    exit 1
fi