#!/usr/bin/env julia

"""
SLURM-Enhanced PubMed Drug Indications Analysis

This enhanced version of the PubMed drug indications pipeline includes:
1. SLURM job management for long-term processing
2. Automatic job submission for remaining drugs
3. Batch processing with configurable chunk sizes
4. Resume capability across SLURM jobs
5. Job monitoring and status reporting

Usage:
    julia slurm_pubmed_drug_indications.jl [OPTIONS]

Options:
    --chunk-size N     Process N drugs per SLURM job (default: 50)
    --time HOURS       SLURM job time limit in hours (default: 4)
    --memory GB        Memory per job in GB (default: 8)
    --status           Check processing status only
    --submit-remaining Submit SLURM jobs for remaining drugs
    --monitor          Monitor currently running SLURM jobs
    --single-job       Run in single job mode (process all assigned drugs)

Environment Variables:
    SLURM_DRUG_START   Starting drug index for this job
    SLURM_DRUG_END     Ending drug index for this job
    SLURM_CHUNK_ID     Chunk ID for this job
"""

using Pkg
using HTTP
using JSON3
using Dates
using Distributed

# Import all functions from the original program
include("pubmed_drug_indications.jl")

# SLURM Configuration
struct SlurmConfig
    chunk_size::Int
    time_hours::Int
    memory_gb::Int
    partition::String
    account::String
    email::String
    
    function SlurmConfig(;
        chunk_size::Int=50,
        time_hours::Int=4,
        memory_gb::Int=8,
        partition::String="batch",
        account::String="",
        email::String="neil_sarkar@brown.edu"
    )
        new(chunk_size, time_hours, memory_gb, partition, account, email)
    end
end

# Global configuration
const SLURM_CONFIG = SlurmConfig()
const SLURM_OUTPUT_DIR = "slurm_outputs"
const SLURM_SCRIPTS_DIR = "slurm_scripts"

"""
    create_slurm_directories()

Create necessary directories for SLURM outputs and scripts.
"""
function create_slurm_directories()
    for dir in [SLURM_OUTPUT_DIR, SLURM_SCRIPTS_DIR]
        if !isdir(dir)
            mkpath(dir)
            println("✓ Created directory: $dir")
        end
    end
end

"""
    get_slurm_job_status(job_ids::Vector{String}) -> Dict

Check the status of SLURM jobs.
"""
function get_slurm_job_status(job_ids::Vector{String})
    if isempty(job_ids)
        return Dict("running" => String[], "completed" => String[], "failed" => String[], "pending" => String[])
    end
    
    job_status = Dict("running" => String[], "completed" => String[], "failed" => String[], "pending" => String[])
    
    for job_id in job_ids
        try
            # Use sacct to check job status
            result = readchomp(`sacct -j $job_id -n -o State`)
            status = strip(result)
            
            if occursin("RUNNING", status)
                push!(job_status["running"], job_id)
            elseif occursin("COMPLETED", status)
                push!(job_status["completed"], job_id)
            elseif occursin("FAILED", status) || occursin("CANCELLED", status) || occursin("TIMEOUT", status)
                push!(job_status["failed"], job_id)
            elseif occursin("PENDING", status)
                push!(job_status["pending"], job_id)
            end
        catch e
            println("⚠️  Warning: Could not check status for job $job_id: $e")
        end
    end
    
    return job_status
end

