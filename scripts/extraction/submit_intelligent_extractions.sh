#!/bin/bash
# Helper script to submit intelligent extraction jobs for multiple drugs

# Function to display usage
function show_usage {
  echo "Usage: $0 [options] [drug1] [drug2] ... [drugN]"
  echo ""
  echo "Options:"
  echo "  -h, --help       Display this help message"
  echo "  -l, --list FILE  Read drug names from a file (one per line)"
  echo ""
  echo "Examples:"
  echo "  $0 Levothyroxine Ibuprofen Metformin"
  echo "  $0 --list drug_list.txt"
}

# Parse command line options
DRUGS=()
DRUG_LIST_FILE=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_usage
      exit 0
      ;;
    -l|--list)
      if [ -f "$2" ]; then
        DRUG_LIST_FILE="$2"
        shift
      else
        echo "Error: Drug list file '$2' not found"
        exit 1
      fi
      ;;
    -*)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
    *)
      DRUGS+=("$1")
      ;;
  esac
  shift
done

# If a drug list file was specified, read drugs from it
if [ -n "$DRUG_LIST_FILE" ]; then
  while IFS= read -r drug; do
    drug=$(echo "$drug" | tr -d '[:space:]')
    if [ -n "$drug" ]; then
      DRUGS+=("$drug")
    fi
  done < "$DRUG_LIST_FILE"
fi

# Check if we have any drugs to process
if [ ${#DRUGS[@]} -eq 0 ]; then
  echo "No drugs specified for processing."
  show_usage
  exit 1
fi

# Script paths
SLURM_SCRIPT="/users/isarkar/sarkarcode/thera/scripts/extraction/intelligent_extraction.slurm"

# Verify scripts exist
if [ ! -f "$SLURM_SCRIPT" ]; then
  echo "Error: SLURM script not found at $SLURM_SCRIPT"
  exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p /users/isarkar/sarkarcode/thera/logs

# Submit jobs
echo "Submitting intelligent extraction jobs for ${#DRUGS[@]} drugs..."

for drug in "${DRUGS[@]}"; do
  echo "Submitting job for: $drug"
  job_id=$(sbatch --parsable "$SLURM_SCRIPT" "$drug")
  
  if [ $? -eq 0 ]; then
    echo "  ✓ Job submitted (ID: $job_id)"
  else
    echo "  ✗ Failed to submit job for $drug"
  fi
done

echo "Done. Use 'squeue -u $USER' to check job status."
