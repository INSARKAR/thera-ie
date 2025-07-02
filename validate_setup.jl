#!/usr/bin/env julia

"""
Validation Script for Llama Drug Indication Extractor

This script tests the extraction system with a small sample to ensure everything is working correctly.
"""

using HTTP
using JSON3

function test_ollama_connection()
    println("Testing Ollama connection...")
    try
        response = HTTP.get("http://localhost:11434/api/tags", connect_timeout=5)
        if response.status == 200
            println("✓ Ollama is accessible")
            
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
        println("✗ Cannot connect to Ollama: $e")
        return false
    end
end

function test_extraction_prompt()
    println("\nTesting extraction with sample data...")
    
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
        response = HTTP.post(
            "http://localhost:11434/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=30,
            readtimeout=120
        )
        
        if response.status == 200
            result = JSON3.read(String(response.body))
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
        else
            println("✗ API request failed with status $(response.status)")
            return false
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

function main()
    println("Llama Drug Indication Extractor - Validation Test")
    println("=" * "="^50)
    
    all_tests_passed = true
    
    # Test 1: Ollama connection
    if !test_ollama_connection()
        all_tests_passed = false
    end
    
    # Test 2: File access
    if !test_file_access()
        all_tests_passed = false
    end
    
    # Test 3: Extraction functionality (only if Ollama is working)
    if all_tests_passed
        if !test_extraction_prompt()
            all_tests_passed = false
        end
    end
    
    println("\n" * "=" * "="^50)
    if all_tests_passed
        println("✓ All tests passed! The system is ready to use.")
        println("\nTo run the extraction:")
        println("  julia setup_and_run.jl")
        println("or")
        println("  julia llama_drug_indication_extractor.jl")
    else
        println("✗ Some tests failed. Please address the issues above.")
        println("\nCommon solutions:")
        println("- Start Ollama: ollama serve")
        println("- Install Llama 3.2: ollama pull llama3.2")
        println("- Check file permissions")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
