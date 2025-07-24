#!/usr/bin/env julia

"""
HPC Setup and Runner Script for Llama Drug Indication Extractor

This script automatically handles GPU resource allocation and Ollama setup in HPC environments.

Usage:
  julia hpc_setup_and_run.jl                    # Full analysis of all drugs
  julia hpc_setup_and_run.jl --test             # Test mode (3 files only)
  julia hpc_setup_and_run.jl --drug DrugName    # Single drug analysis
  julia hpc_setup_and_run.jl --status           # Check system status only

Prerequisites:
  1. Must be run from within a GPU interactive session:
     interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00
  2. Ollama module must be available:
     module load ollama
"""

using Pkg
using HTTP
using JSON3
using Dates

# Configuration constants
const DRUG_FILES_DIR = "/users/isarkar/sarkarcode/thera/phase1_drug_pubmed_refs"
const OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"

function check_gpu_resources()
    println("🔧 Checking HPC GPU environment...")
    println("="^60)
    
    # Check if we're already in an interactive session
    job_id = get(ENV, "SLURM_JOB_ID", nothing)
    if job_id !== nothing
        println("✓ Already in SLURM job: $job_id")
        
        # Check if we're on a GPU node or login node
        hostname = readchomp(`hostname`)
        if occursin("gpu", hostname)
            println("✓ Already on GPU node: $hostname")
            return hostname
        else
            println("⚠️  On login/compute node: $hostname - will need to SSH to GPU")
            return "login_node"
        end
    else
        println("❌ Not in a SLURM GPU session")
        println("Please run this script from within a GPU interactive session:")
        println("  interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00")
        println("  julia hpc_setup_and_run.jl")
        return false
    end
end

function load_ollama_module(gpu_node=nothing)
    println("\n📦 Loading Ollama module...")
    
    if gpu_node !== nothing && gpu_node != "login_node"
        # Load module on GPU node via SSH
        try
            run(`ssh $gpu_node "module load ollama"`)
            println("✓ Ollama module loaded successfully on $gpu_node")
            return true
        catch e
            println("❌ Failed to load Ollama module on $gpu_node: $e")
            println("Try manually: ssh $gpu_node module load ollama")
            return false
        end
    else
        # Load module locally
        try
            run(`module load ollama`)
            println("✓ Ollama module loaded successfully")
            return true
        catch e
            println("❌ Failed to load Ollama module: $e")
            println("Please manually run: module load ollama")
            return false
        end
    end
end

function start_ollama_server(gpu_node=nothing)
    println("\n🚀 Starting Ollama server...")
    
    if gpu_node !== nothing && gpu_node != "login_node"
        println("Starting Ollama server on GPU node: $gpu_node")
        
        # Check if Ollama is already running on GPU node
        try
            result = readchomp(`ssh $gpu_node "curl -s http://localhost:11434/api/tags --connect-timeout 2"`)
            if !isempty(result) && !occursin("curl:", result) && !occursin("Connection refused", result)
                println("✓ Ollama server is already running on $gpu_node")
                return true
            end
        catch
            # Server not running, need to start it
            println("Ollama server not running on $gpu_node, starting it...")
        end
        
        try
            # Load ollama module on remote node first
            println("Loading Ollama module on GPU node...")
            try
                run(`ssh $gpu_node "module load ollama"`)
                println("✓ Ollama module loaded on $gpu_node")
            catch e
                println("⚠️  Could not load Ollama module on GPU node: $e")
                println("Will try to start Ollama anyway...")
            end
            
            # Start ollama serve on GPU node in background
            println("Starting Ollama server on $gpu_node...")
            run(`ssh $gpu_node "nohup ollama serve > /tmp/ollama.log 2>&1 &"`)
            
            # Wait for server to start
            println("Waiting for Ollama server to start on $gpu_node...")
            for attempt in 1:30
                try
                    result = readchomp(`ssh $gpu_node "curl -s http://localhost:11434/api/tags --connect-timeout 2"`)
                    if !isempty(result) && !occursin("curl:", result) && !occursin("Connection refused", result)
                        println("✓ Ollama server started successfully on $gpu_node")
                        return true
                    end
                catch
                    # Continue waiting
                end
                sleep(1)
                print(".")
            end
            
            println("\n❌ Ollama server failed to start within 30 seconds on $gpu_node")
            
            # Try to get error information
            try
                log_content = readchomp(`ssh $gpu_node "tail -10 /tmp/ollama.log 2>/dev/null || echo 'No log file found'"`)
                println("Ollama log output:")
                println(log_content)
            catch
                println("Could not retrieve Ollama log")
            end
            
            return false
            
        catch e
            println("❌ Failed to start Ollama server on $gpu_node: $e")
            println("Try manually: ssh $gpu_node ollama serve &")
            return false
        end
        
    else
        # Local start (for when already on GPU node)
        try
            response = HTTP.get("http://localhost:11434/api/tags", connect_timeout=2)
            if response.status == 200
                println("✓ Ollama server is already running locally")
                return true
            end
        catch
            # Server not running, need to start it
        end
        
        try
            # Start ollama serve in background locally
            spawn(`ollama serve`)
            
            # Wait for server to start
            println("Waiting for Ollama server to start locally...")
            for attempt in 1:30
                try
                    response = HTTP.get("http://localhost:11434/api/tags", connect_timeout=2)
                    if response.status == 200
                        println("✓ Ollama server started successfully locally")
                        return true
                    end
                catch
                    sleep(1)
                    print(".")
                end
            end
            
            println("\n❌ Ollama server failed to start within 30 seconds locally")
            return false
            
        catch e
            println("❌ Failed to start Ollama server locally: $e")
            println("Please manually run: ollama serve &")
            return false
        end
    end