"""
    create_slurm_script(chunk_id::Int, drug_start::Int, drug_end::Int, config::SlurmConfig) -> String

Create a SLURM batch script for processing a chunk of drugs.
"""
function create_slurm_script(chunk_id::Int, drug_start::Int, drug_end::Int, config::SlurmConfig)
    script_name = "pubmed_chunk_$(chunk_id).sh"
    script_path = joinpath(SLURM_SCRIPTS_DIR, script_name)
    
    script_content = """#!/bin/bash
#SBATCH --job-name=pubmed_drugs_$(chunk_id)
#SBATCH --output=$(SLURM_OUTPUT_DIR)/pubmed_chunk_$(chunk_id)_%j.out
#SBATCH --error=$(SLURM_OUTPUT_DIR)/pubmed_chunk_$(chunk_id)_%j.err
#SBATCH --time=$(config.time_hours):00:00
#SBATCH --mem=$(config.memory_gb)G
#SBATCH --partition=$(config.partition)
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4"""

    if !isempty(config.account)
        script_content *= "\n#SBATCH --account=$(config.account)"
    end
    
    if !isempty(config.email)
        script_content *= "\n#SBATCH --mail-type=END,FAIL"
        script_content *= "\n#SBATCH --mail-user=$(config.email)"
    end

    script_content *= """

# Set environment variables for this chunk
export SLURM_DRUG_START=$drug_start
export SLURM_DRUG_END=$drug_end
export SLURM_CHUNK_ID=$chunk_id

# Load Julia module if available
module load julia 2>/dev/null || echo "Julia module not available, using system Julia"

# Navigate to the working directory
cd \${SLURM_SUBMIT_DIR}

# Run the analysis for this chunk
echo "Starting PubMed analysis for chunk $chunk_id (drugs $drug_start to $drug_end)"
echo "Started at: \$(date)"
echo "Node: \$(hostname)"
echo "Working directory: \$(pwd)"

# Run the Julia program in single-job mode
julia slurm_pubmed_drug_indications.jl --single-job

echo "Completed at: \$(date)"
"""

    # Write the script
    open(script_path, "w") do file
        write(file, script_content)
    end
    
    # Make script executable
    run(`chmod +x $script_path`)
    
    return script_path
end

"""
    submit_slurm_job(script_path::String) -> String

Submit a SLURM job and return the job ID.
"""
function submit_slurm_job(script_path::String)
    try
        result = readchomp(`sbatch $script_path`)
        # Extract job ID from "Submitted batch job XXXXXX"
        job_id_match = match(r"(\d+)", result)
        if job_id_match !== nothing
            return job_id_match.captures[1]
        else
            error("Could not extract job ID from: $result")
        end
    catch e
        error("Failed to submit SLURM job: $e")
    end
end

"""
    calculate_drug_chunks(total_drugs::Int, drugs_per_chunk::Int) -> Vector{Tuple{Int,Int}}

Calculate drug index ranges for each chunk.
"""
function calculate_drug_chunks(total_drugs::Int, drugs_per_chunk::Int)
    chunks = Vector{Tuple{Int,Int}}()
    
    for start_idx in 1:drugs_per_chunk:total_drugs
        end_idx = min(start_idx + drugs_per_chunk - 1, total_drugs)
        push!(chunks, (start_idx, end_idx))
    end
    
    return chunks
end

