#!/bin/bash

# Submit Phase 2 Step 1: DrugBank Llama Indication Extraction
# Uses dual GPUs to extract indications from DrugBank text for all approved drugs

echo "🚀 Submitting Phase 2 Step 1: DrugBank Llama Indication Extraction"
echo "📋 Extracting therapeutic indications from DrugBank text using Llama 3.2"

# Check required files and directories
if [[ ! -f "scripts/extraction/phase2_step1_drugbank_llama_coordinator.jl" ]]; then
    echo "❌ Error: Coordinator script not found"
    exit 1
fi

if [[ ! -f "scripts/extraction/phase2_step1_drugbank_llama_extractor.jl" ]]; then
    echo "❌ Error: Worker script not found"
    exit 1
fi

if [[ ! -f "generated_dependency_files/approved_drugs_dict.jl" ]]; then
    echo "❌ Error: Approved drugs dictionary not found"
    echo "Please run Phase 0 Step 1 to generate this file"
    exit 1
fi

if [[ ! -f "prompts/llm_prompt_drugbank.txt" ]]; then
    echo "❌ Error: DrugBank prompt template not found"
    exit 1
fi

# Count total drugs
TOTAL_DRUGS=2915
echo "📊 Total approved drugs to process: $TOTAL_DRUGS"

# Create logs and output directories
mkdir -p logs
mkdir -p phase2_indications_llama_drugbank

# Check existing progress
EXISTING_COUNT=$(ls phase2_indications_llama_drugbank/*_drugbank_extracted_indications.json 2>/dev/null | wc -l)
REMAINING=$((TOTAL_DRUGS - EXISTING_COUNT))

echo "✅ Already processed: $EXISTING_COUNT/$TOTAL_DRUGS"
echo "📋 Remaining to process: $REMAINING"

if [[ $REMAINING -eq 0 ]]; then
    echo "🎉 All drugs have already been processed!"
    echo "To reprocess, remove files from phase2_indications_llama_drugbank/"
    exit 0
fi

# Submit the SLURM job
echo ""
echo "📤 Submitting dual-GPU SLURM job..."
JOB_OUTPUT=$(sbatch phase2_step1_drugbank_llama_extraction.slurm)

if [[ $? -eq 0 ]]; then
    echo "✅ Job submitted successfully!"
    
    # Extract job ID from output
    JOB_ID=$(echo $JOB_OUTPUT | grep -o '[0-9]\+')
    echo "Job ID: $JOB_ID"
    echo ""
    
    echo "📊 Monitor commands:"
    echo "  Job status:   squeue -j $JOB_ID"
    echo "  View logs:    tail -f logs/phase2_drugbank_llama_${JOB_ID}.out"
    echo "  Progress:     ls phase2_indications_llama_drugbank/*.json | wc -l"
    echo ""
    
    # Estimate completion time
    MINUTES_PER_DRUG=0.083  # ~5 seconds per drug
    PARALLEL_FACTOR=2       # 2 GPUs
    ESTIMATED_MINUTES=$(echo "scale=0; $REMAINING * $MINUTES_PER_DRUG / $PARALLEL_FACTOR" | bc)
    ESTIMATED_HOURS=$(echo "scale=1; $ESTIMATED_MINUTES / 60" | bc)
    
    echo "📊 This Phase 2 Step 1 job will:"
    echo "  • Use 2 GPUs in parallel for maximum efficiency"
    echo "  • Process $REMAINING remaining drugs"
    echo "  • Extract indications from DrugBank text"
    echo "  • Apply confidence scoring (threshold: 0.6)"
    echo "  • Generate structured JSON output files"
    echo "  • Complete in approximately $ESTIMATED_HOURS hours"
    echo ""
    
    echo "🔍 Process overview:"
    echo "  ✅ Load approved drugs from generated_dependency_files/"
    echo "  ✅ Check for existing output files"
    echo "  ✅ Start Ollama servers on both GPUs"
    echo "  ✅ Split remaining drugs between GPUs"
    echo "  ✅ Process each drug's indication text with Llama 3.2"
    echo "  ✅ Extract and normalize medical conditions"
    echo "  ✅ Apply confidence scoring"
    echo "  ✅ Save results to phase2_indications_llama_drugbank/"
else
    echo "❌ Failed to submit job"
    exit 1
fi