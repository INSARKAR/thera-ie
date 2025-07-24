#!/usr/bin/env julia

"""
Quick Start Script for Llama Drug Indication Extractor

This script automatically detects the environment (HPC vs local) and 
launches the appropriate setup script.
"""

function detect_environment()
    println("🔍 Detecting environment...")
    
    # Check for SLURM (HPC indicator)
    slurm_job = get(ENV, "SLURM_JOB_ID", nothing)
    
    # Check for module system (HPC indicator)
    has_modules = false
    try
        run(`module --version`)
        has_modules = true
    catch
        has_modules = false
    end
    
    # Check for myq command (HPC queue system)
    has_myq = false
    try
        run(`which myq`)
        has_myq = true
    catch
        has_myq = false
    end
    
    is_hpc = slurm_job !== nothing || has_modules || has_myq
    
    if is_hpc
        println("✓ HPC environment detected")
        if slurm_job !== nothing
            println("  - SLURM job: $slurm_job")
        end
        if has_modules
            println("  - Module system available")
        end
        if has_myq
            println("  - Queue system (myq) available")
        end
        return "hpc"
    else
        println("✓ Local development environment detected")
        return "local"
    end
end

function launch_appropriate_script(env_type)
    println("\n🚀 Launching setup script for $env_type environment...")
    
    if env_type == "hpc"
        if isfile("hpc_setup_and_run.jl")
            println("Starting HPC setup script...")
            include("hpc_setup_and_run.jl")
        else
            println("❌ HPC setup script not found!")
            println("Expected: hpc_setup_and_run.jl")
        end
    else
        if isfile("setup_and_run.jl")
            println("Starting local setup script...")
            include("setup_and_run.jl")
        else
            println("❌ Local setup script not found!")
            println("Expected: setup_and_run.jl")
        end
    end
end

function show_manual_options(env_type)
    println("\n📖 Manual Options:")
    
    if env_type == "hpc"
        println("For HPC environments:")
        println("  julia hpc_setup_and_run.jl     # Interactive HPC setup")
        println("  julia validate_hpc_setup.jl    # Validate HPC configuration")
        println()
        println("Manual HPC steps:")
        println("  1. interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00")
        println("  2. module load ollama")
        println("  3. ollama serve &")
        println("  4. myq  # Check GPU assignment")
        println("  5. ssh gpuXXXX")
        println("  6. ollama pull llama3.2")
    else
        println("For local environments:")
        println("  julia setup_and_run.jl         # Interactive local setup")
        println("  julia validate_setup.jl        # Validate local configuration")
        println()
        println("Manual local steps:")
        println("  1. Install Ollama from https://ollama.ai")
        println("  2. ollama serve")
        println("  3. ollama pull llama3.2")
    end
    
    println()
    println("Direct execution:")
    println("  julia llama_drug_indication_extractor.jl")
end

function main()
    println("🏥 Llama Drug Indication Extractor - Quick Start")
    println("=" * "="^50)
    println()
    
    # Detect environment
    env_type = detect_environment()
    
    println()
    print("Continue with automatic setup? (Y/n): ")
    response = strip(readline())
    
    if lowercase(response) in ["", "y", "yes"]
        launch_appropriate_script(env_type)
    else
        show_manual_options(env_type)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
