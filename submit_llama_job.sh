#!/bin/bash

# Helper script to submit Llama drug indication extraction jobs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 [OPTIONS] [DRUG_NAME]"
    echo ""
    echo "Submit SLURM jobs for Llama drug indication extraction"
    echo ""
    echo "OPTIONS:"
    echo "  -t, --test          Run in test mode (quick test with 2 publications)"
    echo "  -f, --full          Run full extraction for specified drug"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 -t                    # Run quick test with Levothyroxine"
    echo "  $0 -f Levothyroxine      # Run full extraction for Levothyroxine"
    echo "  $0 -f Aspirin           # Run full extraction for Aspirin"
    echo "  $0 Metformin            # Run full extraction for Metformin (default mode)"
    echo ""
    echo "NOTES:"
    echo "  - Test mode processes only 2 publications for quick validation"
    echo "  - Full mode processes all publications for the specified drug"
    echo "  - If no drug is specified, defaults to Levothyroxine"
    echo "  - Job logs will be saved in the logs/ directory"
    echo ""
}

# Default values
TEST_MODE=false
DRUG_NAME="Levothyroxine"
MODE_SET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test)
            TEST_MODE=true
            MODE_SET=true
            shift
            ;;
        -f|--full)
            TEST_MODE=false
            MODE_SET=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unknown option $1"
            show_usage
            exit 1
            ;;
        *)
            DRUG_NAME="$1"
            shift
            ;;
    esac
done

# If no mode was explicitly set and a drug name was provided, default to full mode
if [ "$MODE_SET" = false ] && [ "$DRUG_NAME" != "Levothyroxine" ]; then
    TEST_MODE=false
fi

# Validate drug name (check if file exists)
DRUG_FILE="$SCRIPT_DIR/drug_pubmed_refs/${DRUG_NAME}.json"
if [ ! -f "$DRUG_FILE" ]; then
    echo "❌ Error: Drug file not found: $DRUG_FILE"
    echo ""
    echo "Available drugs (first 10):"
    ls "$SCRIPT_DIR/drug_pubmed_refs/"*.json 2>/dev/null | head -10 | xargs -n 1 basename | sed 's/\.json$//' | sed 's/^/  /'
    echo "  ..."
    echo ""
    echo "Use 'ls drug_pubmed_refs/' to see all available drugs."
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/logs"

# Display job configuration
echo "=== Llama Drug Indication Extraction Job Submission ==="
echo "Drug: $DRUG_NAME"
echo "Mode: $([ "$TEST_MODE" = true ] && echo "Test (quick)" || echo "Full extraction")"
echo "SLURM script: $SCRIPT_DIR/llama_extraction.slurm"
echo "Logs directory: $SCRIPT_DIR/logs/"
echo ""

# Submit the job
echo "Submitting SLURM job..."

if [ "$TEST_MODE" = true ]; then
    JOB_ID=$(sbatch \
        --export=LLAMA_SINGLE_DRUG="$DRUG_NAME",LLAMA_TEST_MODE=true \
        --job-name="llama_test_${DRUG_NAME}" \
        "$SCRIPT_DIR/llama_extraction.slurm")
else
    JOB_ID=$(sbatch \
        --export=LLAMA_SINGLE_DRUG="$DRUG_NAME",LLAMA_TEST_MODE=false \
        --job-name="llama_extract_${DRUG_NAME}" \
        "$SCRIPT_DIR/llama_extraction.slurm")
fi

if [ $? -eq 0 ]; then
    # Extract job ID from sbatch output
    JOB_NUM=$(echo "$JOB_ID" | grep -o '[0-9]\+')
    echo "✓ Job submitted successfully!"
    echo "Job ID: $JOB_NUM"
    echo ""
    echo "Monitor job status:"
    echo "  myq"
    echo "  squeue -u \$USER"
    echo ""
    echo "View job logs:"
    echo "  tail -f logs/llama_extraction_${JOB_NUM}.out"
    echo "  tail -f logs/llama_extraction_${JOB_NUM}.err"
    echo ""
    echo "Cancel job if needed:"
    echo "  scancel $JOB_NUM"
    echo ""
    echo "Check results when complete:"
    echo "  ls -la llama_pubmed_extracted_indications/"
else
    echo "❌ Failed to submit job"
    exit 1
fi