end

function check_gpu_assignment()
    println("\n🔍 Checking GPU assignment...")
    
    try
        # Run myq command to get job info
        result = readchomp(`myq`)
        println("Current job status:")
        println(result)
        
        # Extract GPU node name from myq output
        lines = split(result, '\n')
        gpu_node = nothing
        
        for line in lines
            if occursin("gpu", lowercase(line)) && occursin("Running", line)
                # Look for gpuXXXX pattern
                match_result = match(r"gpu\d+", line)
                if match_result !== nothing
                    gpu_node = match_result.match
                    break
                end
            end
        end
        
        if gpu_node !== nothing
            println("✓ Assigned to GPU node: $gpu_node")
            return gpu_node
        else
            println("⚠️  Could not determine GPU node assignment")
            println("Please check 'myq' output manually")
            return nothing
        end
        
    catch e
        println("❌ Failed to check GPU assignment: $e")
        println("Please manually run: myq")
        return nothing
    end
end

function setup_ssh_connection(gpu_node)
    if gpu_node === nothing
        println("\n⚠️  Skipping SSH setup - no GPU node detected")
        return false
    end
    
    println("\n🔗 Setting up SSH connection to $gpu_node...")
    
    # Test SSH connectivity with a simple command
    try
        println("Testing SSH connection...")
        result = strip(readchomp(`ssh -o ConnectTimeout=10 -o BatchMode=yes $gpu_node hostname`))
        
        if result == gpu_node
            println("✓ SSH connection to $gpu_node is working")
            
            # Test Julia availability on remote node
            println("Testing Julia availability on remote node...")
            julia_version = strip(readchomp(`ssh $gpu_node "julia --version"`))
            println("✓ Julia available on $gpu_node: $julia_version")
            
            # Test Ollama availability on remote node
            println("Testing Ollama availability on remote node...")
            try
                ollama_version = strip(readchomp(`ssh $gpu_node "which ollama"`))
                println("✓ Ollama available on $gpu_node: $ollama_version")
            catch
                println("⚠️  Ollama may not be available on $gpu_node - will try to load module remotely")
            end
            
            # Set environment variable for later use
            ENV["GPU_NODE"] = gpu_node
            return true
        else
            println("⚠️  SSH test returned unexpected result: $result (expected: $gpu_node)")
            return false
        end
    catch e
        println("❌ Failed to establish SSH connection: $e")
        println("Make sure you can manually SSH to: $gpu_node")
        println("Try: ssh $gpu_node hostname")
        return false
    end
end

