#!/usr/bin/env julia

"""
Simple test for Llama drug indication extraction
"""

using HTTP
using JSON3

# Test the Llama API directly
function test_llama_api()
    println("Testing Llama API directly...")
    
    # Simple test prompt
    prompt = """
    Given this drug information, extract drug-indication pairs in JSON format:
    
    Drug: Aspirin
    Text: "Aspirin is commonly used to treat headaches and reduce fever. It is also prescribed for heart attack prevention."
    
    Extract in this JSON format:
    {"indications": ["headache", "fever", "heart attack prevention"]}
    
    Response:
    """
    
    payload = Dict(
        "model" => "llama3.2",
        "prompt" => prompt,
        "stream" => false,
        "options" => Dict(
            "temperature" => 0.1,
            "max_tokens" => 500
        )
    )
    
    try
        response = HTTP.post(
            "http://localhost:11434/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=30,
            readtimeout=60
        )
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            println("✅ API Response:")
            println("Model: ", result.model)
            println("Response: ", result.response)
            println("Done: ", result.done)
            return result.response
        else
            println("❌ API Error: Status $(response.status)")
            return nothing
        end
    catch e
        println("❌ Exception: $e")
        return nothing
    end
end

# Test JSON parsing from response
function test_json_parsing(response_text)
    println("\n🔍 Testing JSON parsing...")
    println("Response text: ", response_text)
    
    # Try to find JSON in the response
    json_match = match(r"\{.*\}", response_text)
    if json_match !== nothing
        json_str = json_match.match
        println("Found JSON: ", json_str)
        
        try
            parsed = JSON3.read(json_str)
            println("✅ Successfully parsed JSON: ", parsed)
            return parsed
        catch e
            println("❌ JSON parsing failed: $e")
            return nothing
        end
    else
        println("❌ No JSON found in response")
        return nothing
    end
end

function main()
    println("🧪 Testing Llama Drug Indication Extraction")
    println("="^50)
    
    # Test API
    response = test_llama_api()
    
    if response !== nothing
        # Test parsing
        parsed = test_json_parsing(response)
        
        if parsed !== nothing
            println("\n✅ Test successful!")
            println("Extracted data: ", parsed)
        else
            println("\n❌ JSON parsing failed")
        end
    else
        println("\n❌ API test failed")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
