#!/usr/bin/env julia

"""
Simple test script to verify Ollama setup for drug indication extraction
"""

using HTTP
using JSON3

function test_ollama_connection()
    println("Testing Ollama connection...")
    
    try
        # Test if Ollama server is running
        response = HTTP.get("http://localhost:11434/api/tags"; connect_timeout=5)
        if response.status == 200
            models_data = JSON3.read(String(response.body))
            println("✓ Ollama server is running")
            
            if haskey(models_data, :models) && length(models_data.models) > 0
                println("Available models:")
                for model in models_data.models
                    println("  - $(model.name)")
                end
            else
                println("⚠ No models loaded")
            end
            return true
        end
    catch e
        println("✗ Ollama connection failed: $e")
        return false
    end
end

function test_llama_generation()
    println("\nTesting Llama 3.2 generation...")
    
    test_payload = Dict(
        "model" => "llama3.2",
        "prompt" => "Extract medical indication from this text: 'Levothyroxine is used to treat hypothyroidism.' Response format: INDICATION: [condition], CONFIDENCE: [0.0-1.0]",
        "stream" => false,
        "options" => Dict(
            "temperature" => 0.1,
            "max_tokens" => 100
        )
    )
    
    try
        response = HTTP.post(
            "http://localhost:11434/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(test_payload);
            connect_timeout=30,
            readtimeout=60
        )
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            println("✓ Llama 3.2 generation successful")
            println("Response: $(result.response)")
            return true
        else
            println("✗ Generation failed with status: $(response.status)")
            return false
        end
    catch e
        println("✗ Generation failed: $e")
        return false
    end
end

function main()
    println("=== Ollama Setup Test ===")
    println("Node: $(gethostname())")
    println("Time: $(now())")
    
    if test_ollama_connection()
        if test_llama_generation()
            println("\n✓ All tests passed! Ollama is ready for drug indication extraction.")
            return true
        end
    end
    
    println("\n✗ Setup incomplete. Please ensure:")
    println("1. You're on a GPU node (ssh gpu2004)")
    println("2. Ollama module is loaded (module load ollama)")
    println("3. Ollama server is running (ollama serve &)")
    println("4. Llama 3.2 model is available (ollama pull llama3.2)")
    
    return false
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
