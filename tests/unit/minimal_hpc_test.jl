#!/usr/bin/env julia

"""
Minimal HPC Test
"""

function main()
    println("🎯 Minimal HPC Test Starting...")
    println("ARGS: $ARGS")
    
    # Check command line arguments
    test_mode = "--test" in ARGS
    println("Test mode: $test_mode")
    
    # Check SLURM environment
    job_id = get(ENV, "SLURM_JOB_ID", nothing)
    println("SLURM Job ID: $(job_id === nothing ? "Not in SLURM job" : job_id)")
    
    if job_id === nothing
        println("❌ Not in SLURM job - this is expected behavior")
        println("Would need to run: interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00")
    else
        println("✓ In SLURM job")
    end
    
    println("✅ Minimal test completed!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