function test_llama_model(gpu_node=nothing)
    println("\n🤖 Testing Llama 3.2 model...")
    
    # Determine if we need to use SSH
    ssh_prefix = gpu_node !== nothing ? `ssh $gpu_node` : ``
    
    try
        # Test if model is available
        cmd = gpu_node !== nothing ? 
              `ssh $gpu_node ollama list` : 
              `ollama list`
        
        result = readchomp(cmd)
        
        if occursin("llama3.2", result)
            println("✓ Llama 3.2 model is available")
            
            # Test a simple query
            println("Testing model with simple query...")
            test_cmd = gpu_node !== nothing ?
                      `ssh $gpu_node ollama run llama3.2 "Hello, respond with just 'Working'"` :
                      `ollama run llama3.2 "Hello, respond with just 'Working'"`
            
            test_result = readchomp(test_cmd)
            println("Model response: $(strip(test_result))")
            return true
        else
            println("❌ Llama 3.2 model not found")
            println("Available models:")
            println(result)
            
            # Try to pull the model
            println("Attempting to pull llama3.2...")
            pull_cmd = gpu_node !== nothing ?
                      `ssh $gpu_node ollama pull llama3.2` :
                      `ollama pull llama3.2`
            
            run(pull_cmd)
            println("✓ Llama 3.2 model downloaded")
            return true
        end
        
    catch e
        println("❌ Failed to test Llama model: $e")
        if gpu_node !== nothing
            println("Try manually: ssh $gpu_node ollama run llama3.2")
        else
            println("Try manually: ollama run llama3.2")
        end
        return false
    end
end

function create_hpc_config()
    println("\n⚙️  Creating HPC-specific configuration...")
    
    gpu_node = get(ENV, "GPU_NODE", nothing)
    
    # Update the main extractor to use SSH if needed
    if gpu_node !== nothing
        println("✓ Configuring for GPU node: $gpu_node")
        
        # Create an environment file for the extraction process
        config_content = """
# HPC Configuration for GPU node: $gpu_node
export GPU_NODE="$gpu_node"
export OLLAMA_HOST="$gpu_node:11434"
export LLAMA_USE_SSH="true"
"""
        
        write("/users/isarkar/sarkarcode/thera/hpc_config.env", config_content)
        println("✓ HPC configuration saved to hpc_config.env")
    end
end