"""
    submit_remaining_drugs_to_slurm(config::SlurmConfig=SLURM_CONFIG) -> Vector{String}

Submit SLURM jobs for all remaining unprocessed drugs.
"""
function submit_remaining_drugs_to_slurm(config::SlurmConfig=SLURM_CONFIG)
    println("🚀 Submitting SLURM jobs for remaining drugs...")
    
    # Create necessary directories
    create_slurm_directories()
    
    # Load drug data
    drugs_dict = load_approved_drugs()
    output_dir = "drug_pubmed_refs"
    
    # Get processing status
    status = get_processing_status(drugs_dict, output_dir)
    
    if status["remaining_to_process"] == 0
        println("✅ All drugs have been processed! No jobs to submit.")
        return String[]
    end
    
    # Get list of unprocessed drugs
    remaining_drugs = collect(status["remaining_drugs"])
    total_remaining = length(remaining_drugs)
    
    println("📊 Processing Status:")
    println("  • Total drugs: $(status["total_drugs"])")
    println("  • Already processed: $(status["already_processed"])")
    println("  • Remaining to process: $total_remaining")
    println("  • Completion: $(status["completion_percentage"])%")
    println()
    
    # Calculate chunks
    chunks = calculate_drug_chunks(total_remaining, config.chunk_size)
    num_chunks = length(chunks)
    
    println("📦 Will create $num_chunks SLURM jobs:")
    println("  • Drugs per job: $(config.chunk_size)")
    println("  • Time per job: $(config.time_hours) hours")
    println("  • Memory per job: $(config.memory_gb) GB")
    println("  • Partition: $(config.partition)")
    println()
    
    # Submit jobs
    submitted_job_ids = Vector{String}()
    
    for (chunk_id, (start_idx, end_idx)) in enumerate(chunks)
        actual_start = start_idx
        actual_end = min(end_idx, total_remaining)
        chunk_size = actual_end - actual_start + 1
        
        println("📤 Submitting chunk $chunk_id/$num_chunks (drugs $actual_start-$actual_end, $chunk_size drugs)...")
        
        # Create SLURM script
        script_path = create_slurm_script(chunk_id, actual_start, actual_end, config)
        
        # Submit job
        try
            job_id = submit_slurm_job(script_path)
            push!(submitted_job_ids, job_id)
            println("    ✅ Job submitted: $job_id")
        catch e
            println("    ❌ Failed to submit chunk $chunk_id: $e")
        end
        
        # Small delay between submissions
        sleep(0.1)
    end
    
    println()
    println("🎯 Job Submission Summary:")
    println("  • Jobs submitted: $(length(submitted_job_ids))/$num_chunks")
    println("  • Total drugs to be processed: $total_remaining")
    println("  • Job IDs: $(join(submitted_job_ids, ", "))")
    
    # Save job tracking information
    job_info = Dict(
        "submitted_at" => string(now()),
        "total_jobs" => length(submitted_job_ids),
        "job_ids" => submitted_job_ids,
        "chunks" => chunks,
        "config" => Dict(
            "chunk_size" => config.chunk_size,
            "time_hours" => config.time_hours,
            "memory_gb" => config.memory_gb,
            "partition" => config.partition
        ),
        "remaining_drugs" => remaining_drugs
    )
    
    job_tracking_file = "slurm_job_tracking.json"
    open(job_tracking_file, "w") do file
        write(file, JSON3.write(job_info))
    end
    println("  • Job tracking saved: $job_tracking_file")
    
    println()
    println("📋 Next Steps:")
    println("  • Monitor jobs: julia slurm_pubmed_drug_indications.jl --monitor")
    println("  • Check status: julia slurm_pubmed_drug_indications.jl --status")
    println("  • View outputs: ls $(SLURM_OUTPUT_DIR)/")
    
    return submitted_job_ids
end

"""
    process_drug_chunk_from_environment()

Process a chunk of drugs based on environment variables set by SLURM.
"""
function process_drug_chunk_from_environment()
    # Get chunk information from environment
    drug_start = parse(Int, get(ENV, "SLURM_DRUG_START", "1"))
    drug_end = parse(Int, get(ENV, "SLURM_DRUG_END", "1"))
    chunk_id = get(ENV, "SLURM_CHUNK_ID", "unknown")
    
    println("🔧 SLURM Chunk Processing Mode")
    println("=" ^ 35)
    println("Chunk ID: $chunk_id")
    println("Drug range: $drug_start to $drug_end")
    println("SLURM Job ID: $(get(ENV, "SLURM_JOB_ID", "unknown"))")
    println("Node: $(readchomp(`hostname`))")
    println("Started at: $(now())")
    println()
    
    try
        # Load data
        println("Loading required data...")
        drugs_dict = load_approved_drugs()
        mesh_file = "mesh_t047_headings.jl"
        disease_headings = load_mesh_disease_headings(mesh_file)
        
        # Get list of remaining drugs (those not yet processed)
        output_dir = "drug_pubmed_refs"
        status = get_processing_status(drugs_dict, output_dir)
        remaining_drugs = collect(status["remaining_drugs"])
        
        # Select drugs for this chunk
        chunk_drugs = remaining_drugs[drug_start:min(drug_end, length(remaining_drugs))]
        
        println("✓ Loaded $(length(drugs_dict)) total drugs")
        println("✓ Found $(length(remaining_drugs)) remaining drugs")
        println("✓ Will process $(length(chunk_drugs)) drugs in this chunk")
        println("✓ Loaded $(length(disease_headings)) MeSH disease headings")
        println()
        
        if isempty(chunk_drugs)
            println("⚠️  No drugs to process in this chunk (all may be completed)")
            return
        end
        
        # Process drugs in this chunk
        drugs_processed = 0
        successful_searches = 0
        successful_analyses = 0
        total_diseases = 0
        total_pubs_analyzed = 0
        
        for (i, drug_name) in enumerate(chunk_drugs)
            indication = drugs_dict[drug_name]
            
            println("[$i/$(length(chunk_drugs))] Processing: $drug_name")
            println("  FDA Indication: $(indication[1:min(100, length(indication))])...")
            
            # Check if already processed (additional safety check)
            if should_skip_drug(drug_name, output_dir)
                println("    ⏭️  Already processed, skipping")
                continue
            end
            
            # Process the drug
            start_time = time()
            result = process_drug_memory_efficient(drug_name, indication, disease_headings, output_dir)
            processing_time = time() - start_time
            
            # Update counters
            drugs_processed += 1
            if get(result, "search_status", "") == "success"
                successful_searches += 1
            end
            if get(result, "disease_associations_count", 0) > 0
                successful_analyses += 1
                total_diseases += result["disease_associations_count"]
            end
            total_pubs_analyzed += get(result, "publications_analyzed_count", 0)
            
            println("    ✓ Completed in $(round(processing_time, digits=1))s")
            
            # Progress update
            if i % 5 == 0
                println()
                println("  📊 Progress Update:")
                println("    • Processed: $i/$(length(chunk_drugs)) drugs")
                println("    • Successful searches: $successful_searches")
                println("    • Disease associations found: $total_diseases")
                println("    • Publications analyzed: $total_pubs_analyzed")
                println()
            end
            
            # Small delay between drugs
            sleep(0.1)
        end
        
        # Final summary for this chunk
        println()
        println("🎯 Chunk $chunk_id Completed!")
        println("=" ^ 25)
        println("Drugs processed: $drugs_processed")
        println("Successful searches: $successful_searches")
        println("Successful analyses: $successful_analyses")
        println("Total disease associations: $total_diseases")
        println("Total publications analyzed: $total_pubs_analyzed")
        println("Completed at: $(now())")
        
        # Clean up resources
        cleanup_optimizations()
        
    catch e
        println("❌ Error in chunk processing: $e")
        println("Stacktrace:")
        println(stacktrace())
        exit(1)
    end
