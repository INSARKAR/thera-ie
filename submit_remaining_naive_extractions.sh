#!/bin/bash

# Submit remaining naive extractions in parallel batches

echo "🔄 Submitting Remaining Naive Extractions"
echo "=" ^50

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

# Calculate batches needed
BATCH_SIZE=400
BATCHES_NEEDED=$(( (MISSING + BATCH_SIZE - 1) / BATCH_SIZE ))

echo "📦 Batch Configuration:"
echo "  Batch size: $BATCH_SIZE drugs"
echo "  Batches needed: $BATCHES_NEEDED"

# Find starting index
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

# Submit batches
echo "🚀 Submitting SLURM jobs..."

CURRENT_INDEX=$START_INDEX
for ((batch=1; batch<=BATCHES_NEEDED; batch++)); do
    echo "  Submitting batch $batch/$BATCHES_NEEDED (starting at index $CURRENT_INDEX)"
    
    # Create batch-specific SLURM script
    BATCH_SCRIPT="scripts/slurm/naive_batch_${batch}.slurm"
    
    # Copy base script and modify for this batch
    cp scripts/slurm/restart_naive_extraction.slurm $BATCH_SCRIPT
    
    # Update the julia command with specific start index
    sed -i "s/julia -t 8 scripts\/extraction\/dual_gpu_batch_enhanced_naive.jl \$START_INDEX \$BATCH_SIZE/julia -t 8 scripts\/extraction\/dual_gpu_batch_enhanced_naive.jl $CURRENT_INDEX $BATCH_SIZE/" $BATCH_SCRIPT
    
    # Update job name
    sed -i "s/#SBATCH --job-name=restart_naive_extraction/#SBATCH --job-name=naive_batch_$batch/" $BATCH_SCRIPT
    
    # Submit job
    JOB_ID=$(sbatch $BATCH_SCRIPT | awk '{print $4}')
    echo "    → Job ID: $JOB_ID"
    
    # Update index for next batch
    CURRENT_INDEX=$((CURRENT_INDEX + BATCH_SIZE))
    
    # Small delay to avoid overwhelming scheduler
    sleep 2
done

echo "✅ All batches submitted!"
echo "📊 Monitor with: squeue -u \$USER"
echo "📋 Check logs in: logs/naive_batch_*"

# Show status command
echo ""
echo "🔍 To check completion status:"
echo "   ./check_naive_completion.sh"