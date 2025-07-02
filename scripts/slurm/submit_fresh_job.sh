#!/bin/bash

# Submit fresh Levothyroxine extraction job

echo "=== Submitting Fresh Levothyroxine Extraction Job ==="
echo "Time: $(date)"

# Make sure we're in the right directory
cd /users/isarkar/sarkarcode/thera

# Ensure logs directory exists
mkdir -p logs

# Submit the job
echo "Submitting SLURM job..."
sbatch fresh_extraction.slurm

if [ $? -eq 0 ]; then
    echo "✅ Job submitted successfully!"
    echo ""
    echo "Monitor with:"
    echo "  squeue -u \$USER"
    echo "  tail -f logs/fresh_extraction_*.out"
    echo ""
    echo "Check results in:"
    echo "  /users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/"
else
    echo "❌ Failed to submit job"
    exit 1
fi
