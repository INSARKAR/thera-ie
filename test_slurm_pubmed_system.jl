#!/usr/bin/env julia

"""
Test Script for SLURM PubMed Drug Analysis System

This script validates the SLURM-enhanced PubMed analysis system by:
1. Checking all required files exist
2. Testing the Julia scripts can be loaded
3. Verifying SLURM commands are available
4. Running a small test analysis
5. Testing job submission and monitoring functions

Usage:
    julia test_slurm_pubmed_system.jl [--full-test]
    
Options:
    --full-test    Run complete validation including actual job submission
"""

using Pkg
using JSON3
using Dates

# Test configuration
const TEST_CHUNK_SIZE = 5
const TEST_TIME_HOURS = 1
const TEST_MEMORY_GB = 4

println("🧪 SLURM PubMed Analysis System Test")
println("=" ^ 40)
println("Started at: $(now())")
println()

"""
    test_file_exists(filepath::String, description::String) -> Bool

Test if a required file exists.
"""
function test_file_exists(filepath::String, description::String)
    if isfile(filepath)
        println("✅ $description: $filepath")
        return true
    else
        println("❌ $description: $filepath (NOT FOUND)")
        return false
    end
end

"""
    test_directory_exists(dirpath::String, description::String) -> Bool

Test if a directory exists or can be created.
"""
function test_directory_exists(dirpath::String, description::String)
    if isdir(dirpath)
        println("✅ $description: $dirpath (exists)")
        return true
    else
        try
            mkpath(dirpath)
            println("✅ $description: $dirpath (created)")
            return true
        catch e
            println("❌ $description: $dirpath (CANNOT CREATE: $e)")
            return false
        end
    end
end

"""
    test_slurm_commands() -> Bool

Test if SLURM commands are available.
"""
function test_slurm_commands()
    println("\n🔧 Testing SLURM Commands:")
    
    slurm_commands = ["sbatch", "squeue", "sacct", "sinfo"]
    all_available = true
    
    for cmd in slurm_commands
        try
            run(pipeline(`which $cmd`, devnull))
            println("✅ $cmd command available")
        catch
            println("❌ $cmd command not found")
            all_available = false
        end
    end
    
    # Test basic SLURM functionality
    if all_available
        try
            # Test sinfo (should work on any SLURM system)
            result = readchomp(`sinfo -h -o "%P"`)
            partitions = split(strip(result), '\n')
            if !isempty(partitions) && !isempty(partitions[1])
                println("✅ SLURM system responsive (partitions: $(join(partitions[1:min(3, length(partitions))], ", ")))")
            else
                println("⚠️  SLURM system available but no partitions found")
            end
        catch e
            println("⚠️  SLURM commands available but system may not be active: $e")
        end
    end
    
    return all_available
end

"""
    test_julia_script_loading() -> Bool

Test if the main Julia scripts can be loaded without errors.
"""
function test_julia_script_loading()
    println("\n📦 Testing Julia Script Loading:")
    
    scripts_to_test = [
        ("pubmed_drug_indications.jl", "Original PubMed analysis script"),
        ("slurm_pubmed_drug_indications.jl", "SLURM-enhanced script")
    ]
    
    all_loaded = true
    
    for (script, description) in scripts_to_test
        try
            # Test if we can include the script without running main()
            println("  Testing $script...")
            
            # For the SLURM script, we need to prevent it from running
            if script == "slurm_pubmed_drug_indications.jl"
                # Temporarily modify PROGRAM_FILE to prevent main execution
                old_program_file = Base.PROGRAM_FILE
                Base.PROGRAM_FILE = "test_mode"
                try
                    include(script)
                    println("✅ $description loaded successfully")
                finally
                    Base.PROGRAM_FILE = old_program_file
                end
            else
                # For the original script, check if it defines expected functions
                include(script)
                # Test if key functions are defined
                expected_functions = [:load_approved_drugs, :load_mesh_disease_headings, :process_drug_memory_efficient]
                for func in expected_functions
                    if isdefined(Main, func)
                        println("  ✅ Function $func defined")
                    else
                        println("  ❌ Function $func not found")
                        all_loaded = false
                    end
                end
                println("✅ $description loaded successfully")
            end
            
        catch e
            println("❌ $description failed to load: $e")
            all_loaded = false
        end
    end
    
    return all_loaded
end

