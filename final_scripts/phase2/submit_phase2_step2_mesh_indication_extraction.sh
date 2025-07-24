#!/bin/bash

# Submit Phase 2 Step 2: MeSH-Based Indication Extraction
# Extracts unique MeSH descriptors as indications from Phase 1 filtered publications

echo "🚀 Submitting Phase 2 Step 2: MeSH Indication Extraction Jobs"
echo "📋 Extracting unique MeSH descriptors as drug indications"

# Check required files and directories
if [[ ! -f "scripts/extraction/phase2_step2_mesh_indication_extractor.jl" ]]; then
    echo "❌ Error: scripts/extraction/phase2_step2_mesh_indication_extractor.jl not found"
    exit 1
fi

if [[ ! -d "phase1_drug_pubmed_mesh" ]]; then
    echo "❌ Error: phase1_drug_pubmed_mesh directory not found"
    echo "Please ensure Phase 1 Step 5 (MeSH filtering) has been completed"
    exit 1
fi

FILE_COUNT=$(ls phase1_drug_pubmed_mesh/*.json | wc -l)
echo "📋 Processing $FILE_COUNT drug files"

# Create logs and output directories
mkdir -p logs
mkdir -p phase2_indications_mesh

# Submit the SLURM job array
echo "📤 Submitting SLURM job array..."
JOB_OUTPUT=$(sbatch phase2_step2_mesh_indication_extraction.slurm)

if [[ $? -eq 0 ]]; then
    echo "✅ Job array submitted successfully!"
    
    # Extract job ID from output
    JOB_ID=$(echo $JOB_OUTPUT | grep -o '[0-9]\+')
    echo "Job Array ID: $JOB_ID"
    echo "Individual jobs: ${JOB_ID}_1 through ${JOB_ID}_8"
    echo ""
    
    echo "📊 Monitor commands:"
    echo "  All jobs:     squeue -j $JOB_ID"
    echo "  Job status:   squeue -u \$USER"
    echo "  Progress:     ls phase2_indications_mesh/*.json | wc -l"
    echo "  View logs:    tail -f logs/phase2_mesh_indications_${JOB_ID}_1.out"
    echo ""
    
    echo "📊 This Phase 2 Step 2 job array will:"
    echo "  • Process $FILE_COUNT drug files across 8 parallel jobs"
    echo "  • Process ~330 files per job with efficient parallel processing"
    echo "  • Extract unique MeSH descriptors as drug indications"
    echo "  • Count supporting publications for each MeSH descriptor"
    echo "  • Generate evidence-based indication files"
    echo "  • Complete processing in ~2-3 hours"
    echo ""
    
    echo "🔍 Phase 2 Step 2 process:"
    echo "  ✅ Load Phase 1 MeSH-organized publications"
    echo "  ✅ Extract unique MeSH descriptor keys"
    echo "  ✅ Count supporting publications per MeSH descriptor"
    echo "  ✅ Collect PMIDs for evidence tracking"
    echo "  ✅ Sort indications by evidence strength"
    echo "  ✅ Generate standardized indication files"
else
    echo "❌ Failed to submit job array"
    exit 1
fi