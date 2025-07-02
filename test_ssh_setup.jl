#!/usr/bin/env julia

"""
Test SSH Setup for GPU Allocation

This script tests the SSH functionality for the HPC setup.
"""

function test_environment_detection()
    println("🔧 Testing Environment Detection")
    println("="^40)
    
    # Check hostname
    hostname = strip(readchomp(`hostname`))
    println("Hostname: $hostname")
    
    # Check if we're in a SLURM job
    job_id = get(ENV, "SLURM_JOB_ID", nothing)
    if job_id !== nothing
        println("SLURM Job ID: $job_id")
        
        # Check if we're on login node or GPU node
        if occursin("login", hostname) || occursin("vscode", hostname) || !occursin("gpu", hostname)
            println("Status: On login/compute node - will need SSH to GPU")
            return "login_node"
        else
            println("Status: Already on GPU node")
            return hostname
        end
    else
        println("Status: Not in SLURM job")
        return "no_slurm"
    end
end

function test_gpu_assignment_detection()
    println("\n🔍 Testing GPU Assignment Detection")
    println("="^40)
    
    try
        # Run myq command to get job info
        result = read(`myq`, String)
        println("myq output:")
        println(result)
        
        # Extract GPU node name from myq output
        lines = split(result, '\n')
        gpu_node = nothing
        
        for line in lines
            if occursin("gpu", lowercase(line)) && (occursin("Running", line) || occursin("R", line))
                # Look for gpuXXXX pattern
                match_result = match(r"gpu\d+", line)
                if match_result !== nothing
                    gpu_node = match_result.match
                    break
                end
            end
        end
        
        if gpu_node !== nothing
            println("✓ Found GPU node: $gpu_node")
            return gpu_node
        else
            println("❌ Could not determine GPU node from myq output")
            return nothing
        end
        
    catch e
        println("❌ Failed to run myq: $e")
        return nothing
    end
end

function test_ssh_connection(gpu_node)
    if gpu_node === nothing
        println("\n⚠️  No GPU node to test SSH connection")
        return false
    end
    
    println("\n🔗 Testing SSH Connection to $gpu_node")
    println("="^40)
    
    try
        println("Testing basic SSH connectivity...")
        result = strip(readchomp(`ssh -o ConnectTimeout=10 -o BatchMode=yes $gpu_node hostname`))
        
        if result == gpu_node
            println("✅ SSH connection successful")
            
            # Test basic commands
            println("Testing Julia availability...")
            julia_version = strip(readchomp(`ssh $gpu_node "julia --version"`))
            println("✅ Julia: $julia_version")
            
            # Test module system
            println("Testing module system...")
            try
                module_result = readchomp(`ssh $gpu_node "module list 2>&1"`)
                println("✅ Module system accessible")
            catch e
                println("⚠️  Module system test failed: $e")
            end
            
            # Test Ollama availability
            println("Testing Ollama availability...")
            try
                ollama_path = strip(readchomp(`ssh $gpu_node "which ollama 2>/dev/null || echo 'not found'"`))
                if ollama_path != "not found"
                    println("✅ Ollama found at: $ollama_path")
                else
                    println("⚠️  Ollama not in PATH, will need to load module")
                end
            catch e
                println("⚠️  Ollama test failed: $e")
            end
            
            return true
        else
            println("❌ SSH test failed - got hostname: $result")
            return false
        end
        
    catch e
        println("❌ SSH connection failed: $e")
        return false
    end
end

function main()
    println("🧪 SSH Setup Test for HPC GPU Allocation")
    println("="^50)
    
    # Test 1: Environment detection
    env_status = test_environment_detection()
    
    if env_status == "no_slurm"
        println("\n❌ Test cannot proceed - not in SLURM job")
        println("Please run from within a GPU interactive session:")
        println("  interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00")
        return
    end
    
    # Test 2: GPU assignment detection
    gpu_node = test_gpu_assignment_detection()
    
    # Test 3: SSH connection (only if we're on login node)
    if env_status == "login_node"
        ssh_success = test_ssh_connection(gpu_node)
        
        if ssh_success
            println("\n✅ All SSH tests passed!")
            println("The HPC setup should work correctly.")
        else
            println("\n❌ SSH tests failed!")
            println("You may need to set up SSH keys or check network connectivity.")
        end
    else
        println("\n✅ Already on GPU node - no SSH needed!")
    end
    
    println("\n📊 Test Summary")
    println("Environment: $env_status")
    println("GPU Node: $(gpu_node === nothing ? "Not detected" : gpu_node)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