function run_analysis_hpc(test_mode=false, single_drug=nothing, gpu_node=nothing)
    println("\n🚀 Starting Llama extraction analysis...")
    
    if gpu_node !== nothing && gpu_node != "login_node"
        println("Running analysis on GPU node: $gpu_node")
        ENV["LLAMA_GPU_NODE"] = gpu_node
        
        # Set test mode if requested
        if test_mode
            ENV["LLAMA_TEST_MODE"] = "true"
            ENV["LLAMA_MAX_FILES"] = "3"  # Smaller test for HPC
            println("Running in TEST MODE (3 files)")
        elseif single_drug !== nothing
            ENV["LLAMA_SINGLE_DRUG"] = single_drug
            println("Running single drug analysis: $single_drug")
        end
        
        # Copy the analysis script to the GPU node and run it there
        current_dir = pwd()
        try
            # Setup remote working directory
            remote_dir = "/tmp/thera_analysis_$(ENV["SLURM_JOB_ID"])"
            println("Setting up remote directory: $remote_dir")
            run(`ssh $gpu_node mkdir -p $remote_dir`)
            
            # Copy necessary files to GPU node
            println("Copying analysis files to GPU node...")
            run(`scp llama_drug_indication_extractor.jl $gpu_node:$remote_dir/`)
            run(`scp -r phase1_drug_pubmed_refs $gpu_node:$remote_dir/`)
            
            # Also copy Project.toml and Manifest.toml if they exist
            if isfile("Project.toml")
                run(`scp Project.toml $gpu_node:$remote_dir/`)
            end
            if isfile("Manifest.toml")
                run(`scp Manifest.toml $gpu_node:$remote_dir/`)
            end
            
            # Create Julia script that sets up environment and runs analysis
            julia_script = """
#!/usr/bin/env julia

# Set environment variables
ENV["LLAMA_GPU_NODE"] = "$gpu_node"
ENV["LLAMA_TEST_MODE"] = "$(get(ENV, "LLAMA_TEST_MODE", ""))"
ENV["LLAMA_MAX_FILES"] = "$(get(ENV, "LLAMA_MAX_FILES", ""))"
ENV["LLAMA_SINGLE_DRUG"] = "$(get(ENV, "LLAMA_SINGLE_DRUG", ""))"

# Change to analysis directory
cd("$remote_dir")

# Activate project environment if available
using Pkg
if isfile("Project.toml")
    Pkg.activate(".")
    Pkg.instantiate()
end

println("🚀 Starting analysis on GPU node: $gpu_node")
println("Working directory: \$(pwd())")
println("Environment variables:")
println("  LLAMA_GPU_NODE: \$(get(ENV, "LLAMA_GPU_NODE", "not set"))")
println("  LLAMA_TEST_MODE: \$(get(ENV, "LLAMA_TEST_MODE", "not set"))")
println("  LLAMA_MAX_FILES: \$(get(ENV, "LLAMA_MAX_FILES", "not set"))")
println("  LLAMA_SINGLE_DRUG: \$(get(ENV, "LLAMA_SINGLE_DRUG", "not set"))")

# Include and run the main extractor
try
    include("llama_drug_indication_extractor.jl")
    main()  # Actually call the main function!
    println("✅ Analysis completed successfully on GPU node")
catch e
    println("❌ Analysis failed on GPU node: \$e")
    rethrow(e)
end
"""
            
            # Write Julia script to temp file and copy to GPU node
            temp_script = tempname() * ".jl"
            write(temp_script, julia_script)
            run(`scp $temp_script $gpu_node:$remote_dir/run_analysis.jl`)
            
            println("Executing analysis on GPU node $gpu_node...")
            println("Command: ssh $gpu_node 'cd $remote_dir && julia run_analysis.jl'")
            
            # Run the analysis with proper error handling
            try
                run(`ssh $gpu_node "cd $remote_dir && julia run_analysis.jl"`)
                println("✅ Analysis execution completed")
            catch e
                println("❌ Analysis execution failed: $e")
                # Try to get any error output
                try
                    error_log = readchomp(`ssh $gpu_node "cd $remote_dir && ls -la"`)
                    println("Remote directory contents:")
                    println(error_log)
                catch
                    println("Could not retrieve remote directory information")
                end
                rethrow(e)
            end
            
            # Copy results back
            println("Copying results back from GPU node...")
            run(`mkdir -p llama_pubmed_extracted_indications`)
            
            # Check if results exist before copying
            try
                result_check = readchomp(`ssh $gpu_node "ls $remote_dir/llama_pubmed_extracted_indications/ 2>/dev/null | wc -l"`)
                result_count = parse(Int, strip(result_check))
                
                if result_count > 0
                    # Use a safer approach to copy results
                    run(`scp -r $(gpu_node):$(remote_dir)/llama_pubmed_extracted_indications/ .`)
                    println("✅ Copied $result_count result files back")
                else
                    println("⚠️  No result files found in remote directory")
                end
            catch e
                println("⚠️  Error checking/copying results: $e")
            end
            
            # Clean up temp files
            rm(temp_script, force=true)
            run(`ssh $gpu_node "rm -rf $remote_dir"`)
            
            return true
            
        catch e
            println("❌ Failed to run analysis on GPU node: $e")
            # Clean up on failure
            try
                remote_dir = "/tmp/thera_analysis_$(ENV["SLURM_JOB_ID"])"
                run(`ssh $gpu_node "rm -rf $remote_dir"`)
            catch
                # Ignore cleanup errors
            end
            return false
        end
        
    else
        # Running locally (already on GPU node)
        if gpu_node !== nothing
            ENV["LLAMA_GPU_NODE"] = gpu_node
        end
        
        # Set test mode if requested
        if test_mode
            ENV["LLAMA_TEST_MODE"] = "true"
            ENV["LLAMA_MAX_FILES"] = "3"  # Smaller test for HPC
            println("Running in TEST MODE (3 files)")
        elseif single_drug !== nothing
            ENV["LLAMA_SINGLE_DRUG"] = single_drug
            println("Running single drug analysis: $single_drug")
        end
        
        # Include the main extractor
        try
            include("llama_drug_indication_extractor.jl")
            main()  # Call the main function
            return true
        catch e
            println("❌ Failed to run analysis: $e")
            return false
        end
    end
end

