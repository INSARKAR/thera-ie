#!/usr/bin/env julia

"""
Simple test for GPU session management functionality
"""

using Dates

function test_gpu_session_check()
    println("🧪 Testing GPU Session Management")
    println("="^40)
    
    # Test environment detection
    job_id = get(ENV, "SLURM_JOB_ID", nothing)
    println("SLURM Job ID: $(job_id === nothing ? "None" : job_id)")
    
    hostname = try
        readchomp(`hostname`)
    catch
        "unknown"
    end
    println("Hostname: $hostname")
    
    # Test session validity function
    function check_gpu_session_validity()
        job_id = get(ENV, "SLURM_JOB_ID", nothing)
        if job_id === nothing
            return false, "No SLURM job"
        end
        
        try
            # Check job status with squeue
            result = readchomp(`squeue -j $job_id -h -o "%T"`)
            if result == "RUNNING"
                hostname = readchomp(`hostname`)
                if occursin("gpu", hostname)
                    return true, "Active on $hostname"
                else
                    return false, "Not on GPU node"
                end
            else
                return false, "Job status: $result"
            end
        catch e
            return false, "Error checking job: $e"
        end
    end
    
    is_valid, msg = check_gpu_session_validity()
    println("Session Valid: $is_valid")
    println("Status: $msg")
    
    # Test file paths
    OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
    DRUG_FILES_DIR = "/users/isarkar/sarkarcode/thera/phase1_drug_pubmed_refs"
    
    println("\nDirectory Tests:")
    println("Drug files dir exists: $(isdir(DRUG_FILES_DIR))")
    println("Output dir exists: $(isdir(OUTPUT_DIR))")
    
    if isdir(DRUG_FILES_DIR)
        drug_files = [f for f in readdir(DRUG_FILES_DIR) if endswith(f, ".json")]
        println("Drug files found: $(length(drug_files))")
        if length(drug_files) > 0
            println("First few: $(join(drug_files[1:min(3, length(drug_files))], ", "))")
        end
    end
    
    if isdir(OUTPUT_DIR)
        result_files = [f for f in readdir(OUTPUT_DIR) if endswith(f, "_llama_extracted.json")]
        println("Result files found: $(length(result_files))")
        if length(result_files) > 0
            println("First few: $(join(result_files[1:min(3, length(result_files))], ", "))")
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    test_gpu_session_check()
end
