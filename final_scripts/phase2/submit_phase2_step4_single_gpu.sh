#!/bin/bash

# Submit Phase 2 Step 4 using single GPU approach with batches
# Each job uses 1 GPU and processes 10 drugs

echo "=== Phase 2 Step 4: Single GPU Batch Submission ==="
echo "Timestamp: $(date)"

# Configuration
DRUGS_PER_JOB=10

# Check prerequisites
echo "🔍 Checking prerequisites..."

if [[ ! -f "scripts/slurm/phase2_step4_single_gpu_batch.slurm" ]]; then
    echo "❌ Single GPU batch SLURM script not found"
    exit 1
fi

if [[ ! -f "scripts/extraction/phase2_step4_pubmed_llama_extractor.jl" ]]; then
    echo "❌ Extractor script not found"
    exit 1
fi

# Count drugs and calculate job requirements
TOTAL_DRUGS=$(ls phase1_drug_pubmed_mesh/*.json | wc -l)
EXISTING_RESULTS=$(ls phase2_indications_llama_pubmed/*_pubmed_llama_indications.json 2>/dev/null | wc -l)
REMAINING=$(( TOTAL_DRUGS - EXISTING_RESULTS ))

# Calculate number of jobs needed
JOBS_NEEDED=$(( (TOTAL_DRUGS + DRUGS_PER_JOB - 1) / DRUGS_PER_JOB ))

echo "✅ Prerequisites check passed"
echo ""
echo "📊 Analysis:"
echo "  • Total drugs: $TOTAL_DRUGS"
echo "  • Existing results: $EXISTING_RESULTS"
echo "  • Remaining to process: $REMAINING"
echo ""
echo "🚀 Job Configuration:"
echo "  • Drugs per job: $DRUGS_PER_JOB"
echo "  • Jobs needed: $JOBS_NEEDED"
echo "  • Resource per job: 1 GPU, 8GB RAM, 1 CPU"
echo "  • Time per job: 2 hours"
echo "  • Total GPU hours: $((JOBS_NEEDED * 2))"
echo "  • Max concurrent jobs: ~10-20 (based on GPU availability)"

if [ $REMAINING -le 0 ]; then
    echo ""
    echo "✅ All drugs already processed!"
    exit 0
fi

# Create directories
mkdir -p phase2_indications_llama_pubmed
mkdir -p logs

# Confirm submission
echo ""
read -p "Submit $JOBS_NEEDED single GPU batch jobs for Phase 2 Step 4? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Submission cancelled"
    exit 1
fi

# Submit jobs
echo "📤 Submitting $JOBS_NEEDED single GPU batch jobs..."
JOB_ID=$(sbatch --array=1-$JOBS_NEEDED scripts/slurm/phase2_step4_single_gpu_batch.slurm | awk '{print $4}')

if [ $? -eq 0 ] && [ ! -z "$JOB_ID" ]; then
    echo "✅ Successfully submitted job array: $JOB_ID"
    echo ""
    echo "📋 Job Management Commands:"
    echo "  • Check status: squeue -u \$USER"
    echo "  • Check array: squeue -j $JOB_ID"
    echo "  • Cancel all: scancel $JOB_ID"
    echo "  • View sample log: tail logs/phase2_pubmed_batch_${JOB_ID}_1.out"
    echo ""
    echo "📊 Progress Monitoring:"
    echo "  • Check progress: ls phase2_indications_llama_pubmed/ | wc -l"
    echo "  • Monitor: watch 'ls phase2_indications_llama_pubmed/ | wc -l'"
    echo "  • Expected final count: $TOTAL_DRUGS"
    echo ""
    echo "🔔 $JOBS_NEEDED single GPU batch jobs submitted!"
    echo "💡 Each job processes $DRUGS_PER_JOB drugs on 1 GPU"
    echo "🎯 Output files should start appearing as jobs complete"
    echo ""
    echo "⏱️ Estimated completion: $((JOBS_NEEDED * 2 / 10)) hours (assuming 10 concurrent jobs)"
else
    echo "❌ Failed to submit jobs"
    exit 1
fi