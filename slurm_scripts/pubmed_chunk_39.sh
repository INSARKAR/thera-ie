#!/bin/bash
#SBATCH --job-name=pubmed_drugs_39
#SBATCH --output=slurm_outputs/pubmed_chunk_39_%j.out
#SBATCH --error=slurm_outputs/pubmed_chunk_39_%j.err
#SBATCH --time=4:00:00
#SBATCH --mem=8G
#SBATCH --partition=batch
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=neil_sarkar@brown.edu
# Set environment variables for this chunk
export SLURM_DRUG_START=1901
export SLURM_DRUG_END=1950
export SLURM_CHUNK_ID=39

# Load Julia module if available
module load julia 2>/dev/null || echo "Julia module not available, using system Julia"

# Navigate to the working directory
cd ${SLURM_SUBMIT_DIR}

# Run the analysis for this chunk
echo "Starting PubMed analysis for chunk 39 (drugs 1901 to 1950)"
echo "Started at: $(date)"
echo "Node: $(hostname)"
echo "Working directory: $(pwd)"

# Run the Julia program in single-job mode
julia slurm_pubmed_drug_indications.jl --single-job

echo "Completed at: $(date)"
