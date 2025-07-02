#!/bin/bash

# HPC GPU Request and Analysis Wrapper
# This script requests GPU resources and then runs the Llama analysis

echo "🏥 HPC Llama Drug Indication Extractor - GPU Request Wrapper"
echo "============================================================"

# Check if we're already in a SLURM job
if [[ -n "$SLURM_JOB_ID" ]]; then
    echo "✓ Already in SLURM job: $SLURM_JOB_ID"
    echo "Running analysis directly..."
    julia hpc_setup_and_run.jl "$@"
else
    echo "Requesting GPU resources..."
    echo "Command: interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00"
    echo ""
    echo "This will:"
    echo "1. Request a GPU interactive session"
    echo "2. Load the Ollama module"
    echo "3. Run the Llama drug indication analysis"
    echo ""
    echo "You may need to wait in the queue for GPU availability."
    echo ""
    
    # Create a temporary script to run inside the interactive session
    TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << EOF
#!/bin/bash
echo "🚀 GPU session started, loading Ollama and running analysis..."
module load ollama
cd $(pwd)
julia hpc_setup_and_run.jl $@
echo "Analysis complete. GPU session will end shortly."
EOF
    
    chmod +x "$TEMP_SCRIPT"
    
    # Request interactive session and run the analysis
    interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00 "$TEMP_SCRIPT"
    
    # Clean up
    rm "$TEMP_SCRIPT"
fi
