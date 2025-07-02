#!/usr/bin/env julia

"""
Simple HPC Test Script
"""

using HTTP
using JSON3

function main()
    println("🧪 Testing HPC environment...")
    
    # Test 1: Check SLURM
    job_id = get(ENV, "SLURM_JOB_ID", nothing)
    println("SLURM Job ID: $(job_id === nothing ? "Not in SLURM job" : job_id)")
    
    # Test 2: Check hostname
    hostname = strip(read(`hostname`, String))
    println("Hostname: $hostname")
    
    # Test 3: Check if module command exists
    try
        result = read(`which module`, String)
        println("Module command: $(strip(result))")
    catch e
        println("Module command: Not found ($e)")
    end
    
    # Test 4: Try module list (should work if in HPC environment)
    try
        result = read(`module list`, String)
        println("Current modules loaded:")
        println(result)
    catch e
        println("Module list failed: $e")
    end
    
    # Test 5: Check for myq command
    try
        result = read(`which myq`, String)
        println("MyQ command: $(strip(result))")
    catch e
        println("MyQ command: Not found ($e)")
    end
    
    println("✅ Test completed!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