function check_system_status()
    println("\n📊 System Status Check")
    println("="^40)
    
    # Check SLURM job
    job_id = get(ENV, "SLURM_JOB_ID", "Not in SLURM job")
    println("SLURM Job ID: $job_id")
    
    # Check GPU assignment
    gpu_node = get(ENV, "GPU_NODE", nothing)
    if gpu_node !== nothing
        println("GPU Node: $gpu_node")
    else
        println("GPU Node: Not assigned")
    end
    
    # Check Ollama
    try
        response = HTTP.get("http://localhost:11434/api/tags", connect_timeout=2)
        if response.status == 200
            println("Ollama Server: ✓ Running")
            
            models = JSON3.read(String(response.body))
            llama_models = [m for m in models.models if occursin("llama3.2", m.name)]
            
            if !isempty(llama_models)
                println("Llama 3.2: ✓ Available")
                for model in llama_models
                    println("  - $(model.name)")
                end
            else
                println("Llama 3.2: ❌ Not found")
            end
        else
            println("Ollama Server: ❌ Not responding")
        end
    catch e
        println("Ollama Server: ❌ Cannot connect ($e)")
    end
    
    # Check directories
    drug_dir = "/users/isarkar/sarkarcode/thera/phase1_drug_pubmed_refs"
    output_dir = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
    
    if isdir(drug_dir)
        files = [f for f in readdir(drug_dir) if endswith(f, ".json")]
        println("Input files: ✓ $(length(files)) drug files found")
    else
        println("Input files: ❌ Directory not found")
    end
    
    if isdir(output_dir)
        results = [f for f in readdir(output_dir) if endswith(f, "_llama_extracted.json")]
        println("Output files: ✓ $(length(results)) result files exist")
    else
        println("Output files: Directory will be created")
    end
end

function check_gpu_session_validity()
    """Check if current GPU session is still valid and active"""
    job_id = get(ENV, "SLURM_JOB_ID", nothing)
    if job_id === nothing
        return false, "No SLURM job"
    end
    
    try
        # Check job status with squeue
        result = readchomp(`squeue -j $job_id -h -o "%T"`)
        if result == "RUNNING"
            # Also check if we can still access the GPU node
            hostname = readchomp(`hostname`)
            if occursin("gpu", hostname)
                return true, "Active on $hostname"
            else
                # Check if assigned GPU node is still accessible
                gpu_node = check_gpu_assignment()
                if gpu_node !== nothing
                    try
                        readchomp(`ssh -o ConnectTimeout=5 $gpu_node hostname`)
                        return true, "Active via SSH to $gpu_node"
                    catch
                        return false, "GPU node $gpu_node not accessible"
                    end
                else
                    return false, "No GPU node assigned"
                end
            end
        else
            return false, "Job status: $result"
        end
    catch e
        return false, "Error checking job: $e"
    end
end

function request_new_gpu_session()
    """Request a new GPU interactive session with 2-hour duration"""
    println("🔄 Requesting new GPU session (2 hours)...")
    
    try
        # Submit interactive job request with 2-hour time limit
        println("Submitting SLURM job request...")
        run(`srun --job-name=llama_extraction --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=4 --mem=32G --time=2:00:00 --pty bash -c "cd $(pwd()) && export SLURM_JOB_ID=\$SLURM_JOB_ID && julia hpc_setup_and_run.jl --resume"`)
        return true
    catch e
        println("❌ Failed to request new GPU session: $e")
        return false
    end
end

function get_processed_drugs()
    """Get list of drugs that have already been processed"""
    processed = String[]
    if isdir(OUTPUT_DIR)
        for file in readdir(OUTPUT_DIR)
            if endswith(file, "_llama_extracted.json")
                drug_name = replace(file, "_llama_extracted.json" => "")
                push!(processed, drug_name)
            end
        end
    end
    return processed
end

function get_pending_drugs(max_files=0)
    """Get list of drugs that still need to be processed"""
    if !isdir(DRUG_FILES_DIR)
        return String[]
    end
    
    all_drugs = String[]
    for file in readdir(DRUG_FILES_DIR)
        if endswith(file, ".json")
            drug_name = replace(file, ".json" => "")
            push!(all_drugs, drug_name)
        end
    end
    
    processed = get_processed_drugs()
    pending = setdiff(all_drugs, processed)
    
    if max_files > 0 && length(pending) > max_files
        return pending[1:max_files]
    end
    
    return pending
end

function save_processing_state(current_drug, completed_drugs, failed_drugs)
    """Save current processing state to resume later"""
    state = Dict(
        "current_drug" => current_drug,
        "completed_drugs" => completed_drugs,
        "failed_drugs" => failed_drugs,
        "last_update" => string(now()),
        "session_start" => get(ENV, "SESSION_START_TIME", string(now()))
    )
    
    write("processing_state.json", JSON3.write(state, allow_inf=true))
