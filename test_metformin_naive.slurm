#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=0:30:00
#SBATCH --job-name=test_metformin_naive
#SBATCH --output=test_metformin_naive_%j.out
#SBATCH --error=test_metformin_naive_%j.err

echo "Starting GPU job for Metformin naive LLM test..."
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"

# Load modules
module load ollama julia

# Start Ollama server in background
echo "Starting Ollama server..."
ollama serve > ollama_server.log 2>&1 &
OLLAMA_PID=$!

# Wait for server to start
echo "Waiting for Ollama server to start..."
sleep 10

# Check if server is responding
echo "Testing Ollama server..."
curl -s http://localhost:11434/api/tags || echo "Server not responding"

# Set environment variable
export OLLAMA_HOST="http://localhost:11434"

# Load the model if needed
echo "Loading llama3.2 model..."
ollama pull llama3.2

# Test the naive LLM prompt with Metformin
echo "Testing naive LLM prompt with Metformin..."
julia -e '
using HTTP
using JSON3

# Test the naive LLM prompt with Metformin
ollama_host = get(ENV, "OLLAMA_HOST", "http://localhost:11434")

# Create the prompt for Metformin
prompt = """You are a medical expert with comprehensive knowledge of pharmaceuticals and their therapeutic applications.

DRUG: Metformin

Task: Based on your medical knowledge, identify all known therapeutic indications for Metformin. Consider both FDA-approved uses and well-established off-label applications supported by clinical evidence.

Rules:
1. List specific medical conditions, diseases, or therapeutic indications that Metformin is used to treat, prevent, or manage
2. Focus on therapeutic uses, not side effects or contraindications
3. Use standard medical terminology
4. Rate confidence 0.1-1.0 based on regulatory approval and evidence strength
5. A confidence of 0.6+ means established therapeutic use with strong evidence

Format your response for each therapeutic indication exactly as:
Indication 1:
EVIDENCE: [YES or NO]
CONFIDENCE: [0.1-1.0]
REASONING: [condition/disease name - Brief clinical description]

Indication 2:
EVIDENCE: [YES or NO]
CONFIDENCE: [0.1-1.0]
REASONING: [condition/disease name - Brief clinical description]

Continue for all therapeutic indications..."""

# Make the request
println("🔍 Testing naive LLM prompt with Metformin...")
println("Ollama host: $ollama_host")

try
    response = HTTP.post(
        "$ollama_host/api/generate",
        ["Content-Type" => "application/json"],
        JSON3.write(Dict(
            "model" => "llama3.2",
            "prompt" => prompt,
            "stream" => false
        ))
    )
    
    result = JSON3.read(String(response.body))
    
    println("\n📋 LLM Response:")
    println(result["response"])
    
catch e
    println("❌ Error: $e")
end
'

# Clean up
echo "Cleaning up..."
kill $OLLAMA_PID 2>/dev/null || true

echo "Job completed."