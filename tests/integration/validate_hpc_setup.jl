#!/usr/bin/env julia

"""
HPC Validation Script for Llama Drug Indication Extractor

This script tests the extraction system in HPC environments with GPU nodes.
"""

using HTTP
using JSON3

function test_hpc_environment()
    println("Testing HPC environment setup...")
    
    # Check SLURM job
    job_id = get(ENV, "SLURM_JOB_ID", nothing)
    if job_id !== nothing
        println("✓ Running in SLURM job: $job_id")
    else
        println("⚠️  Not in a SLURM job - you may need to request GPU resources")
        println("   Run: interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00")
    end
    
    # Check for module system
    try
        run(`module list`)
        println("✓ Module system is available")
    catch e
        println("⚠️  Module system may not be available: $e")
    end
    
    return job_id !== nothing
end

function test_ollama_connection_hpc()
    println("\nTesting Ollama connection...")
    
    gpu_node = get(ENV, "LLAMA_GPU_NODE", nothing)
    
    if gpu_node !== nothing
        println("Testing connection to GPU node: $gpu_node")
        try
            # Test SSH connectivity first
            result = read(`ssh $gpu_node hostname`, String)
            if strip(result) == gpu_node
                println("✓ SSH connection to $gpu_node is working")
            else
                println("⚠️  SSH test returned unexpected result: $result")
            end
            
            # Test Ollama on GPU node
            ollama_result = read(`ssh $gpu_node curl -s http://localhost:11434/api/tags --connect-timeout 5`, String)
            models = JSON3.read(ollama_result)
            
            println("✓ Ollama is accessible on GPU node")
            
            llama_models = [m for m in models.models if occursin("llama3.2", m.name)]
            if !isempty(llama_models)
                println("✓ Llama 3.2 models found:")
                for model in llama_models
                    println("  - $(model.name)")
                end
                return true
            else
                println("✗ No Llama 3.2 models found on GPU node")
                println("Run: ssh $gpu_node ollama pull llama3.2")
                return false
            end
            
        catch e
            println("✗ Cannot connect to Ollama on GPU node: $e")
            println("Try:")
            println("  ssh $gpu_node")
            println("  module load ollama")
            println("  ollama serve &")
            println("  ollama pull llama3.2")
            return false
        end
        
    else
        # Try local connection
        try
            response = HTTP.get("http://localhost:11434/api/tags", connect_timeout=5)
            if response.status == 200
                println("✓ Ollama is accessible locally")
                
                models = JSON3.read(String(response.body))
                llama_models = [m for m in models.models if occursin("llama3.2", m.name)]
                
                if !isempty(llama_models)
                    println("✓ Llama 3.2 models found:")
                    for model in llama_models
                        println("  - $(model.name)")
                    end
                    return true
                else
                    println("✗ No Llama 3.2 models found")
                    println("Run: ollama pull llama3.2")
                    return false
                end
            end
        catch e
            println("✗ Cannot connect to local Ollama: $e")
            println("Please start Ollama: ollama serve")
            return false
        end
    end
end

function test_extraction_prompt_hpc()
    println("\nTesting extraction with sample data...")
    
    gpu_node = get(ENV, "LLAMA_GPU_NODE", nothing)
    
    sample_drug = "Acetophenazine"
    sample_title = "Acetophenazine for office treatment of paranoid symptoms"
    sample_abstract = "A clinical study examining the effectiveness of acetophenazine in treating paranoid symptoms in outpatient settings. Results showed significant improvement in psychotic symptoms."
    sample_mesh = ["Antipsychotic Agents", "Paranoid Disorders", "Psychotic Disorders"]
    
    prompt = """
You are a medical expert tasked with extracting drug-indication pairings from scientific literature.

DRUG: $sample_drug

PUBLICATION TITLE: $sample_title

ABSTRACT: $sample_abstract

MESH TERMS: $(join(sample_mesh, ", "))

TASK: Analyze the above publication and extract specific medical conditions, diseases, or therapeutic indications that the drug "$sample_drug" is used to treat, prevent, or manage based on the content.

INSTRUCTIONS:
1. Only extract indications that are clearly stated or strongly implied in the text
2. Focus on therapeutic uses, not side effects or contraindications
3. Use standard medical terminology when possible
4. If the publication mentions the drug but doesn't indicate a therapeutic use, respond with "NO_INDICATION"
5. Rate your confidence (0.0-1.0) in each extraction

FORMAT YOUR RESPONSE EXACTLY AS:
INDICATION: [condition/disease name]
CONFIDENCE: [0.0-1.0]

If multiple indications are found, list each separately with the same format.
If no therapeutic indication is found, respond with:
NO_INDICATION
CONFIDENCE: 1.0
"""

    payload = Dict(
        "model" => "llama3.2",
        "prompt" => prompt,
        "stream" => false,
        "options" => Dict(
            "temperature" => 0.1,
            "top_p" => 0.9,
            "max_tokens" => 1000
        )
    )
    
    try
        println("Sending test query to Llama...")
        
        if gpu_node !== nothing
            # HPC environment with SSH
            temp_file = tempname() * ".json"
            write(temp_file, JSON3.write(payload))
            
            cmd = `ssh $gpu_node curl -X POST http://localhost:11434/api/generate -H "Content-Type: application/json" -d @$temp_file --connect-timeout 30 --max-time 120`
            result_json = read(cmd, String)
            rm(temp_file)
            
            result = JSON3.read(result_json)
            
        else
            # Local environment
            response = HTTP.post(
                "http://localhost:11434/api/generate",
                ["Content-Type" => "application/json"],
                JSON3.write(payload);
                connect_timeout=30,
                readtimeout=120
            )
            
            if response.status == 200
                result = JSON3.read(String(response.body))
            else
                println("✗ API request failed with status $(response.status)")
                return false
            end
        end
        
        println("✓ Successfully received response from Llama")
        println("\nSample Response:")
        println("-" * "="^50)
        println(result.response)
        println("-" * "="^50)
        
        # Test parsing
        response_text = result.response
        lines = split(strip(response_text), '\n')
        indications = 0
        
        for line in lines
            if startswith(strip(line), "INDICATION:")
                indication_text = strip(replace(line, "INDICATION:" => ""))
                if indication_text != "NO_INDICATION"
                    indications += 1
                    println("✓ Found indication: $indication_text")
                end
            end
        end
        
        if indications > 0
            println("✓ Successfully extracted $indications indication(s)")
            return true
        else
            println("⚠ No indications extracted - this might be normal for this sample")
            return true
        end
        
    catch e
        println("✗ Error querying Llama: $e")
        return false
    end
