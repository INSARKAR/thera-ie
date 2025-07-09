#!/bin/bash

# Distribute naive extraction across multiple single-GPU SLURM jobs

echo "🚀 Distributing Naive Extraction Across Multiple GPUs"
echo "=" ^60

# Calculate missing extractions
TOTAL_DRUGS=$(julia -e "include(\"approved_drugs_dict.jl\"); println(length(APPROVED_DRUGS_DICT))")
EXISTING_NAIVE=$(ls llama_naive_extracted_indications/ | wc -l)
MISSING=$((TOTAL_DRUGS - EXISTING_NAIVE))

echo "📊 Current Status:"
echo "  Total drugs: $TOTAL_DRUGS"
echo "  Existing naive extractions: $EXISTING_NAIVE"
echo "  Missing extractions: $MISSING"

if [ $MISSING -eq 0 ]; then
    echo "✅ All drugs already processed!"
    exit 0
fi

# Configuration
DRUGS_PER_JOB=50  # Smaller batches for faster turnaround
MAX_CONCURRENT_JOBS=10  # Limit to avoid overwhelming scheduler

JOBS_NEEDED=$(( (MISSING + DRUGS_PER_JOB - 1) / DRUGS_PER_JOB ))

echo "📦 Job Configuration:"
echo "  Drugs per job: $DRUGS_PER_JOB"
echo "  Maximum concurrent jobs: $MAX_CONCURRENT_JOBS"
echo "  Total jobs needed: $JOBS_NEEDED"

# Find starting index (first missing drug)
START_INDEX=$(julia -e "
    include(\"approved_drugs_dict.jl\")
    existing_files = Set(replace.(readdir(\"llama_naive_extracted_indications\"), \"_enhanced_naive_extracted_indications.json\" => \"\"))
    drug_names = collect(keys(APPROVED_DRUGS_DICT))
    for (i, drug) in enumerate(drug_names)
        if !(replace(drug, \" \" => \"_\") in existing_files)
            println(i)
            break
        end
    end
")

echo "  Starting from drug index: $START_INDEX"

# Submit jobs in waves to respect concurrent limit
echo ""
echo "🌊 Submitting jobs in waves..."

CURRENT_INDEX=$START_INDEX
JOBS_SUBMITTED=0
WAVE=1

while [ $CURRENT_INDEX -le $TOTAL_DRUGS ] && [ $JOBS_SUBMITTED -lt $JOBS_NEEDED ]; do
    echo ""
    echo "🌊 Wave $WAVE (up to $MAX_CONCURRENT_JOBS jobs):"
    
    WAVE_JOBS=0
    
    # Submit up to MAX_CONCURRENT_JOBS in this wave
    while [ $WAVE_JOBS -lt $MAX_CONCURRENT_JOBS ] && [ $CURRENT_INDEX -le $TOTAL_DRUGS ] && [ $JOBS_SUBMITTED -lt $JOBS_NEEDED ]; do
        
        # Calculate actual batch size (don't exceed total drugs)
        ACTUAL_BATCH_SIZE=$DRUGS_PER_JOB
        if [ $((CURRENT_INDEX + DRUGS_PER_JOB - 1)) -gt $TOTAL_DRUGS ]; then
            ACTUAL_BATCH_SIZE=$((TOTAL_DRUGS - CURRENT_INDEX + 1))
        fi
        
        echo "  Job $((JOBS_SUBMITTED + 1)): drugs $CURRENT_INDEX-$((CURRENT_INDEX + ACTUAL_BATCH_SIZE - 1))"
        
        # Submit job
        JOB_ID=$(sbatch scripts/slurm/single_gpu_naive_extraction.slurm $CURRENT_INDEX $ACTUAL_BATCH_SIZE | awk '{print $4}')
        echo "    → Job ID: $JOB_ID"
        
        # Update counters
        CURRENT_INDEX=$((CURRENT_INDEX + ACTUAL_BATCH_SIZE))
        JOBS_SUBMITTED=$((JOBS_SUBMITTED + 1))
        WAVE_JOBS=$((WAVE_JOBS + 1))
        
        # Small delay to avoid overwhelming scheduler
        sleep 1
    done
    
    if [ $JOBS_SUBMITTED -lt $JOBS_NEEDED ]; then
        echo ""
        echo "⏳ Waiting for some jobs to complete before submitting next wave..."
        echo "   (Will auto-submit more when queue space available)"
        
        # Wait for some jobs to finish before next wave
        while [ $(squeue -u $USER | grep naive | wc -l) -ge $MAX_CONCURRENT_JOBS ]; do
            sleep 30
        done
    fi
    
    WAVE=$((WAVE + 1))
done

echo ""
echo "✅ All jobs submitted!"
echo "📊 Total jobs submitted: $JOBS_SUBMITTED"
echo "📊 Monitor with: squeue -u \$USER"

# Show useful commands
echo ""
echo "🔍 Useful Commands:"
echo "  Check status: ./check_naive_completion.sh"
echo "  Monitor jobs: watch 'squeue -u \$USER'"
echo "  Check logs: ls logs/naive_gpu_batch_*.out"

# Create a monitoring script
cat > monitor_naive_jobs.sh << 'EOF'
#!/bin/bash
echo "📊 Naive Extraction Job Monitor"
echo "==============================="
echo "Running jobs: $(squeue -u $USER | grep naive | wc -l)"
echo "Total completions: $(ls llama_naive_extracted_indications/ | wc -l)/2915"
echo ""
echo "Recent completions:"
ls -lt llama_naive_extracted_indications/ | head -5
echo ""
echo "Running jobs:"
squeue -u $USER | grep naive
EOF

chmod +x monitor_naive_jobs.sh

echo "  Monitor progress: ./monitor_naive_jobs.sh"