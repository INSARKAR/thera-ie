#!/usr/bin/env julia

"""
Setup and Runner Script for Llama Drug Indication Extractor

This script helps set up the environment and run the drug indication extraction.
"""

using Pkg
using HTTP
using JSON3

function check_dependencies()
    println("Checking Julia dependencies...")
    
    required_packages = ["HTTP", "JSON3", "Dates", "Logging"]
    missing_packages = String[]
    
    for pkg in required_packages
        try
            eval(:(using $(Symbol(pkg))))
            println("✓ $pkg is available")
        catch
            println("✗ $pkg is missing")
            push!(missing_packages, pkg)
        end
    end
    
    if !isempty(missing_packages)
        println("\nInstalling missing packages...")
        for pkg in missing_packages
            Pkg.add(pkg)
        end
        println("Dependencies installed successfully!")
    else
        println("All dependencies are available!")
    end
end

function check_ollama()
    println("\nChecking Ollama installation...")
    
    try
        response = HTTP.get("http://localhost:11434/api/tags", connect_timeout=5)
        if response.status == 200
            println("✓ Ollama is running")
            
            # Check if llama3.2 model is available
            models = JSON3.read(String(response.body))
            
            llama_models = [m for m in models.models if occursin("llama3.2", m.name)]
            if !isempty(llama_models)
                println("✓ Llama 3.2 model is available")
                for model in llama_models
                    println("  - $(model.name)")
                end
                return true
            else
                println("✗ Llama 3.2 model not found")
                println("To install Llama 3.2, run: ollama pull llama3.2")
                return false
            end
        end
    catch e
        println("✗ Cannot connect to Ollama")
        println("Please ensure Ollama is installed and running:")
        println("1. Install Ollama from https://ollama.ai/")
        println("2. Run: ollama serve")
        println("3. Run: ollama pull llama3.2")
        return false
    end
end

function show_menu()
    println("\n" * "="^60)
    println("Llama Drug Indication Extractor")
    println("="^60)
    println()
    println("1. Check dependencies and setup")
    println("2. Run full analysis (all drug files)")
    println("3. Run test analysis (first 5 files)")
    println("4. Run single drug analysis")
    println("5. View previous results")
    println("6. Clean output directory")
    println("7. Exit")
    println()
    print("Choose an option (1-7): ")
end

function run_analysis(test_mode=false, single_drug=nothing)
    println("\n" * "="^40)
    if test_mode
        println("Running TEST analysis (first 5 files)")
    elseif single_drug !== nothing
        println("Running analysis for: $single_drug")
    else
        println("Running FULL analysis")
    end
    println("="^40)
    
    # Set environment variable for test mode
    if test_mode
        ENV["LLAMA_TEST_MODE"] = "true"
        ENV["LLAMA_MAX_FILES"] = "5"
    elseif single_drug !== nothing
        ENV["LLAMA_SINGLE_DRUG"] = single_drug
    end
    
    # Run the main extractor
    include("llama_drug_indication_extractor.jl")
end

function view_results()
    output_dir = "/users/isarkar/sarkarcode/thera/llama_extracted_indications"
    
    if !isdir(output_dir)
        println("No results directory found: $output_dir")
        return
    end
    
    files = readdir(output_dir)
    json_files = [f for f in files if endswith(f, ".json")]
    
    if isempty(json_files)
        println("No result files found in $output_dir")
        return
    end
    
    println("\nFound $(length(json_files)) result files:")
    for file in json_files
        println("  - $file")
    end
    
    # Show summary if available
    summary_file = joinpath(output_dir, "extraction_summary.json")
    if isfile(summary_file)
        try
            summary = JSON3.read(read(summary_file, String))
            println("\nSummary:")
            println("  Drugs analyzed: $(summary.analysis_summary.total_drugs_analyzed)")
            println("  Publications processed: $(summary.analysis_summary.total_publications_processed)")
            println("  Indications extracted: $(summary.analysis_summary.total_indications_extracted)")
            println("  Average indications per drug: $(summary.analysis_summary.average_indications_per_drug)")
        catch e
            println("Could not read summary file: $e")
        end
    end
end

function clean_output()
    output_dir = "/users/isarkar/sarkarcode/thera/llama_extracted_indications"
    
    if !isdir(output_dir)
        println("Output directory does not exist: $output_dir")
        return
    end
    
    files = readdir(output_dir)
    if isempty(files)
        println("Output directory is already clean")
        return
    end
    
    print("Are you sure you want to delete all $(length(files)) files in $output_dir? (y/N): ")
    response = readline()
    
    if lowercase(strip(response)) == "y"
        for file in files
            rm(joinpath(output_dir, file))
        end
        println("Output directory cleaned")
    else
        println("Operation cancelled")
    end
end

function get_available_drugs()
    drug_dir = "/users/isarkar/sarkarcode/thera/phase1_drug_pubmed_refs"
    if !isdir(drug_dir)
        return String[]
    end
    
    files = readdir(drug_dir)
    json_files = [f for f in files if endswith(f, ".json")]
    drug_names = [replace(f, ".json" => "") for f in json_files]
    
    return sort(drug_names)
end

function main()
    while true
        show_menu()
        choice = readline()
        
        if choice == "1"
            check_dependencies()
            check_ollama()
            
        elseif choice == "2"
            if check_ollama()
                run_analysis(false)
            end
            
        elseif choice == "3"
            if check_ollama()
                run_analysis(true)
            end
            
        elseif choice == "4"
            drugs = get_available_drugs()
            if isempty(drugs)
                println("No drug files found")
            else
                println("\nAvailable drugs:")
                for (i, drug) in enumerate(drugs[1:min(20, end)])
                    println("  $i. $drug")
                end
                if length(drugs) > 20
                    println("  ... and $(length(drugs) - 20) more")
                end
                
                print("\nEnter drug name: ")
                drug_name = strip(readline())
                
                if drug_name in drugs
                    if check_ollama()
                        run_analysis(false, drug_name)
                    end
                else
                    println("Drug not found: $drug_name")
                end
            end
            
        elseif choice == "5"
            view_results()
            
        elseif choice == "6"
            clean_output()
            
        elseif choice == "7"
            println("Goodbye!")
            break
            
        else
            println("Invalid choice. Please select 1-7.")
        end
        
        if choice != "7"
            print("\nPress Enter to continue...")
            readline()
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
