#!/bin/bash

# Monitor Llama drug indication extraction jobs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 [OPTIONS] [JOB_ID]"
    echo ""
    echo "Monitor Llama drug indication extraction jobs"
    echo ""
    echo "OPTIONS:"
    echo "  -s, --status        Show job status"
    echo "  -l, --logs          Show live logs"
    echo "  -r, --results       Show results summary"
    echo "  -a, --all           Show all information"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 -s               # Show status of all your jobs"
    echo "  $0 -l 12345         # Show live logs for job 12345"
    echo "  $0 -r               # Show results summary"
    echo "  $0 -a 12345         # Show all info for job 12345"
    echo ""
}

show_job_status() {
    echo "=== Job Status ==="
    echo "Your SLURM jobs:"
    myq 2>/dev/null || squeue -u $USER
    echo ""
}

show_logs() {
    local job_id=$1
    if [ -z "$job_id" ]; then
        echo "Latest log files:"
        ls -lt "$SCRIPT_DIR/logs/"llama_extraction_*.out 2>/dev/null | head -3
        echo ""
        echo "Specify a job ID to view live logs: $0 -l <JOB_ID>"
        return
    fi
    
    local out_log="$SCRIPT_DIR/logs/llama_extraction_${job_id}.out"
    local err_log="$SCRIPT_DIR/logs/llama_extraction_${job_id}.err"
    
    echo "=== Live Logs for Job $job_id ==="
    if [ -f "$out_log" ]; then
        echo "Output log: $out_log"
        echo "Error log: $err_log"
        echo ""
        echo "Press Ctrl+C to stop following logs"
        echo ""
        tail -f "$out_log" &
        TAIL_PID=$!
        if [ -f "$err_log" ] && [ -s "$err_log" ]; then
            echo "--- Errors ---"
            tail -f "$err_log" &
            TAIL_ERR_PID=$!
        fi
        
        # Wait for Ctrl+C
        trap 'kill $TAIL_PID 2>/dev/null; kill $TAIL_ERR_PID 2>/dev/null; exit 0' INT
        wait $TAIL_PID
    else
        echo "Log file not found: $out_log"
        echo "Job may not have started yet or job ID is incorrect."
    fi
}

show_results() {
    echo "=== Results Summary ==="
    local results_dir="$SCRIPT_DIR/phase1_llama_pubmed_extracted_indications"
    
    if [ ! -d "$results_dir" ]; then
        echo "Results directory not found: $results_dir"
        return
    fi
    
    echo "Results directory: $results_dir"
    echo ""
    
    # List all result files
    local result_files=($(ls "$results_dir"/*.json 2>/dev/null))
    if [ ${#result_files[@]} -eq 0 ]; then
        echo "No result files found."
        return
    fi
    
    echo "Result files:"
    for file in "${result_files[@]}"; do
        local basename_file=$(basename "$file")
        local file_size=$(du -h "$file" | cut -f1)
        local mod_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1-2)
        echo "  $basename_file ($file_size, $mod_time)"
        
        # Try to extract summary information
        if command -v jq >/dev/null 2>&1; then
            if [[ "$basename_file" == *"_llama_extracted.json" ]]; then
                local drug_name=$(jq -r '.metadata.drug_name // "unknown"' "$file" 2>/dev/null)
                local total_pubs=$(jq -r '.metadata.total_publications // 0' "$file" 2>/dev/null)
                local total_indications=$(jq -r '.metadata.total_indications_extracted // 0' "$file" 2>/dev/null)
                echo "    → $drug_name: $total_indications indications from $total_pubs publications"
            elif [[ "$basename_file" == *"quick_test.json" ]]; then
                local pubs_tested=$(jq -r '.test_info.publications_tested // 0' "$file" 2>/dev/null)
                local indications_found=$(jq -r '.test_info.indications_found // 0' "$file" 2>/dev/null)
                echo "    → Test: $indications_found indications from $pubs_tested publications"
            fi
        fi
    done
    echo ""
    
    # Show most recent detailed results
    local latest_file=$(ls -t "$results_dir"/*.json 2>/dev/null | head -1)
    if [ ! -z "$latest_file" ] && command -v jq >/dev/null 2>&1; then
        echo "Latest results details ($(basename "$latest_file")):"
        if [[ "$latest_file" == *"_llama_extracted.json" ]]; then
            echo "Metadata:"
            jq '.metadata' "$latest_file" 2>/dev/null | sed 's/^/  /'
            echo ""
            echo "Sample indications:"
            jq -r '.extracted_indications[0:3][] | "  - \(.indication) (confidence: \(.confidence), PMID: \(.pmid))"' "$latest_file" 2>/dev/null
        elif [[ "$latest_file" == *"quick_test.json" ]]; then
            echo "Test info:"
            jq '.test_info' "$latest_file" 2>/dev/null | sed 's/^/  /'
            echo ""
            echo "Found indications:"
            jq -r '.indications[] | "  - \(.text) (confidence: \(.confidence), PMID: \(.pmid))"' "$latest_file" 2>/dev/null
        fi
    fi
}

# Default action
action="status"
job_id=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--status)
            action="status"
            shift
            ;;
        -l|--logs)
            action="logs"
            shift
            ;;
        -r|--results)
            action="results"
            shift
            ;;
        -a|--all)
            action="all"
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
            job_id="$1"
            shift
            ;;
    esac
done

# Execute the requested action
case $action in
    "status")
        show_job_status
        ;;
    "logs")
        show_logs "$job_id"
        ;;
    "results")
        show_results
        ;;
    "all")
        show_job_status
        echo ""
        show_results
        echo ""
        if [ ! -z "$job_id" ]; then
            show_logs "$job_id"
        fi
        ;;
esac