end

"""
    monitor_slurm_jobs()

Monitor the status of submitted SLURM jobs.
"""
function monitor_slurm_jobs()
    println("📊 Monitoring SLURM Jobs")
    println("=" ^ 23)
    
    # Load job tracking information
    job_tracking_file = "slurm_job_tracking.json"
    if !isfile(job_tracking_file)
        println("❌ No job tracking file found: $job_tracking_file")
        println("   Run with --submit-remaining first to submit jobs")
        return
    end
    
    job_info = JSON3.read(read(job_tracking_file, String))
    job_ids = job_info["job_ids"]
    
    println("Job tracking file: $job_tracking_file")
    println("Jobs submitted at: $(job_info["submitted_at"])")
    println("Total jobs: $(length(job_ids))")
    println()
    
    # Check job status
    status = get_slurm_job_status(job_ids)
    
    println("📈 Job Status:")
    println("  • Running: $(length(status["running"]))")
    println("  • Completed: $(length(status["completed"]))")
    println("  • Failed: $(length(status["failed"]))")
    println("  • Pending: $(length(status["pending"]))")
    println()
    
    if !isempty(status["running"])
        println("🏃 Running Jobs:")
        for job_id in status["running"]
            println("  • Job $job_id")
        end
        println()
    end
    
    if !isempty(status["completed"])
        println("✅ Completed Jobs:")
        for job_id in status["completed"]
            println("  • Job $job_id")
        end
        println()
    end
    
    if !isempty(status["failed"])
        println("❌ Failed Jobs:")
        for job_id in status["failed"]
            println("  • Job $job_id")
        end
        println()
    end
    
    if !isempty(status["pending"])
        println("⏳ Pending Jobs:")
        for job_id in status["pending"]
            println("  • Job $job_id")
        end
        println()
    end
    
    # Check overall processing status
    try
        drugs_dict = load_approved_drugs()
        output_dir = "drug_pubmed_refs"
        processing_status = get_processing_status(drugs_dict, output_dir)
        
        println("📊 Overall Processing Status:")
        println("  • Total drugs: $(processing_status["total_drugs"])")
        println("  • Already processed: $(processing_status["already_processed"])")
        println("  • Remaining: $(processing_status["remaining_to_process"])")
        println("  • Completion: $(processing_status["completion_percentage"])%")
        
        if processing_status["remaining_to_process"] > 0 && length(status["running"]) == 0 && length(status["pending"]) == 0
            println()
            println("💡 Suggestion: All jobs completed but drugs remain.")
            println("   Some jobs may have failed. Check logs and resubmit:")
            println("   julia slurm_pubmed_drug_indications.jl --submit-remaining")
        end
        
    catch e
        println("⚠️  Could not check processing status: $e")
    end
