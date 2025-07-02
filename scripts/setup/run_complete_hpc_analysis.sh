#!/bin/bash

# Complete HPC Workflow Script for Llama Drug Indication Extraction
# 
# This script handles the complete workflow:
# 1. Request GPU resources
# 2. Load required modules  
# 3. Run the analysis with SSH to GPU node
# 4. Retrieve results
# 
# Usage:
#   ./run_complete_hpc_analysis.sh [--test] [--drug DrugName]

set -e  # Exit on any error

# Parse command line arguments
TEST_MODE=""
SINGLE_DRUG=""
JULIA_ARGS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE="--test"
            JULIA_ARGS="$JULIA_ARGS --test"
            shift
            ;;
        --drug)
            SINGLE_DRUG="$2"
            JULIA_ARGS="$JULIA_ARGS --drug $2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--test] [--drug DrugName] [--help]"
            echo ""
            echo "Options:"
            echo "  --test              Run in test mode (3 files only)"
            echo "  --drug DrugName     Run analysis for single drug"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "This script will:"
            echo "1. Request GPU resources if not already allocated"
            echo "2. Load required modules (Ollama)"
            echo "3. Run the drug indication extraction analysis"
            echo "4. Handle SSH to GPU node automatically"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🏥 Complete HPC Workflow for Llama Drug Indication Extraction"
echo "============================================================="

# Check if we're already in a GPU session
if [[ -n "$SLURM_JOB_ID" ]]; then
    echo "✓ Already in SLURM job: $SLURM_JOB_ID"
    
    # Load required modules
    echo "📦 Loading required modules..."
    module load ollama
    echo "✓ Ollama module loaded"
    
    # Run the analysis
    echo "🚀 Starting analysis..."
    if [[ -n "$TEST_MODE" ]]; then
        echo "Running in TEST MODE"
    fi
    if [[ -n "$SINGLE_DRUG" ]]; then
        echo "Running single drug analysis: $SINGLE_DRUG"
    fi
    
    julia hpc_setup_and_run_v2.jl $JULIA_ARGS
    
else
    echo "❌ Not in a SLURM GPU session"
    echo ""
    echo "To run the complete analysis, you have two options:"
    echo ""
    echo "Option 1 - Interactive Session (Recommended for testing):"
    echo "  interact -n 4 -m 32g -q gpu -g 1 -t 2:00:00"
    echo "  cd $(pwd)"
    echo "  $0 $JULIA_ARGS"
    echo ""
    echo "Option 2 - Batch Job (For production runs):"
    echo "  sbatch --job-name=llama_extraction \\"
    echo "         --partition=gpu \\"
    echo "         --gres=gpu:1 \\"
    echo "         --nodes=1 \\"
    echo "         --ntasks=4 \\"
    echo "         --mem=32G \\"
    echo "         --time=4:00:00 \\"
    echo "         --wrap=\"cd $(pwd) && $0 $JULIA_ARGS\""
    echo ""
    echo "Starting interactive session now (2 hours)..."
    echo "The script will automatically request new sessions as needed."
    echo "After the session starts, please run:"
    echo "  cd $(pwd)"
    echo "  $0 $JULIA_ARGS"
    echo ""
    
    # Request interactive session with 2-hour limit
    interact -n 4 -m 32g -q gpu -g 1 -t 2:00:00
fi
