#!/bin/bash

# Submit Phase 2 Step 3: Naive Llama Drug Indication Extraction Jobs

echo "=== Phase 2 Step 3: Naive Llama Extraction Submission ==="

# Create necessary directories
mkdir -p logs
mkdir -p phase2_indications_llama_naive

# Check if output directory already has results
if [ -d "phase2_indications_llama_naive" ] && [ "$(ls -A phase2_indications_llama_naive 2>/dev/null)" ]; then
    EXISTING_FILES=$(ls phase2_indications_llama_naive/*.json 2>/dev/null | wc -l)
    echo "📁 Found $EXISTING_FILES already processed drugs in phase2_indications_llama_naive/"
    echo "   Script will automatically skip these and process remaining drugs."
else
    echo "📁 No existing results found - will process all approved drugs"
fi

# Submit the SLURM job array
echo "🚀 Submitting Phase 2 Step 3 naive llama extraction jobs..."
echo "   - 30 parallel jobs processing 100 drugs each"
echo "   - Output directory: phase2_indications_llama_naive/"
echo "   - Using Llama 3.2 knowledge-based extraction"

JOB_ID=$(sbatch phase2_step3_naive_llama_extraction.slurm | awk '{print $4}')

if [ $? -eq 0 ]; then
    echo "✅ Jobs submitted successfully!"
    echo "📋 Job ID: $JOB_ID"
    echo ""
    echo "Monitor progress:"
    echo "  squeue -u \$USER"
    echo "  ls phase2_indications_llama_naive/*.json | wc -l"
    echo ""
    echo "View logs:"
    echo "  tail -f logs/phase2_step3_naive_llama_${JOB_ID}_1.out"
    echo ""
    echo "Check results:"
    echo "  ls -la phase2_indications_llama_naive/ | head -10"
else
    echo "❌ Failed to submit jobs"
    exit 1
fi