end

"""
    parse_command_line_args() -> Dict

Parse command line arguments.
"""
function parse_command_line_args()
    args = Dict(
        "chunk_size" => 50,
        "time_hours" => 4,
        "memory_gb" => 8,
        "status" => false,
        "submit_remaining" => false,
        "monitor" => false,
        "single_job" => false
    )
    
    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        
        if arg == "--chunk-size" && i < length(ARGS)
            args["chunk_size"] = parse(Int, ARGS[i+1])
            i += 2
        elseif arg == "--time" && i < length(ARGS)
            args["time_hours"] = parse(Int, ARGS[i+1])
            i += 2
        elseif arg == "--memory" && i < length(ARGS)
            args["memory_gb"] = parse(Int, ARGS[i+1])
            i += 2
        elseif arg == "--status"
            args["status"] = true
            i += 1
        elseif arg == "--submit-remaining"
            args["submit_remaining"] = true
            i += 1
        elseif arg == "--monitor"
            args["monitor"] = true
            i += 1
        elseif arg == "--single-job"
            args["single_job"] = true
            i += 1
        else
            println("Unknown argument: $arg")
            i += 1
        end
    end
    
    return args
end

"""
    print_usage()

Print usage information.
"""
function print_usage()
    println("""
SLURM-Enhanced PubMed Drug Indications Analysis

Usage:
    julia slurm_pubmed_drug_indications.jl [OPTIONS]

Options:
    --chunk-size N     Process N drugs per SLURM job (default: 50)
    --time HOURS       SLURM job time limit in hours (default: 4)
    --memory GB        Memory per job in GB (default: 8)
    --status           Check processing status only
    --submit-remaining Submit SLURM jobs for remaining drugs
    --monitor          Monitor currently running SLURM jobs
    --single-job       Run in single job mode (process assigned drugs)

Examples:
    # Check current status
    julia slurm_pubmed_drug_indications.jl --status

    # Submit jobs for remaining drugs (default settings)
    julia slurm_pubmed_drug_indications.jl --submit-remaining

    # Submit jobs with custom settings
    julia slurm_pubmed_drug_indications.jl --submit-remaining --chunk-size 100 --time 8 --memory 16

    # Monitor job progress
    julia slurm_pubmed_drug_indications.jl --monitor
""")
end

"""
    main_slurm()

Main function for SLURM-enhanced processing.
"""
function main_slurm()
    args = parse_command_line_args()
    
    # Handle special modes
    if args["single_job"]
        # This is a SLURM job processing its assigned chunk
        process_drug_chunk_from_environment()
        return
    end
    
    if args["status"]
        # Show processing status
        try
            drugs_dict = load_approved_drugs()
            output_dir = "drug_pubmed_refs"
            status = get_processing_status(drugs_dict, output_dir)
            
            println("📊 PubMed Drug Processing Status")
            println("=" ^ 32)
            println("Total drugs: $(status["total_drugs"])")
            println("Already processed: $(status["already_processed"])")
            println("Remaining to process: $(status["remaining_to_process"])")
            println("Completion: $(status["completion_percentage"])%")
            
            if status["remaining_to_process"] > 0
                estimated_jobs = ceil(Int, status["remaining_to_process"] / args["chunk_size"])
                println()
                println("To process remaining drugs:")
                println("  Estimated SLURM jobs needed: $estimated_jobs")
                println("  With chunk size: $(args["chunk_size"])")
                println()
                println("Submit jobs with:")
                println("  julia slurm_pubmed_drug_indications.jl --submit-remaining")
            end
            
        catch e
            println("❌ Error checking status: $e")
        end
        return
    end
    
    if args["monitor"]
        monitor_slurm_jobs()
        return
    end
    
    if args["submit_remaining"]
        # Submit SLURM jobs for remaining drugs
        config = SlurmConfig(
            chunk_size=args["chunk_size"],
            time_hours=args["time_hours"],
            memory_gb=args["memory_gb"]
        )
        submit_remaining_drugs_to_slurm(config)
        return
    end
    
    # Default: print usage
    print_usage()
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main_slurm()
end
