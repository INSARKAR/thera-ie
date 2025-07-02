#!/bin/bash

# Submit Llama Drug Indication Extraction Job
# Usage: ./submit_extraction.sh [DRUG_NAME] [--test]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values
DRUG_NAME="Levothyroxine"
TEST_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [DRUG_NAME] [--test]"
            echo ""
            echo "Arguments:"
            echo "  DRUG_NAME    Name of the drug to process (default: Levothyroxine)"
            echo "  --test       Run in test mode (quick test only)"
            echo ""
            echo "Examples:"
            echo "  $0                          # Process Levothyroxine"
            echo "  $0 Aspirin                 # Process Aspirin"
            echo "  $0 Levothyroxine --test    # Test with Levothyroxine"
            echo ""
            echo "Available drugs:"
            ls drug_pubmed_refs/*.json 2>/dev/null | head -10 | xargs -n1 basename | sed 's/.json$//' | sed 's/^/  /'
            exit 0
            ;;
        *)
            DRUG_NAME="$1"
            shift
            ;;
    esac
done

echo "=== Llama Drug Indication Extraction Submission ==="
echo "Drug: $DRUG_NAME"
echo "Test mode: $TEST_MODE"
echo "Working directory: $(pwd)"
echo ""

# Validate drug file exists
DRUG_FILE="drug_pubmed_refs/${DRUG_NAME}.json"
if [ ! -f "$DRUG_FILE" ]; then
    echo "❌ ERROR: Drug file not found: $DRUG_FILE"
    echo ""
    echo "Available drugs (first 20):"
    ls drug_pubmed_refs/*.json 2>/dev/null | head -20 | xargs -n1 basename | sed 's/.json$//' | sed 's/^/  /'
    echo ""
    echo "Use --help for usage information"
    exit 1
fi

echo "✓ Drug file found: $DRUG_FILE"

# Create logs directory
mkdir -p logs
echo "✓ Logs directory ready: logs/"

# Check if SLURM script exists
if [ ! -f "llama_extraction.slurm" ]; then
    echo "❌ ERROR: SLURM script not found: llama_extraction.slurm"
    exit 1
fi

echo "✓ SLURM script found: llama_extraction.slurm"

# Check current queue status
echo ""
echo "=== Current Queue Status ==="
myq 2>/dev/null || echo "Could not check queue status"

# Submit the job
echo ""
echo "=== Submitting Job ==="

if [ "$TEST_MODE" = true ]; then
    echo "Submitting test job for $DRUG_NAME..."
    # For test mode, we'll modify the SLURM script temporarily
    cp llama_extraction.slurm llama_extraction_test.slurm
    sed -i 's/#SBATCH --time=2:00:00/#SBATCH --time=0:30:00/' llama_extraction_test.slurm
    sed -i 's/llama_extraction_%j/llama_test_%j/' llama_extraction_test.slurm
    
    JOB_ID=$(sbatch --parsable llama_extraction_test.slurm "$DRUG_NAME")
    rm llama_extraction_test.slurm
else
    echo "Submitting full extraction job for $DRUG_NAME..."
    JOB_ID=$(sbatch --parsable llama_extraction.slurm "$DRUG_NAME")
fi

if [ $? -eq 0 ]; then
    echo "✓ Job submitted successfully!"
    echo "Job ID: $JOB_ID"
    echo ""
    echo "=== Monitoring Commands ==="
    echo "Check job status:    squeue -j $JOB_ID"
    echo "View output:         tail -f logs/llama_extraction_${JOB_ID}.out"
    echo "View errors:         tail -f logs/llama_extraction_${JOB_ID}.err"
    echo "Cancel job:          scancel $JOB_ID"
    echo ""
    echo "=== Expected Timeline ==="
    if [ "$TEST_MODE" = true ]; then
        echo "Test mode: ~5-10 minutes"
        echo "- GPU allocation: 1-2 minutes"
        echo "- Ollama setup: 2-3 minutes"
        echo "- Quick test: 2-3 minutes"
    else
        echo "Full extraction: ~30-60 minutes (depends on number of publications)"
        echo "- GPU allocation: 1-2 minutes"
        echo "- Ollama setup: 2-3 minutes"
        echo "- Processing: varies by drug (1-10 seconds per publication)"
    fi
    echo ""
    echo "Results will be saved to: llama_pubmed_extracted_indications/"
else
    echo "❌ ERROR: Failed to submit job"
    exit 1
fi
