#!/bin/bash

# Helper script to submit a single dual GPU job for specific drugs

if [ $# -lt 1 ]; then
    echo "Usage: $0 drug1 [drug2]"
    exit 1
fi

DRUG1="$1"
DRUG2="${2:-$1}"  # If no second drug provided, use the first drug

sbatch scripts/slurm/dual_gpu_naive_extraction.slurm "$DRUG1" "$DRUG2"