end

function load_processing_state()
    """Load previous processing state"""
    if isfile("processing_state.json")
        try
            content = read("processing_state.json", String)
            return JSON3.read(content)
        catch e
            println("⚠️  Could not load processing state: $e")
        end
    end
    return nothing
end

function run_analysis_with_session_management(test_mode=false, single_drug=nothing, resume_mode=false, processing_state=nothing)
    """Main processing function with GPU session management"""
    
    # Initialize tracking variables
    completed_drugs = processing_state !== nothing ? processing_state.completed_drugs : String[]
    failed_drugs = processing_state !== nothing ? processing_state.failed_drugs : String[]
    total_processed = 0
    
    # Determine which drugs to process
    if single_drug !== nothing
        drugs_to_process = [single_drug]
        println("🎯 Processing single drug: $single_drug")
    elseif test_mode
        drugs_to_process = get_pending_drugs(3)  # Limit to 3 for test mode
        println("🧪 Test mode: Processing $(length(drugs_to_process)) drugs")
    else
        drugs_to_process = get_pending_drugs()
        println("🚀 Full analysis: Processing $(length(drugs_to_process)) pending drugs")
    end
    
    if isempty(drugs_to_process)
        println("✅ No drugs to process - all completed!")
        return true
    end
    
    println("📋 Drugs to process: $(join(drugs_to_process[1:min(5, length(drugs_to_process))], ", "))$(length(drugs_to_process) > 5 ? "..." : "")")
    
    # Process each drug with session checking
    for (i, drug_name) in enumerate(drugs_to_process)
        println("\n" * "="^60)
        println("🔬 Processing drug $i/$(length(drugs_to_process)): $drug_name")
        println("="^60)
        
        # Check GPU session before each drug
        is_valid, status_msg = check_gpu_session_validity()
        if !is_valid
            println("⚠️  GPU session invalid: $status_msg")
            
            # Save current state
            save_processing_state(drug_name, completed_drugs, failed_drugs)
            println("💾 Saved processing state")
            
            # Request new session
            println("🔄 Requesting new GPU session...")
            if !request_new_gpu_session()
                println("❌ Failed to get new GPU session")
                return false
            else
                # The new session will resume automatically
                return true
            end
        else
            println("✅ GPU session valid: $status_msg")
        end
        
        # Setup environment for this drug
        ENV["LLAMA_SINGLE_DRUG"] = drug_name
        if test_mode
            ENV["LLAMA_TEST_MODE"] = "true"
        end
        
        # Run analysis for this specific drug
        success = false
        try
            println("🚀 Starting analysis for $drug_name...")
            
            # Get current setup
            gpu_status = check_gpu_resources()
            if gpu_status == false
                println("❌ GPU resources not available")
                push!(failed_drugs, drug_name)
                continue
            end
            
            # Setup GPU environment
            gpu_node = setup_gpu_environment(gpu_status)
            if gpu_node === nothing
                println("❌ Could not setup GPU environment")
                push!(failed_drugs, drug_name)
                continue
            end
            
            # Run analysis
            if run_analysis_hpc(false, drug_name, gpu_node)  # Don't use test_mode here, control via env var
                println("✅ Successfully processed $drug_name")
                push!(completed_drugs, drug_name)
                success = true
            else
                println("❌ Failed to process $drug_name")
                push!(failed_drugs, drug_name)
            end
            
        catch e
            println("❌ Error processing $drug_name: $e")
            push!(failed_drugs, drug_name)
        end
        
        total_processed += 1
        
        # Save progress after each drug
        save_processing_state(drug_name, completed_drugs, failed_drugs)
        
        # Show progress
        println("\n📊 Progress Summary:")
        println("  ✅ Completed: $(length(completed_drugs))")
        println("  ❌ Failed: $(length(failed_drugs))")
        println("  📋 Remaining: $(length(drugs_to_process) - total_processed)")
        
        # Small delay to avoid overwhelming the system
        if i < length(drugs_to_process)
            println("⏳ Brief pause before next drug...")
            sleep(2)
        end
    end
    
    # Final summary
    println("\n" * "="^60)
    println("🎉 Analysis Complete!")
    println("="^60)
    println("✅ Successfully processed: $(length(completed_drugs)) drugs")
    println("❌ Failed: $(length(failed_drugs)) drugs")
    
    if !isempty(failed_drugs)
        println("\n❌ Failed drugs:")
        for drug in failed_drugs
            println("  - $drug")
        end
    end
    
    # Clean up state file if everything is done
    if isempty(get_pending_drugs())
        if isfile("processing_state.json")
            rm("processing_state.json")
            println("🧹 Cleaned up processing state file")
        end
    end
    
    return length(failed_drugs) == 0
