#!/bin/bash

# Submit Phase2 Drug-Indication Analysis Jobs
# This script manages submission of phase2 analysis jobs for all remaining drugs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Submit phase2 analysis jobs for drug-indication processing"
    echo ""
    echo "OPTIONS:"
    echo "  --status         Show current processing status"
    echo "  --test N         Submit test jobs for first N drugs (default: 5)"
    echo "  --batch N        Submit batch of N jobs starting from next unprocessed"
    echo "  --all            Submit jobs for all remaining drugs"
    echo "  --cancel         Cancel all phase2 analysis jobs"
    echo "  --monitor        Monitor running jobs"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 --status                    # Check processing status"
    echo "  $0 --test 10                   # Test with 10 drugs"
    echo "  $0 --batch 100                 # Submit 100 jobs"
    echo "  $0 --all                       # Submit all remaining drugs"
    echo "  $0 --monitor                   # Monitor job progress"
    echo ""
}

show_status() {
    echo "=== Phase2 Processing Status ==="
    julia --project=. phase2_drug_indication_analyzer.jl --status
    echo ""
    
    # Show currently running jobs
    echo "=== Currently Running Jobs ==="
    jobs_running=$(squeue -u $USER -n phase2_analysis --noheader | wc -l)
    if [ $jobs_running -gt 0 ]; then
        echo "Phase2 analysis jobs running: $jobs_running"
        squeue -u $USER -n phase2_analysis
    else
        echo "No phase2 analysis jobs currently running"
    fi
    echo ""
}

get_remaining_count() {
    julia --project=. -e "
    include(\"phase2_drug_indication_analyzer.jl\")
    status = get_processing_status()
    println(status[\"remaining\"])
    "
}

submit_jobs() {
    local num_jobs=$1
    local start_index=${2:-1}
    
    echo "🚀 Submitting $num_jobs phase2 analysis jobs..."
    echo "   Start index: $start_index"
    echo "   End index: $((start_index + num_jobs - 1))"
    echo ""
    
    # Create logs directory
    mkdir -p logs
    
    # Submit array job
    local end_index=$((start_index + num_jobs - 1))
    sbatch --array=${start_index}-${end_index}%20 phase2_analysis.slurm
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully submitted $num_jobs jobs"
        echo "📋 Jobs will process drugs $start_index through $end_index"
        echo "⚠️  Note: Maximum 20 jobs will run concurrently"
        echo ""
        echo "Monitor progress with:"
        echo "  $0 --monitor"
        echo "  squeue -u $USER -n phase2_analysis"
    else
        echo "❌ Failed to submit jobs"
        exit 1
    fi
}

cancel_jobs() {
    echo "🛑 Cancelling all phase2 analysis jobs..."
    
    job_ids=$(squeue -u $USER -n phase2_analysis --noheader -o "%A" | tr '\n' ' ')
    
    if [ -z "$job_ids" ]; then
        echo "No phase2 analysis jobs found to cancel"
        return
    fi
    
    for job_id in $job_ids; do
        scancel $job_id
        echo "Cancelled job: $job_id"
    done
    
    echo "✅ All phase2 analysis jobs cancelled"
}

monitor_jobs() {
    echo "=== Phase2 Analysis Job Monitor ==="
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    while true; do
        clear
        echo "=== Phase2 Analysis Job Monitor - $(date) ==="
        echo ""
        
        # Show current status
        show_status
        
        # Show recent log output
        echo "=== Recent Log Output ==="
        latest_log=$(ls -t logs/phase2_analysis_*.out 2>/dev/null | head -1)
        if [ ! -z "$latest_log" ]; then
            echo "Latest log: $latest_log"
            echo "---"
            tail -5 "$latest_log" 2>/dev/null || echo "No log content yet"
        else
            echo "No log files found yet"
        fi
        
        echo ""
        echo "Refreshing in 30 seconds... (Ctrl+C to stop)"
        sleep 30
    done
}

# Validate environment
if [ ! -f "phase2_drug_indication_analyzer.jl" ]; then
    echo "❌ Error: phase2_drug_indication_analyzer.jl not found"
    echo "Please run this script from the thera project directory"
    exit 1
fi

if [ ! -f "phase2_analysis.slurm" ]; then
    echo "❌ Error: phase2_analysis.slurm not found"
    echo "Please ensure the SLURM script exists"
    exit 1
fi

# Parse command line arguments
case "${1:-}" in
    --status)
        show_status
        ;;
    --test)
        num_test=${2:-5}
        echo "🧪 Running test submission with $num_test drugs"
        submit_jobs $num_test 1
        ;;
    --batch)
        if [ -z "$2" ]; then
            echo "❌ Error: --batch requires number of jobs"
            echo "Usage: $0 --batch <number_of_jobs>"
            exit 1
        fi
        
        remaining=$(get_remaining_count)
        if [ $remaining -eq 0 ]; then
            echo "✅ All drugs have been processed!"
            exit 0
        fi
        
        batch_size=$2
        if [ $batch_size -gt $remaining ]; then
            echo "⚠️  Requested $batch_size jobs, but only $remaining drugs remaining"
            echo "Submitting $remaining jobs instead"
            batch_size=$remaining
        fi
        
        # Calculate start index (total drugs - remaining + 1)
        total_drugs=$(julia --project=. -e "
        include(\"phase2_drug_indication_analyzer.jl\")
        status = get_processing_status()
        println(status[\"total_drugs\"])
        ")
        start_index=$((total_drugs - remaining + 1))
        
        submit_jobs $batch_size $start_index
        ;;
    --all)
        remaining=$(get_remaining_count)
        if [ $remaining -eq 0 ]; then
            echo "✅ All drugs have been processed!"
            exit 0
        fi
        
        echo "📊 Found $remaining drugs remaining to process"
        echo "🚀 Submitting jobs for all remaining drugs..."
        
        # Calculate start index
        total_drugs=$(julia --project=. -e "
        include(\"phase2_drug_indication_analyzer.jl\")
        status = get_processing_status()
        println(status[\"total_drugs\"])
        ")
        start_index=$((total_drugs - remaining + 1))
        
        submit_jobs $remaining $start_index
        ;;
    --cancel)
        cancel_jobs
        ;;
    --monitor)
        monitor_jobs
        ;;
    -h|--help)
        show_usage
        ;;
    "")
        echo "❌ Error: No option specified"
        echo ""
        show_usage
        exit 1
        ;;
    *)
        echo "❌ Error: Unknown option '$1'"
        echo ""
        show_usage
        exit 1
        ;;
esac