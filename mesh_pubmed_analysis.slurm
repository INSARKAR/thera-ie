#!/bin/bash
#SBATCH --job-name=mesh_pubmed_analysis
#SBATCH --account=default
#SBATCH --time=12:00:00
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --output=logs/mesh_pubmed_analysis_%j.out
#SBATCH --error=logs/mesh_pubmed_analysis_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=isarkar@brown.edu

# Load required modules
module load julia

# Set working directory
cd /oscar/home/isarkar/sarkarcode/thera

# Create logs directory if it doesn't exist
mkdir -p logs

# Backup existing file before overwriting
if [ -f "drug_disease_associations.json" ]; then
    cp drug_disease_associations.json drug_disease_associations_backup_$(date +%Y%m%d_%H%M%S).json
    echo "Backed up existing drug_disease_associations.json"
fi

# Set environment variables for robust execution
export JULIA_NUM_THREADS=8
export JULIA_PROJECT=.

echo "Starting comprehensive MeSH PubMed drug-disease association analysis..."
echo "Total drugs to analyze: $(wc -l < approved_drugs_list.csv)"
echo "Start time: $(date)"

# Check if required files exist
echo "Checking required files..."
ls -la approved_drugs_dict.jl
ls -la approved_drugs_dict.json
ls -la mesh_t047_headings.jl

# Run the comprehensive analysis with full production mode
echo "Running analysis..."
julia --project=. -t 8 scripts/extraction/pubmed_drug_indications.jl

echo "Analysis completed at: $(date)"

# Check if output file was created successfully
if [ -f "drug_disease_associations.json" ]; then
    echo "✅ Analysis completed successfully"
    echo "Output file size: $(ls -lh drug_disease_associations.json | awk '{print $5}')"
    
    # Count how many drugs were analyzed
    julia -e "
    using JSON3
    data = JSON3.read(read(\"drug_disease_associations.json\", String))
    total_drugs = data.metadata.total_drugs_analyzed
    println(\"Total drugs analyzed: \$total_drugs\")
    
    # Check if Levothyroxine is included
    found_levo = false
    for drug_result in data.results_summary
        if occursin(\"levothyroxine\", lowercase(drug_result.drug_name))
            found_levo = true
            println(\"✅ Levothyroxine found with \$(drug_result.disease_associations_count) MeSH disease associations\")
            if !isempty(drug_result.disease_analysis_summary.matched_diseases)
                println(\"   MeSH descriptors: \$(drug_result.disease_analysis_summary.matched_diseases)\")
            end
            break
        end
    end
    if !found_levo
        println(\"❌ Levothyroxine not found in results\")
    end
    "
else
    echo "❌ Analysis failed - output file not created"
    exit 1
fi

echo "MeSH PubMed analysis job completed"