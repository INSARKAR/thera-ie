#!/bin/bash

# Submit optimized Levothyroxine extraction job

echo "=== Submitting OPTIMIZED Levothyroxine Extraction Job ==="
echo "Time: $(date)"

# Make sure we're in the right directory
cd /users/isarkar/sarkarcode/thera

# Ensure logs directory exists
mkdir -p logs

# Show current job status first
echo "Current running jobs:"
squeue -u $USER

echo ""
echo "🚀 OPTIMIZATIONS in this version:"
echo "   - 10x faster: 0.05s delay (vs 0.5s)"
echo "   - Shorter prompts for faster processing"
echo "   - Reduced API timeouts"
echo "   - Retry logic for failed calls"
echo "   - Periodic checkpoints every 500 publications"
echo "   - Less verbose logging"
echo "   - Estimated 10x speed improvement"

echo ""
read -p "Submit optimized job? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Submit the job
    echo "Submitting optimized SLURM job..."
    sbatch optimized_extraction.slurm
    
    if [ $? -eq 0 ]; then
        echo "✅ Optimized job submitted successfully!"
        echo ""
        echo "Monitor with:"
        echo "  squeue -u \$USER"
        echo "  tail -f logs/optimized_extraction_*.out"
        echo ""
        echo "Expected processing time: ~30-60 minutes (vs 5+ hours original)"
        echo "Check intermediate results:"
        echo "  ls -la llama_pubmed_extracted_indications/Levothyroxine_checkpoint_*.json"
    else
        echo "❌ Failed to submit job"
        exit 1
    fi
else
    echo "Job submission cancelled."
fi
