#!/bin/bash

# Check naive extraction completion status

echo "📊 Naive Extraction Completion Status"
echo "=" ^40

# Calculate current status
TOTAL_DRUGS=$(julia -e "include(\"approved_drugs_dict.jl\"); println(length(APPROVED_DRUGS_DICT))")
EXISTING_NAIVE=$(ls llama_naive_extracted_indications/ | wc -l 2>/dev/null || echo 0)
MISSING=$((TOTAL_DRUGS - EXISTING_NAIVE))
COMPLETION_PCT=$(( EXISTING_NAIVE * 100 / TOTAL_DRUGS ))

echo "Total drugs in approved list: $TOTAL_DRUGS"
echo "Naive extractions completed: $EXISTING_NAIVE"
echo "Still missing: $MISSING"
echo "Completion: $COMPLETION_PCT%"

# Show running jobs
RUNNING_JOBS=$(squeue -u $USER | grep naive | wc -l)
if [ $RUNNING_JOBS -gt 0 ]; then
    echo ""
    echo "🏃 Currently running naive jobs: $RUNNING_JOBS"
    squeue -u $USER | grep naive
else
    echo ""
    echo "💤 No naive extraction jobs currently running"
fi

# Progress bar
echo ""
echo "Progress: ["
for ((i=1; i<=50; i++)); do
    if [ $((i * 2)) -le $COMPLETION_PCT ]; then
        echo -n "█"
    else
        echo -n "░"
    fi
done
echo "] $COMPLETION_PCT%"

if [ $MISSING -eq 0 ]; then
    echo ""
    echo "🎉 All naive extractions complete!"
    echo "✅ Ready for recovery analysis"
else
    echo ""
    echo "⏳ $MISSING drugs still need processing"
    
    if [ $RUNNING_JOBS -eq 0 ]; then
        echo "💡 Run: ./submit_remaining_naive_extractions.sh"
    fi
fi