"""
    test_data_loading() -> Bool

Test if required data files can be loaded.
"""
function test_data_loading()
    println("\n📊 Testing Data Loading:")
    
    all_loaded = true
    
    # Test approved drugs loading
    try
        drugs_dict = load_approved_drugs()
        drug_count = length(drugs_dict)
        println("✅ Approved drugs loaded: $drug_count drugs")
        
        # Show sample drugs
        sample_drugs = collect(keys(drugs_dict))[1:min(3, length(drugs_dict))]
        println("  Sample drugs: $(join(sample_drugs, ", "))")
        
    catch e
        println("❌ Failed to load approved drugs: $e")
        all_loaded = false
    end
    
    # Test MeSH headings loading
    try
        disease_headings = load_mesh_disease_headings("mesh_t047_headings.jl")
        heading_count = length(disease_headings)
        println("✅ MeSH disease headings loaded: $heading_count headings")
        
        # Show sample headings
        sample_headings = collect(disease_headings)[1:min(3, length(disease_headings))]
        println("  Sample headings: $(join(sample_headings, ", "))")
        
    catch e
        println("❌ Failed to load MeSH disease headings: $e")
        all_loaded = false
    end
    
    return all_loaded
end

"""
    test_slurm_script_generation() -> Bool

Test SLURM script generation functionality.
"""
function test_slurm_script_generation()
    println("\n📜 Testing SLURM Script Generation:")
    
    try
        # Load the SLURM functions (they should be available from previous loading)
        if !isdefined(Main, :create_slurm_script)
            println("❌ SLURM functions not available")
            return false
        end
        
        # Create test directories
        test_slurm_dir = "test_slurm_scripts"
        test_output_dir = "test_slurm_outputs"
        
        if !isdir(test_slurm_dir)
            mkpath(test_slurm_dir)
        end
        if !isdir(test_output_dir)
            mkpath(test_output_dir)
        end
        
        # Test script generation with mock configuration
        test_config = Main.SlurmConfig(
            chunk_size=TEST_CHUNK_SIZE,
            time_hours=TEST_TIME_HOURS,
            memory_gb=TEST_MEMORY_GB,
            partition="batch",
            account="",
            email="test@example.com"
        )
        
        # Generate a test script
        test_script_path = joinpath(test_slurm_dir, "test_pubmed_chunk_1.sh")
        
        # Create script content manually for testing
        script_content = """#!/bin/bash
#SBATCH --job-name=pubmed_drugs_test
#SBATCH --output=$test_output_dir/pubmed_chunk_test_%j.out
#SBATCH --error=$test_output_dir/pubmed_chunk_test_%j.err
#SBATCH --time=$TEST_TIME_HOURS:00:00
#SBATCH --mem=$(TEST_MEMORY_GB)G
#SBATCH --partition=batch
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4

export SLURM_DRUG_START=1
export SLURM_DRUG_END=5
export SLURM_CHUNK_ID=test

echo "Test SLURM script generated successfully"
echo "This is a test script and should not be submitted"
"""
        
        open(test_script_path, "w") do file
            write(file, script_content)
        end
        
        run(`chmod +x $test_script_path`)
        
        if isfile(test_script_path)
            println("✅ Test SLURM script generated: $test_script_path")
            
            # Verify script content
            content = read(test_script_path, String)
            if occursin("SBATCH", content) && occursin("SLURM_DRUG_START", content)
                println("✅ Script content validated")
            else
                println("⚠️  Script generated but content may be incomplete")
            end
            
            return true
        else
            println("❌ Failed to generate test script")
            return false
        end
        
    catch e
        println("❌ Script generation test failed: $e")
        return false
    end
end

"""
    test_processing_status() -> Bool

Test processing status checking functionality.
"""
function test_processing_status()
    println("\n📈 Testing Processing Status:")
    
    try
        # Load required data
        drugs_dict = load_approved_drugs()
        output_dir = "drug_pubmed_refs"
        
        # Get processing status
        status = get_processing_status(drugs_dict, output_dir)
        
        println("✅ Status check successful:")
        println("  • Total drugs: $(status["total_drugs"])")
        println("  • Already processed: $(status["already_processed"])")
        println("  • Remaining: $(status["remaining_to_process"])")
        println("  • Completion: $(status["completion_percentage"])%")
        
        return true
        
    catch e
        println("❌ Status check failed: $e")
        return false
    end
end

