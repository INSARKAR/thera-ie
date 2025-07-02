#!/usr/bin/env julia

"""
Simple HPC Script - Non-hanging version
"""

function safe_run_command(cmd, description)
    println("$description...")
    try
        result = readchomp(cmd)
        println("✓ $description: $result")
        return result
    catch e
        println("❌ $description failed: $e")
        return nothing
    end
end

function main()
    println("🧪 Simple HPC Test (Non-hanging version)")
    println("="^50)
    
    # Test environment variables first (no subprocess calls)
    job_id = get(ENV, "SLURM_JOB_ID", "Not set")
    hostname = get(ENV, "HOSTNAME", "Not set")
    
    println("SLURM Job ID: $job_id")
    println("Hostname: $hostname")
    
    # Test simple commands
    safe_run_command(`whoami`, "Current user")
    safe_run_command(`pwd`, "Current directory")
    
    # Test if we can check for Ollama
    ollama_result = safe_run_command(`which ollama`, "Ollama location")
    
    if ollama_result !== nothing
        println("✅ Ollama is available!")
        
        # Try a simple ollama command
        version_result = safe_run_command(`ollama --version`, "Ollama version")
        if version_result !== nothing
            println("✅ Ollama is working!")
        end
    else
        println("⚠️  Ollama not found in PATH")
    end
    
    println("\n✅ Simple test completed!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
