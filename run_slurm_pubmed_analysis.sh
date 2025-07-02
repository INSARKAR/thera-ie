#!/bin/bash

#
# SLURM PubMed Drug Analysis Orchestrator
#
# This script provides comprehensive management of the SLURM-based PubMed drug analysis pipeline.
# It handles job submission, monitoring, and automatic resubmission for failed or incomplete work.
#
# Usage:
#     ./run_slurm_pubmed_analysis.sh [COMMAND] [OPTIONS]
#
# Commands:
#     start        Start the analysis (submit initial jobs)
#     status       Check current processing status
#     monitor      Monitor running jobs
#     resume       Resume/resubmit jobs for remaining drugs
#     cleanup      Clean up completed job files
#     summary      Generate final summary after all jobs complete
#
# Options:
#     --chunk-size N     Drugs per SLURM job (default: 50)
#     --time HOURS       Job time limit in hours (default: 4)
#     --memory GB        Memory per job in GB (default: 8)
#     --partition NAME   SLURM partition (default: batch)
#     --account NAME     SLURM account (optional)
#     --auto-resume      Automatically resubmit failed jobs
#     --max-retries N    Maximum retry attempts (default: 3)
#

# Default configuration
CHUNK_SIZE=50
TIME_HOURS=4
MEMORY_GB=8
PARTITION="batch"
ACCOUNT=""
AUTO_RESUME=false
MAX_RETRIES=3
LOG_DIR="slurm_orchestrator_logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Create log directory
mkdir -p "$LOG_DIR"
ORCHESTRATOR_LOG="$LOG_DIR/orchestrator_$(date +%Y%m%d_%H%M%S).log"

# Function to log to both console and file
log_both() {
    local level="$1"
    local message="$2"
    case "$level" in
        "INFO") log_info "$message" | tee -a "$ORCHESTRATOR_LOG" ;;
        "SUCCESS") log_success "$message" | tee -a "$ORCHESTRATOR_LOG" ;;
        "WARNING") log_warning "$message" | tee -a "$ORCHESTRATOR_LOG" ;;
        "ERROR") log_error "$message" | tee -a "$ORCHESTRATOR_LOG" ;;
    esac
}

# Parse command line arguments
parse_args() {
    COMMAND=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            start|status|monitor|resume|cleanup|summary)
                COMMAND="$1"
                shift
                ;;
            --chunk-size)
                CHUNK_SIZE="$2"
                shift 2
                ;;
            --time)
                TIME_HOURS="$2"
                shift 2
                ;;
            --memory)
                MEMORY_GB="$2"
                shift 2
                ;;
            --partition)
                PARTITION="$2"
                shift 2
                ;;
            --account)
                ACCOUNT="$2"
                shift 2
                ;;
            --auto-resume)
                AUTO_RESUME=true
                shift
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$COMMAND" ]]; then
        log_error "No command specified"
        show_usage
        exit 1
    fi
}

show_usage() {
    cat << EOF
SLURM PubMed Drug Analysis Orchestrator

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    start        Start the analysis (submit initial jobs)
    status       Check current processing status
    monitor      Monitor running jobs
    resume       Resume/resubmit jobs for remaining drugs
    cleanup      Clean up completed job files
    summary      Generate final summary after all jobs complete

Options:
    --chunk-size N     Drugs per SLURM job (default: 50)
    --time HOURS       Job time limit in hours (default: 4)
    --memory GB        Memory per job in GB (default: 8)
    --partition NAME   SLURM partition (default: batch)
    --account NAME     SLURM account (optional)
    --auto-resume      Automatically resubmit failed jobs
    --max-retries N    Maximum retry attempts (default: 3)

Examples:
    # Start analysis with default settings
    $0 start

    # Start with custom resources
    $0 start --chunk-size 100 --time 8 --memory 16

    # Check status
    $0 status

    # Monitor and auto-resume failed jobs
    $0 monitor --auto-resume

    # Generate final summary
    $0 summary
EOF
}

