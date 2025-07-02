#!/bin/bash

# Test script for Llama Drug Indication Extractor
# Run this on the GPU node after setting up Ollama

echo "=== Llama Drug Indication Extractor Test ==="
echo "Node: $(hostname)"
echo "Time: $(date)"
echo ""

# Check if we're on a GPU node
if [[ $(hostname) != gpu* ]]; then
    echo "⚠ Warning: Not on a GPU node. Please run:"
    echo "ssh gpu2004"
    echo ""
fi

# Check if Ollama module is loaded
if ! command -v ollama &> /dev/null; then
    echo "❌ Ollama not found. Please load the module:"
    echo "module load ollama"
    exit 1
fi

echo "✓ Ollama command available"

# Check if Ollama server is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "❌ Ollama server not responding. Please start it:"
    echo "ollama serve &"
    echo "Wait a few seconds, then run:"
    echo "ollama run llama3.2"
    exit 1
fi

echo "✓ Ollama server is running"

# Check if llama3.2 model is available
if ! curl -s http://localhost:11434/api/tags | grep -q llama3.2; then
    echo "❌ Llama 3.2 model not found. Please run:"
    echo "ollama pull llama3.2"
    exit 1
fi

echo "✓ Llama 3.2 model is available"

# Test basic generation
echo ""
echo "Testing Llama 3.2 generation..."
RESPONSE=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model": "llama3.2", "prompt": "Extract indication: Levothyroxine treats hypothyroidism. Format: INDICATION: [condition], CONFIDENCE: [0.0-1.0]", "stream": false, "options": {"temperature": 0.1, "max_tokens": 50}}' \
    --connect-timeout 10 --max-time 30)

if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
    echo "✓ Llama generation successful"
    echo "Sample response: $(echo $RESPONSE | jq -r '.response' 2>/dev/null || echo $RESPONSE | head -c 100)..."
else
    echo "❌ Llama generation failed"
    exit 1
fi

echo ""
echo "🎉 All checks passed! Ready to run drug indication extractor."
echo ""
echo "To run the test extractor:"
echo "cd /users/isarkar/sarkarcode/thera"
echo "julia --project=. test_levothyroxine_extractor.jl"
echo ""
echo "To run the full extractor for Levothyroxine:"
echo "LLAMA_SINGLE_DRUG=Levothyroxine julia --project=. llama_drug_indication_extractor.jl"