end

function test_file_access()
    println("\nTesting file access...")
    
    drug_dir = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs"
    output_dir = "/users/isarkar/sarkarcode/thera/llama_extracted_indications"
    
    if !isdir(drug_dir)
        println("✗ Drug files directory not found: $drug_dir")
        return false
    else
        files = [f for f in readdir(drug_dir) if endswith(f, ".json")]
        println("✓ Found $(length(files)) drug files in input directory")
    end
    
    if !isdir(output_dir)
        try
            mkpath(output_dir)
            println("✓ Created output directory: $output_dir")
        catch e
            println("✗ Cannot create output directory: $e")
            return false
        end
    else
        println("✓ Output directory exists: $output_dir")
    end
    
    # Test write permissions
    test_file = joinpath(output_dir, "test_write.txt")
    try
        write(test_file, "test")
        rm(test_file)
        println("✓ Write permissions confirmed for output directory")
        return true
    catch e
        println("✗ Cannot write to output directory: $e")
        return false
    end
end

function detect_gpu_node()
    println("\nAttempting to detect GPU node assignment...")
    
    try
        result = read(`myq`, String)
        println("Job queue status:")
        println(result)
        
        # Look for GPU node in the output
        lines = split(result, '\n')
        for line in lines
            if occursin("gpu", lowercase(line)) && occursin("Running", line)
                match_result = match(r"gpu\d+", line)
                if match_result !== nothing
                    gpu_node = match_result.match
                    println("✓ Detected GPU node: $gpu_node")
                    ENV["LLAMA_GPU_NODE"] = gpu_node
                    return gpu_node
                end
            end
        end
        
        println("⚠️  Could not auto-detect GPU node from myq output")
        return nothing
        
    catch e
        println("⚠️  Could not run myq command: $e")
        return nothing
    end
end

function main()
    println("HPC Llama Drug Indication Extractor - Validation Test")
    println("=" * "="^55)
    
    all_tests_passed = true
    
    # Test 1: HPC environment
    if !test_hpc_environment()
        println("⚠️  HPC environment checks failed - continuing with available tests")
    end
    
    # Test 2: GPU node detection
    gpu_node = detect_gpu_node()
    
    # Test 3: File access
    if !test_file_access()
        all_tests_passed = false
    end
    
    # Test 4: Ollama connection
    if !test_ollama_connection_hpc()
        all_tests_passed = false
    end
    
    # Test 5: Extraction functionality (only if Ollama is working)
    if all_tests_passed
        if !test_extraction_prompt_hpc()
            all_tests_passed = false
        end
    end
    
    println("\n" * "=" * "="^55)
    if all_tests_passed
        println("✓ All tests passed! The system is ready to use.")
        println("\nTo run the extraction:")
        println("  julia hpc_setup_and_run.jl    (for HPC environments)")
        println("  julia setup_and_run.jl        (for local environments)")
        println("or")
        println("  julia llama_drug_indication_extractor.jl")
        
        if gpu_node !== nothing
            println("\nDetected GPU node: $gpu_node")
            println("This has been set as LLAMA_GPU_NODE environment variable")
        end
        
    else
        println("✗ Some tests failed. Please address the issues above.")
        println("\nFor HPC environments:")
        println("1. Request GPU resources: interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00")
        println("2. Load Ollama module: module load ollama")
        println("3. Start Ollama on GPU node: ssh gpuXXXX ollama serve &")
        println("4. Install model: ssh gpuXXXX ollama pull llama3.2")
        println("\nOr use the automated setup: julia hpc_setup_and_run.jl")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
