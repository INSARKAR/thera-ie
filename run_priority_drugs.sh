#!/bin/bash

# Priority drug processing script
# Focuses on commonly prescribed and important drugs first

echo "=== Priority Drug Processing with Dual GPU ==="
echo "Start time: $(date)"
echo ""

# Define high-priority drugs (commonly prescribed and therapeutically important)
PRIORITY_DRUGS=(
    "Levothyroxine"
    "Metformin" 
    "Atorvastatin"
    "Lisinopril"
    "Amlodipine"
    "Omeprazole"
    "Metoprolol"
    "Simvastatin"
    "Losartan"
    "Albuterol"
    "Hydrochlorothiazide"
    "Gabapentin"
    "Sertraline"
    "Furosemide"
    "Montelukast"
    "Escitalopram"
    "Prednisone"
    "Tramadol"
    "Trazodone"
    "Duloxetine"
    "Pantoprazole"
    "Meloxicam"
    "Citalopram"
    "Clonazepam"
    "Cyclobenzaprine"
    "Alprazolam"
    "Fluoxetine"
    "Warfarin"
    "Insulin"
    "Aspirin"
    "Ibuprofen"
    "Acetaminophen"
    "Amoxicillin"
    "Ciprofloxacin"
    "Azithromycin"
    "Doxycycline"
    "Cephalexin"
    "Methylprednisolone"
    "Fentanyl"
    "Morphine"
    "Oxycodone"
    "Hydrocodone"
    "Codeine"
    "Clonidine"
    "Carvedilol"
    "Spironolactone"
    "Digoxin"
    "Warfarin"
    "Rivaroxaban"
    "Apixaban"
)

# Function to check if drug file exists
drug_exists() {
    local drug=$1
    [ -f "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/${drug}.json" ]
}

# Function to check if drug already processed
drug_processed() {
    local drug=$1
    [ -f "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/${drug}_llama_extracted_indications.json" ]
}

# Function to submit dual GPU job and wait for completion
process_drug_pair() {
    local drug1=$1
    local drug2=$2
    
    echo "Processing: $drug1 + $drug2"
    
    # Submit job
    export LLAMA_DRUG1="$drug1"
    export LLAMA_DRUG2="$drug2"
    
    local jobid=$(sbatch dual_gpu_llama_extraction.slurm | grep -o '[0-9]\+$')
    
    if [ -z "$jobid" ]; then
        echo "❌ Failed to submit job for $drug1 + $drug2"
        return 1
    fi
    
    echo "  Job ID: $jobid"
    
    # Wait for completion
    while squeue -j "$jobid" -h &>/dev/null; do
        sleep 30
    done
    
    # Check results
    if [ -f "logs/dual_gpu_llama_extraction_${jobid}.out" ]; then
        if grep -q "✅ Dual GPU extraction completed successfully!" "logs/dual_gpu_llama_extraction_${jobid}.out"; then
            echo "  ✅ Successfully completed"
            return 0
        else
            echo "  ❌ Job failed"
            return 1
        fi
    else
        echo "  ⚠️  No log file found"
        return 1
    fi
}

# Main processing
main() {
    echo "📊 Total priority drugs: ${#PRIORITY_DRUGS[@]}"
    
    # Filter to existing and unprocessed drugs
    local pending_drugs=()
    local processed_count=0
    local missing_count=0
    
    for drug in "${PRIORITY_DRUGS[@]}"; do
        if ! drug_exists "$drug"; then
            echo "⚠️  Drug file not found: $drug"
            ((missing_count++))
        elif drug_processed "$drug"; then
            echo "✓ Already processed: $drug"
            ((processed_count++))
        else
            pending_drugs+=("$drug")
        fi
    done
    
    echo ""
    echo "📊 Summary:"
    echo "  Already processed: $processed_count"
    echo "  Missing files: $missing_count"
    echo "  Pending processing: ${#pending_drugs[@]}"
    echo ""
    
    if [ ${#pending_drugs[@]} -eq 0 ]; then
        echo "✅ All priority drugs have been processed!"
        return 0
    fi
    
    # Process in pairs
    local successful_pairs=0
    local failed_pairs=0
    
    for ((i=0; i<${#pending_drugs[@]}; i+=2)); do
        local drug1="${pending_drugs[$i]}"
        local drug2="${pending_drugs[$((i+1))]:-}"
        
        local pair_num=$(((i/2) + 1))
        local total_pairs=$((((${#pending_drugs[@]} + 1) / 2)))
        
        echo "=== Pair $pair_num/$total_pairs ==="
        
        if [ -n "$drug2" ]; then
            if process_drug_pair "$drug1" "$drug2"; then
                ((successful_pairs++))
            else
                ((failed_pairs++))
            fi
        else
            # Single remaining drug
            echo "Processing single drug: $drug1"
            if process_drug_pair "$drug1" ""; then
                ((successful_pairs++))
            else
                ((failed_pairs++))
            fi
        fi
        
        echo ""
        
        # Small delay between jobs
        if [ $i -lt $((${#pending_drugs[@]} - 2)) ]; then
            echo "Waiting 30 seconds before next job..."
            sleep 30
        fi
    done
    
    echo "=== Priority Drug Processing Complete ==="
    echo "✅ Successful pairs: $successful_pairs"
    echo "❌ Failed pairs: $failed_pairs"
    echo "End time: $(date)"
}

# Check if user wants to see status only
if [ "$1" = "status" ]; then
    echo "=== Priority Drug Status ==="
    
    local processed_count=0
    local missing_count=0
    local pending_count=0
    
    for drug in "${PRIORITY_DRUGS[@]}"; do
        if ! drug_exists "$drug"; then
            ((missing_count++))
        elif drug_processed "$drug"; then
            ((processed_count++))
        else
            ((pending_count++))
        fi
    done
    
    echo "Total priority drugs: ${#PRIORITY_DRUGS[@]}"
    echo "Processed: $processed_count"
    echo "Pending: $pending_count"
    echo "Missing files: $missing_count"
    echo "Progress: $(echo "scale=1; $processed_count * 100 / ${#PRIORITY_DRUGS[@]}" | bc -l)%"
    
    # Show current running jobs
    echo ""
    echo "Current jobs:"
    squeue -u $USER
else
    main
fi