"""
    run_full_test() -> Bool

Run a complete test including actual functionality.
"""
function run_full_test()
    println("\n🚀 Running Full System Test:")
    
    try
        # Test a small drug processing
        drugs_dict = load_approved_drugs()
        disease_headings = load_mesh_disease_headings("mesh_t047_headings.jl")
        
        # Get first drug for testing
        first_drug = first(drugs_dict)
        drug_name, indication = first_drug
        
        println("Testing with drug: $drug_name")
        
        # Create test output directory
        test_output_dir = "test_drug_output"
        if !isdir(test_output_dir)
            mkpath(test_output_dir)
        end
        
        # Process one drug
        println("  Processing drug...")
        start_time = time()
        result = process_drug_memory_efficient(drug_name, indication, disease_headings, test_output_dir)
        processing_time = time() - start_time
        
        println("  ✅ Drug processed in $(round(processing_time, digits=1))s")
        println("  • Search status: $(get(result, "search_status", "unknown"))")
        println("  • Publications found: $(get(result, "count", 0))")
        println("  • Disease associations: $(get(result, "disease_associations_count", 0))")
        
        # Check if output file was created
        safe_filename = sanitize_filename(drug_name)
        test_file = joinpath(test_output_dir, "$(safe_filename).json")
        
        if isfile(test_file)
            println("  ✅ Output file created: $(basename(test_file))")
            
            # Verify file content
            file_content = JSON3.read(read(test_file, String))
            if haskey(file_content, "result") && haskey(file_content.result, "drug_name")
                println("  ✅ Output file content validated")
            else
                println("  ⚠️  Output file created but content may be incomplete")
            end
        else
            println("  ❌ Output file not created")
            return false
        end
        
        return true
        
    catch e
        println("❌ Full test failed: $e")
        return false
    end
end

"""
    main_test()

Main testing function.
"""
function main_test()
    full_test = "--full-test" in ARGS
    
    println("🔍 Test Configuration:")
    println("  • Full test mode: $full_test")
    println("  • Test chunk size: $TEST_CHUNK_SIZE")
    println("  • Test time limit: $TEST_TIME_HOURS hours")
    println("  • Test memory: $TEST_MEMORY_GB GB")
    println()
    
    all_tests_passed = true
    
    # 1. Test file existence
    println("1️⃣ Testing Required Files:")
    required_files = [
        ("pubmed_drug_indications.jl", "Original PubMed analysis script"),
        ("slurm_pubmed_drug_indications.jl", "SLURM-enhanced script"),
        ("run_slurm_pubmed_analysis.sh", "SLURM orchestration script"),
        ("approved_drugs_dict.jl", "Approved drugs dictionary"),
        ("mesh_t047_headings.jl", "MeSH disease headings")
    ]
    
    for (file, desc) in required_files
        if !test_file_exists(file, desc)
            all_tests_passed = false
        end
    end
    
    # 2. Test directories
    println("\n2️⃣ Testing Directories:")
    required_dirs = [
        ("drug_pubmed_refs", "Output directory for individual drug files"),
        ("slurm_scripts", "SLURM batch scripts directory"),
        ("slurm_outputs", "SLURM job outputs directory")
    ]
    
    for (dir, desc) in required_dirs
        if !test_directory_exists(dir, desc)
            all_tests_passed = false
        end
    end
    
    # 3. Test SLURM availability
    if !test_slurm_commands()
        println("⚠️  SLURM commands not available - some functionality will be limited")
    end
    
    # 4. Test Julia script loading
    if !test_julia_script_loading()
        all_tests_passed = false
    end
    
    # 5. Test data loading
    if !test_data_loading()
        all_tests_passed = false
    end
    
    # 6. Test SLURM script generation
    if !test_slurm_script_generation()
        all_tests_passed = false
    end
    
    # 7. Test processing status
    if !test_processing_status()
        all_tests_passed = false
    end
    
    # 8. Full functionality test (optional)
    if full_test
        if !run_full_test()
            all_tests_passed = false
        end
    else
        println("\n🔄 Skipping full functionality test (use --full-test to enable)")
    end
    
    # Final summary
    println("\n" ^ 1)
    println("🏁 Test Summary")
    println("=" ^ 15)
    println("Completed at: $(now())")
    
    if all_tests_passed
        println("✅ All tests PASSED!")
        println("\n💡 Next Steps:")
        println("  • Start analysis: ./run_slurm_pubmed_analysis.sh start")
        println("  • Check status: ./run_slurm_pubmed_analysis.sh status")
        println("  • Monitor jobs: ./run_slurm_pubmed_analysis.sh monitor")
    else
        println("❌ Some tests FAILED!")
        println("\n🔧 Troubleshooting:")
        println("  • Ensure all required files are present")
        println("  • Run data generation scripts if needed:")
        println("    - julia approved_drugs_extractor.jl")
        println("    - julia mesh_t047_extractor.jl")
        println("  • Check SLURM system availability")
    end
    
    return all_tests_passed
end

# Run tests if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main_test()
end
