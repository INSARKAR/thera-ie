#!/bin/bash

# Submit Phase 1 Step 5: MeSH Filtering and Reorganization
# Filters publications by semantic relevance and frequency, organizes by MeSH descriptor

echo "🚀 Submitting Phase 1 Step 5: MeSH Filtering Jobs"
echo "🎯 Filtering by semantic relevance and frequency, organizing by MeSH"

# Check required files and directories
if [[ ! -f "scripts/extraction/phase1_step5_mesh_filtering_worker.jl" ]]; then
    echo "❌ Error: scripts/extraction/phase1_step5_mesh_filtering_worker.jl not found"
    exit 1
fi

if [[ ! -f "mesh_semantic_headings.jl" ]]; then
    echo "❌ Error: mesh_semantic_headings.jl not found"
    exit 1
fi

if [[ ! -d "phase1_drug_pubmed_refs" ]]; then
    echo "❌ Error: phase1_drug_pubmed_refs directory not found"
    exit 1
fi

FILE_COUNT=$(ls phase1_drug_pubmed_refs/*.json | wc -l)
echo "📋 Processing $FILE_COUNT drug files"

# Create logs directory
mkdir -p logs

# Submit the SLURM job array
echo "📤 Submitting SLURM job array..."
JOB_OUTPUT=$(sbatch phase1_step5_mesh_filtering.slurm)

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
    echo "  Progress:     ls phase1_drug_pubmed_mesh/*.json | wc -l"
    echo "  View logs:    tail -f logs/phase1_mesh_filter_${JOB_ID}_1.out"
    echo ""
    
    echo "📊 This MeSH filtering job array will:"
    echo "  • Process $FILE_COUNT drug files across 8 parallel jobs"
    echo "  • Process ~330 files per job with efficient parallel processing"
    echo "  • Apply semantic filtering using approved MeSH descriptors"
    echo "  • Apply >1% frequency filtering (except for ≤5 publications)"
    echo "  • Organize publications by MeSH descriptor categories"
    echo "  • Complete processing in ~4-6 hours"
    echo ""
    
    echo "🔍 MeSH filtering process:"
    echo "  ✅ Semantic filter - keep publications with relevant MeSH terms"
    echo "  ✅ Frequency filter - keep MeSH terms appearing in >1% of publications"
    echo "  ✅ Special handling - keep all if ≤5 publications after semantic filter"
    echo "  ✅ Organization - group publications by MeSH descriptor"
    echo "  ✅ Redundancy allowed - same PMID can appear under multiple MeSH categories"
else
    echo "❌ Failed to submit job array"
    exit 1
fi