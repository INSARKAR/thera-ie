#!/bin/bash

# Phase 0 Step 1: DrugBank Approved Drugs Extraction
# Extracts approved drugs with indications from DrugBank XML file

echo "🚀 Starting Phase 0 Step 1: DrugBank Approved Drugs Extraction"
echo "📋 Processing DrugBank XML to extract approved drugs with valid indications"

# Check if DrugBank XML file exists
DRUGBANK_XML="_data/drugbank/full_database.xml"
if [[ ! -f "$DRUGBANK_XML" ]]; then
    echo "❌ Error: DrugBank XML file not found at $DRUGBANK_XML"
    echo "Please place the DrugBank full database XML file in _data/drugbank/"
    exit 1
fi

# Create output directories
mkdir -p generated_dependency_files
mkdir -p logs

echo "📤 Running DrugBank extraction..."

# Run the extraction
julia --project=. phase0_step1_drugbank_extractor.jl "$DRUGBANK_XML" 2>&1 | tee logs/phase0_step1_drugbank_extraction.log

if [[ $? -eq 0 ]]; then
    echo "✅ DrugBank extraction completed successfully!"
    echo ""
    echo "📊 Generated files:"
    echo "  📋 approved_drugs_dict.jl - Julia dictionary format"  
    echo "  📋 approved_drugs_dict.json - JSON format"
    echo "  📋 approved_drugs_list.csv - CSV format"
    echo ""
    echo "📈 Statistics:"
    if [[ -f "generated_dependency_files/approved_drugs_dict.jl" ]]; then
        DRUG_COUNT=$(grep -c '"' generated_dependency_files/approved_drugs_dict.jl)
        echo "  ✅ Extracted $DRUG_COUNT approved drugs with valid indications"
    fi
    echo "  📂 Files saved in: generated_dependency_files/"
else
    echo "❌ DrugBank extraction failed"
    echo "📋 Check logs/phase0_step1_drugbank_extraction.log for details"
    exit 1
fi