# Check if required files exist
check_prerequisites() {
    local required_files=(
        "pubmed_drug_indications.jl"
        "slurm_pubmed_drug_indications.jl"
        "approved_drugs_dict.jl"
        "mesh_t047_headings.jl"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            return 1
        fi
    done
    
    log_success "All prerequisite files found"
    return 0
}

# Build Julia command with options
build_julia_command() {
    local cmd="julia slurm_pubmed_drug_indications.jl"
    cmd="$cmd --chunk-size $CHUNK_SIZE"
    cmd="$cmd --time $TIME_HOURS"
    cmd="$cmd --memory $MEMORY_GB"
    echo "$cmd"
}

# Start the analysis
start_analysis() {
    log_both "INFO" "Starting SLURM PubMed drug analysis"
    log_both "INFO" "Configuration: chunk-size=$CHUNK_SIZE, time=${TIME_HOURS}h, memory=${MEMORY_GB}G"
    
    if ! check_prerequisites; then
        log_both "ERROR" "Prerequisites check failed"
        exit 1
    fi
    
    # Submit initial jobs
    local julia_cmd="$(build_julia_command) --submit-remaining"
    log_both "INFO" "Executing: $julia_cmd"
    
    if $julia_cmd 2>&1 | tee -a "$ORCHESTRATOR_LOG"; then
        log_both "SUCCESS" "Initial job submission completed"
        
        # Start monitoring if auto-resume is enabled
        if [[ "$AUTO_RESUME" == "true" ]]; then
            log_both "INFO" "Auto-resume enabled, starting monitoring"
            monitor_with_auto_resume
        fi
    else
        log_both "ERROR" "Initial job submission failed"
        exit 1
    fi
}

# Check status
check_status() {
    log_both "INFO" "Checking processing status"
    
    local julia_cmd="$(build_julia_command) --status"
    $julia_cmd 2>&1 | tee -a "$ORCHESTRATOR_LOG"
    
    # Also check SLURM job status
    log_both "INFO" "Checking SLURM job status"
    local monitor_cmd="$(build_julia_command) --monitor"
    $monitor_cmd 2>&1 | tee -a "$ORCHESTRATOR_LOG"
}

# Monitor jobs with optional auto-resume
monitor_with_auto_resume() {
    local retry_count=0
    local monitoring=true
    
    log_both "INFO" "Starting job monitoring (auto-resume: $AUTO_RESUME, max-retries: $MAX_RETRIES)"
    
    while [[ "$monitoring" == "true" && "$retry_count" -le "$MAX_RETRIES" ]]; do
        log_both "INFO" "Monitoring cycle $((retry_count + 1)) of $((MAX_RETRIES + 1))"
        
        # Check job status
        local julia_cmd="$(build_julia_command) --monitor"
        local monitor_output
        monitor_output=$($julia_cmd 2>&1)
        echo "$monitor_output" | tee -a "$ORCHESTRATOR_LOG"
        
        # Check if there are running or pending jobs
        local running_jobs
        running_jobs=$(echo "$monitor_output" | grep -o "Running: [0-9]*" | grep -o "[0-9]*" || echo "0")
        local pending_jobs
        pending_jobs=$(echo "$monitor_output" | grep -o "Pending: [0-9]*" | grep -o "[0-9]*" || echo "0")
        
        if [[ "$running_jobs" == "0" && "$pending_jobs" == "0" ]]; then
            log_both "INFO" "No running or pending jobs detected"
            
            # Check if there are still drugs to process
            local status_cmd="$(build_julia_command) --status"
            local status_output
            status_output=$($status_cmd 2>&1)
            
            local remaining_drugs
            remaining_drugs=$(echo "$status_output" | grep -o "Remaining to process: [0-9]*" | grep -o "[0-9]*" || echo "0")
            
            if [[ "$remaining_drugs" -gt "0" ]]; then
                if [[ "$AUTO_RESUME" == "true" && "$retry_count" -lt "$MAX_RETRIES" ]]; then
                    log_both "WARNING" "Found $remaining_drugs unprocessed drugs, attempting resume (retry $((retry_count + 1))/$MAX_RETRIES)"
                    
                    # Submit jobs for remaining drugs
                    local resume_cmd="$(build_julia_command) --submit-remaining"
                    if $resume_cmd 2>&1 | tee -a "$ORCHESTRATOR_LOG"; then
                        log_both "SUCCESS" "Resume job submission completed"
                        retry_count=$((retry_count + 1))
                        
                        # Wait before next monitoring cycle
                        log_both "INFO" "Waiting 60 seconds before next monitoring cycle"
                        sleep 60
                    else
                        log_both "ERROR" "Resume job submission failed"
                        monitoring=false
                    fi
                else
                    log_both "WARNING" "Drugs remain unprocessed but auto-resume disabled or max retries reached"
                    monitoring=false
                fi
            else
                log_both "SUCCESS" "All drugs have been processed!"
                monitoring=false
            fi
        else
            log_both "INFO" "Jobs still running (running: $running_jobs, pending: $pending_jobs)"
            log_both "INFO" "Waiting 300 seconds before next check"
            sleep 300
        fi
    done
    
    if [[ "$retry_count" -gt "$MAX_RETRIES" ]]; then
        log_both "WARNING" "Maximum retry attempts ($MAX_RETRIES) reached"
    fi
}

# Resume processing
resume_analysis() {
    log_both "INFO" "Resuming analysis for remaining drugs"
    
    local julia_cmd="$(build_julia_command) --submit-remaining"
    log_both "INFO" "Executing: $julia_cmd"
    
    if $julia_cmd 2>&1 | tee -a "$ORCHESTRATOR_LOG"; then
        log_both "SUCCESS" "Resume job submission completed"
        
        # Start monitoring if auto-resume is enabled
        if [[ "$AUTO_RESUME" == "true" ]]; then
            log_both "INFO" "Auto-resume enabled, starting monitoring"
            monitor_with_auto_resume
        fi
    else
        log_both "ERROR" "Resume job submission failed"
        exit 1
    fi
}

# Clean up completed job files
cleanup_jobs() {
    log_both "INFO" "Cleaning up completed SLURM job files"
    
    # Create cleanup directory
    local cleanup_dir="slurm_cleanup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$cleanup_dir"
    
    # Move old output files
    if [[ -d "slurm_outputs" ]]; then
        local file_count
        file_count=$(find slurm_outputs -name "*.out" -o -name "*.err" | wc -l)
        if [[ "$file_count" -gt "0" ]]; then
            mv slurm_outputs/* "$cleanup_dir/" 2>/dev/null || true
            log_both "INFO" "Moved $file_count output files to $cleanup_dir"
        fi
    fi
    
    # Archive old scripts
    if [[ -d "slurm_scripts" ]]; then
        local script_count
        script_count=$(find slurm_scripts -name "*.sh" | wc -l)
        if [[ "$script_count" -gt "0" ]]; then
            tar -czf "$cleanup_dir/slurm_scripts.tar.gz" slurm_scripts/
            rm -f slurm_scripts/*.sh
            log_both "INFO" "Archived $script_count script files"
        fi
    fi
    
    log_both "SUCCESS" "Cleanup completed, files moved to $cleanup_dir"
}

# Generate final summary
generate_summary() {
    log_both "INFO" "Generating final analysis summary"
    
    # Run the original program to generate comprehensive summary
    if julia pubmed_drug_indications.jl 2>&1 | tee -a "$ORCHESTRATOR_LOG"; then
        log_both "SUCCESS" "Final summary generation completed"
        
        # Display summary files
        log_both "INFO" "Summary files generated:"
        for file in drug_disease_associations.json drug_disease_associations.txt drug_disease_publications.json; do
            if [[ -f "$file" ]]; then
                local size
                size=$(du -h "$file" | cut -f1)
                log_both "INFO" "  - $file ($size)"
            fi
        done
        
        # Check drug_pubmed_refs directory
        if [[ -d "drug_pubmed_refs" ]]; then
            local drug_files
            drug_files=$(find drug_pubmed_refs -name "*.json" | wc -l)
            log_both "INFO" "  - drug_pubmed_refs/ ($drug_files individual drug files)"
        fi
        
    else
        log_both "ERROR" "Final summary generation failed"
        exit 1
    fi
}

# Monitor jobs without auto-resume
monitor_jobs() {
    log_both "INFO" "Monitoring SLURM jobs"
    
    local julia_cmd="$(build_julia_command) --monitor"
    $julia_cmd 2>&1 | tee -a "$ORCHESTRATOR_LOG"
}

# Main execution
main() {
    parse_args "$@"
    
    log_both "INFO" "SLURM PubMed Analysis Orchestrator started"
    log_both "INFO" "Command: $COMMAND"
    log_both "INFO" "Log file: $ORCHESTRATOR_LOG"
    
    case "$COMMAND" in
        "start")
            start_analysis
            ;;
        "status")
            check_status
            ;;
        "monitor")
            if [[ "$AUTO_RESUME" == "true" ]]; then
                monitor_with_auto_resume
            else
                monitor_jobs
            fi
            ;;
        "resume")
            resume_analysis
            ;;
        "cleanup")
            cleanup_jobs
            ;;
        "summary")
            generate_summary
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
    
    log_both "SUCCESS" "Orchestrator completed successfully"
}

# Execute main function with all arguments
main "$@"
