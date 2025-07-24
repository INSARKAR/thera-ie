#!/bin/bash

# Phase 0 Step 2: MeSH Semantic Type Extraction  
# Extracts medical MeSH descriptors from MeSH descriptor files

echo "🚀 Starting Phase 0 Step 2: MeSH Semantic Type Extraction"
echo "📋 Processing MeSH descriptors to extract medical semantic types"

# Check if MeSH descriptor file exists
MESH_FILE="_data/mesh/d2025.bin"
if [[ ! -f "$MESH_FILE" ]]; then
    echo "❌ Error: MeSH descriptor file not found at $MESH_FILE"
    echo "Please place the MeSH d2025.bin file in _data/mesh/"
    echo "Download from: https://www.nlm.nih.gov/databases/download/mesh.html"
    exit 1
fi

# Create output directories  
mkdir -p generated_dependency_files
mkdir -p logs

echo "📤 Running MeSH semantic type extraction..."

# Run the extraction
julia --project=. phase0_step2_mesh_semantic_extractor.jl 2>&1 | tee logs/phase0_step2_mesh_extraction.log

if [[ $? -eq 0 ]]; then
    echo "✅ MeSH extraction completed successfully!"
    echo ""
    echo "📊 Generated files:"
    echo "  📋 mesh_semantic_headings.jl - Julia Set format"
    echo "  📋 mesh_semantic_headings.txt - Plain text list"
    echo ""
    echo "📈 Statistics:"
    if [[ -f "generated_dependency_files/mesh_semantic_headings.jl" ]]; then
        MESH_COUNT=$(grep -o '"[^"]*"' generated_dependency_files/mesh_semantic_headings.jl | wc -l)
        echo "  ✅ Extracted $MESH_COUNT medical MeSH descriptors"
    fi
    echo "  📂 Files saved in: generated_dependency_files/"
    echo ""
    echo "🔍 Semantic types included:"
    echo "  • T047 - Disease or Syndrome"
    echo "  • T191 - Neoplastic Process"  
    echo "  • T048 - Mental or Behavioral Dysfunction"
    echo "  • T184 - Sign or Symptom"
    echo "  • And 11 other medical semantic types"
else
    echo "❌ MeSH extraction failed"
    echo "📋 Check logs/phase0_step2_mesh_extraction.log for details"
    exit 1
fi