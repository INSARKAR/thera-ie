#!/usr/bin/env julia

"""
Quick Test of Llama Drug Indication Extractor for Levothyroxine
Processes only 2 publications for quick testing
"""

using HTTP
using JSON3
using Dates

println("=== Levothyroxine Indication Extraction Test ===")
println("Node: $(gethostname())")
println("Time: $(now())")

# Configuration
const DRUG_FILE = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/Levothyroxine.json"
const OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
const MODEL_NAME = "llama3.2"
const MAX_PUBS = 2  # Only test 2 publications

# Ensure output directory exists
if !isdir(OUTPUT_DIR)
    mkpath(OUTPUT_DIR)
end

# Simple data structures
struct Indication
    text::String
    confidence::Float64
    pmid::String
end

function test_ollama_connection()
    println("🔍 Testing Ollama connection...")
    try
        response = HTTP.get("http://localhost:11434/api/tags"; connect_timeout=5)
        println("✓ Ollama server is accessible")
        return true
    catch e
        println("❌ Cannot connect to Ollama: $e")
        println("Please ensure:")
        println("  1. You're on gpu2004: ssh gpu2004")
        println("  2. Ollama module loaded: module load ollama")
        println("  3. Ollama server running: ollama serve &")
        println("  4. Model available: ollama run llama3.2")
        return false
    end
end

function query_llama_simple(prompt::String)
    payload = Dict(
        "model" => MODEL_NAME,
        "prompt" => prompt,
        "stream" => false,
        "options" => Dict("temperature" => 0.1, "max_tokens" => 150)
    )
    
    try
        response = HTTP.post(
            "http://localhost:11434/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=15,
            readtimeout=60
        )
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            return result.response
        end
    catch e
        println("❌ Query failed: $e")
    end
    return nothing
end

function extract_indication(drug_name::String, title::String, abstract::String, pmid::String)
    prompt = """
Medical expert: Extract therapeutic indications for $drug_name from this publication.

TITLE: $title

ABSTRACT: $abstract

TASK: What condition does $drug_name treat? Use this EXACT format:

INDICATION: [medical condition]
CONFIDENCE: [0.0-1.0]

If no clear indication, respond: NO_INDICATION
"""

    println("🤖 Querying Llama for PMID: $pmid")
    response = query_llama_simple(prompt)
    
    if response === nothing
        println("   ❌ No response received")
        return nothing
    end
    
    # Simple parsing
    lines = split(strip(response), '\n')
    indication_text = ""
    confidence = 0.0
    
    for line in lines
        line = strip(line)
        if startswith(line, "INDICATION:")
            indication_text = strip(replace(line, "INDICATION:" => ""))
        elseif startswith(line, "CONFIDENCE:")
            conf_str = strip(replace(line, "CONFIDENCE:" => ""))
            try
                confidence = parse(Float64, conf_str)
            catch
                confidence = 0.5  # Default if parsing fails
            end
        end
    end
    
    if !isempty(indication_text) && indication_text != "NO_INDICATION"
        println("   ✓ Found: $indication_text (confidence: $confidence)")
        return Indication(indication_text, confidence, pmid)
    else
        println("   - No indication found")
        return nothing
    end
end

function main()
    # Test connection first
    if !test_ollama_connection()
        return false
    end
    
    # Load Levothyroxine data
    println("\n📖 Loading Levothyroxine data...")
    if !isfile(DRUG_FILE)
        println("❌ File not found: $DRUG_FILE")
        return false
    end
    
    drug_data = JSON3.read(read(DRUG_FILE, String))
    drug_name = get(drug_data.metadata, "drug_name", "Levothyroxine")
    publications = get(drug_data.result, "publications_analyzed", [])
    
    println("✓ Loaded data for: $drug_name")
    println("📚 Total publications: $(length(publications))")
    println("🧪 Testing with first $MAX_PUBS publications...")
    
    if length(publications) < MAX_PUBS
        println("⚠ Only $(length(publications)) publications available")
    end
    
    # Process publications
    indications = Indication[]
    test_pubs = publications[1:min(MAX_PUBS, length(publications))]
    
    for (i, pub) in enumerate(test_pubs)
        pmid = get(pub, "pmid", "unknown")
        title = get(pub, "title", "")
        abstract = get(pub, "abstract", "")
        
        println("\n📄 Publication $i/$MAX_PUBS:")
        println("   PMID: $pmid")
        println("   Title: $(title[1:min(80, length(title))])$(length(title) > 80 ? "..." : "")")
        
        if isempty(title) && isempty(abstract)
            println("   ⚠ No content, skipping")
            continue
        end
        
        indication = extract_indication(drug_name, title, abstract, pmid)
        if indication !== nothing
            push!(indications, indication)
        end
        
        # Delay between requests
        if i < length(test_pubs)
            print("   ⏳ Waiting 3 seconds...")
            sleep(3)
            println(" done")
        end
    end
    
    # Results
    println("\n" * "="^50)
    println("📊 RESULTS SUMMARY")
    println("="^50)
    println("Publications processed: $(length(test_pubs))")
    println("Indications extracted: $(length(indications))")
    
    if !isempty(indications)
        println("\n🎯 EXTRACTED INDICATIONS:")
        for (i, ind) in enumerate(indications)
            println("$i. $(ind.text)")
            println("   Confidence: $(ind.confidence)")
            println("   Source: PMID $(ind.pmid)")
            println()
        end
        
        # Save results
        output_file = joinpath(OUTPUT_DIR, "levothyroxine_quick_test.json")
        results = Dict(
            "test_info" => Dict(
                "drug" => drug_name,
                "publications_tested" => length(test_pubs),
                "indications_found" => length(indications),
                "timestamp" => string(now()),
                "node" => gethostname()
            ),
            "indications" => [
                Dict("text" => ind.text, "confidence" => ind.confidence, "pmid" => ind.pmid)
                for ind in indications
            ]
        )
        
        write(output_file, JSON3.write(results, allow_inf=true))
        println("💾 Results saved to: $output_file")
        println("\n🎉 Test completed successfully!")
        return true
    else
        println("⚠ No indications were extracted.")
        println("This might indicate:")
        println("- The publications don't contain clear therapeutic information")
        println("- The prompt needs adjustment")
        println("- Ollama responses need better parsing")
        return false
    end
end

# Run the test
if abspath(PROGRAM_FILE) == @__FILE__
    success = main()
    exit(success ? 0 : 1)
end