end

function setup_gpu_environment(gpu_status)
    """Setup GPU environment and return GPU node"""
    
    # Load Ollama module if needed
    if gpu_status == "login_node" || !occursin("gpu", gpu_status)
        if !load_ollama_module()
            println("❌ Failed to load Ollama module")
            return nothing
        end
    end
    
    # Get GPU node
    gpu_node = gpu_status == "login_node" ? check_gpu_assignment() : gpu_status
    
    if gpu_node === nothing && gpu_status == "login_node"
        println("❌ Could not determine GPU node assignment")
        return nothing
    end
    
    # Setup SSH connection if needed
    if gpu_status == "login_node"
        if !setup_ssh_connection(gpu_node)
            println("❌ Could not establish SSH connection to GPU node")
            return nothing
        end
    end
    
    # Start Ollama server
    if !start_ollama_server(gpu_node)
        println("❌ Could not start Ollama server")
        return nothing
    end
    
    # Test Llama model
    if !test_llama_model(gpu_node)
        println("❌ Llama 3.2 model not working")
        return nothing
    end
    
    # Set environment variable
    if gpu_node !== nothing && gpu_node != "login_node"
        ENV["GPU_NODE"] = gpu_node
    end
    
    create_hpc_config()
    
    return gpu_node
end

function main()
    println("🏥 HPC Llama Drug Indication Extractor")
    println("Automated setup and execution for GPU cluster environments")
    println("=" * "="^50)
    
    # Parse command line arguments
    test_mode = "--test" in ARGS
    status_only = "--status" in ARGS
    help_requested = "--help" in ARGS || "-h" in ARGS
    resume_mode = "--resume" in ARGS
    single_drug = nothing
    
    # Show help if requested
    if help_requested
        println("\nUsage:")
        println("  julia hpc_setup_and_run.jl                    # Full analysis of all drugs")
        println("  julia hpc_setup_and_run.jl --test             # Test mode (3 files only)")
        println("  julia hpc_setup_and_run.jl --drug DrugName    # Single drug analysis")
        println("  julia hpc_setup_and_run.jl --status           # Check system status only")
        println("  julia hpc_setup_and_run.jl --resume           # Resume previous analysis")
        println("  julia hpc_setup_and_run.jl --help             # Show this help")
        println("\nFeatures:")
        println("  - Automatic GPU session management (2-hour sessions)")
        println("  - Resume capability after timeouts")
        println("  - Per-drug GPU availability checking")
        println("\nPrerequisites:")
        println("  1. Must be in GPU interactive session: interact -n 4 -m 32g -q gpu -g 1 -t 2:00:00")
        println("  2. Ollama module must be loaded: module load ollama")
        return
    end
    
    # Look for single drug argument
    for (i, arg) in enumerate(ARGS)
        if arg == "--drug" && i < length(ARGS)
            single_drug = ARGS[i + 1]
            break
        end
    end
    
    # If status only, run status check and exit
    if status_only
        check_system_status()
        return
    end
    
    # Set session start time
    if !haskey(ENV, "SESSION_START_TIME")
        ENV["SESSION_START_TIME"] = string(now())
    end
    
    if test_mode
        println("Running in TEST MODE (3 files)")
    elseif single_drug !== nothing
        println("Running single drug analysis: $single_drug")
    elseif resume_mode
        println("RESUMING previous analysis")
    else
        println("Running FULL analysis with auto-resumption")
    end
    
    # Load previous state if resuming
    processing_state = resume_mode ? load_processing_state() : nothing
    if processing_state !== nothing
        println("📊 Loaded previous state:")
        println("  - Completed drugs: $(length(processing_state.completed_drugs))")
        println("  - Failed drugs: $(length(processing_state.failed_drugs))")
        println("  - Last drug: $(processing_state.current_drug)")
    end
    
    # Main processing loop with GPU session management
    run_analysis_with_session_management(test_mode, single_drug, resume_mode, processing_state)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
