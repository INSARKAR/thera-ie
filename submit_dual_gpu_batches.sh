#!/bin/bash

# Submit dual GPU batch jobs to process remaining naive extractions
# Each job processes 2 batches simultaneously on 2 GPUs

echo "=== Submitting Dual GPU Batch Jobs ==="

# We have batches 00-18 (19 total)
# Pair them up: (00,01), (02,03), (04,05), etc.
# Last batch 18 will run alone on GPU 0

submitted_jobs=0

for i in {0..8}; do
    batch1=$(printf "%02d" $((i * 2)))
    batch2=$(printf "%02d" $((i * 2 + 1)))
    
    echo "Submitting dual GPU job: batch $batch1 + batch $batch2"
    sbatch -J "dual_naive_${batch1}_${batch2}" \
           -o "logs/dual_naive_${batch1}_${batch2}_%j.out" \
           -e "logs/dual_naive_${batch1}_${batch2}_%j.err" \
           dual_gpu_naive_batch.slurm $batch1 $batch2
    
    ((submitted_jobs++))
    sleep 2
done

# Handle the last odd batch (18) separately
batch_last=$(printf "%02d" 18)
echo "Submitting single GPU job for remaining batch: $batch_last"
sbatch -J "dual_naive_${batch_last}_solo" \
       -o "logs/dual_naive_${batch_last}_solo_%j.out" \
       -e "logs/dual_naive_${batch_last}_solo_%j.err" \
       dual_gpu_naive_batch.slurm $batch_last $batch_last

((submitted_jobs++))

echo ""
echo "=== Submission Complete ==="
echo "Total jobs submitted: $submitted_jobs"
echo "Each dual GPU job processes ~100 drugs (2 batches of 50)"
echo "Expected total drug processing: ~950 drugs"
echo ""
echo "Monitor progress with: squeue -u \$USER"
echo "Check completion with: find llama_naive_extracted_indications/ -name '*_enhanced_naive_extracted_indications.json' | wc -l"