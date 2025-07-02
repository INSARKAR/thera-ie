#!/usr/bin/env julia

"""
Simplified Llama 3.2 Drug-Indication Extractor for Testing
Processes only the first few publications from Levothyroxine
"""

using HTTP
using JSON3
using Dates

# Configuration
const DRUG_FILES_DIR = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs"
const OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
const LLAMA_API_URL = "http://localhost:11434/api/generate"
const MODEL_NAME = "llama3.2"
const MAX_PUBLICATIONS_TEST = 3  # Limit for testing

# Ensure output directory exists
if !isdir(OUTPUT_DIR)
    mkpath(OUTPUT_DIR)
    println("Created output directory: $OUTPUT_DIR")
end

struct DrugIndicationPair
    drug_name::String
    indication::String
    confidence::Float64
    pmid::String
    title::String
    source_text::String
    extracted_at::DateTime
end

function create_extraction_prompt(drug_name::String, title::String, abstract::String)
    prompt = """
You are a medical expert. Extract therapeutic indications for the drug "$drug_name" from this publication.

TITLE: $title

ABSTRACT: $abstract

TASK: Identify what medical conditions this drug treats. Respond ONLY in this format:

INDICATION: [condition name]
CONFIDENCE: [0.0-1.0]

If multiple conditions, list each separately. If no clear therapeutic use, respond:
NO_INDICATION
CONFIDENCE: 1.0
"""
    return prompt
end

function parse_llama_response(response_text::String, drug_name::String, pmid::String, title::String, source_text::String)
    pairs = DrugIndicationPair[]
    lines = split(strip(response_text), '\n')
    
    current_indication = nothing
    current_confidence = 0.0
    
    for line in lines
        line = strip(line)
        if startswith(line, "INDICATION:")
            indication_text = strip(replace(line, "INDICATION:" => ""))
            if indication_text == "NO_INDICATION"
                return pairs
            end
            current_indication = indication_text
        elseif startswith(line, "CONFIDENCE:")
            confidence_text = strip(replace(line, "CONFIDENCE:" => ""))
            try
                current_confidence = parse(Float64, confidence_text)
                if current_indication !== nothing
                    pair = DrugIndicationPair(
                        drug_name,
                        current_indication,
                        current_confidence,
                        pmid,
                        title,
                        source_text,
                        now()
                    )
                    push!(pairs, pair)
                    current_indication = nothing
                end
            catch e
                println("Warning: Failed to parse confidence: $confidence_text")
            end
        end
    end
    
    return pairs
end

function query_llama(prompt::String)
    payload = Dict(
        "model" => MODEL_NAME,
        "prompt" => prompt,
        "stream" => false,
        "options" => Dict(
            "temperature" => 0.1,
            "top_p" => 0.9,
            "max_tokens" => 200
        )
    )
    
    try
        response = HTTP.post(
            LLAMA_API_URL,
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=30,
            readtimeout=120
        )
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            return result.response
        else
            println("API request failed with status $(response.status)")
            return nothing
        end
    catch e
        println("Error querying Llama API: $e")
        return nothing
    end
end

function process_publication(drug_name::String, publication::Dict)
    pmid = get(publication, "pmid", "unknown")
    title = get(publication, "title", "")
    abstract = get(publication, "abstract", "")
    
    if isempty(title) && isempty(abstract)
        println("  Skipping publication $pmid - no content")
        return DrugIndicationPair[]
    end
    
    source_text = "Title: $title\nAbstract: $abstract"
    prompt = create_extraction_prompt(drug_name, title, abstract)
    
    println("  Processing publication $pmid...")
    println("    Title: $(title[1:min(80, length(title))])$(length(title) > 80 ? "..." : "")")
    
    response = query_llama(prompt)
    
    if response === nothing
        println("    ✗ Failed to get response")
        return DrugIndicationPair[]
    end
    
    pairs = parse_llama_response(response, drug_name, pmid, title, source_text)
    
    println("    ✓ Extracted $(length(pairs)) indication(s)")
    for pair in pairs
        println("      - $(pair.indication) (confidence: $(pair.confidence))")
    end
    
    return pairs
end

function test_levothyroxine_extraction()
    println("=== Testing Levothyroxine Drug Indication Extraction ===")
    println("Node: $(gethostname())")
    println("Time: $(now())")
    println("Max publications to process: $MAX_PUBLICATIONS_TEST")
    
    # Load Levothyroxine data
    levo_file = joinpath(DRUG_FILES_DIR, "Levothyroxine.json")
    
    if !isfile(levo_file)
        println("✗ Levothyroxine.json not found at: $levo_file")
        return false
    end
    
    println("Loading Levothyroxine data...")
    drug_data = JSON3.read(read(levo_file, String))
    
    drug_name = get(drug_data.metadata, "drug_name", "Levothyroxine")
    publications = get(drug_data.result, "publications_analyzed", [])
    
    println("Drug: $drug_name")
    println("Total publications available: $(length(publications))")
    
    if isempty(publications)
        println("✗ No publications found")
        return false
    end
    
    # Process first few publications
    test_publications = publications[1:min(MAX_PUBLICATIONS_TEST, length(publications))]
    println("Processing first $(length(test_publications)) publications...\n")
    
    all_indications = DrugIndicationPair[]
    
    for (i, publication) in enumerate(test_publications)
        println("Publication $i/$(length(test_publications)):")
        
        try
            pairs = process_publication(drug_name, publication)
            append!(all_indications, pairs)
            
            # Add delay between requests
            if i < length(test_publications)
                print("    Waiting 2 seconds...")
                sleep(2)
                println(" done")
            end
        catch e
            println("    ✗ Error processing: $e")
        end
        
        println()
    end
    
    # Save results
    if !isempty(all_indications)
        output_file = joinpath(OUTPUT_DIR, "Levothyroxine_test_results.json")
        
        result_dict = Dict(
            "metadata" => Dict(
                "drug_name" => drug_name,
                "test_mode" => true,
                "publications_processed" => length(test_publications),
                "total_indications_extracted" => length(all_indications),
                "model_used" => MODEL_NAME,
                "extraction_time" => string(now()),
                "node" => gethostname()
            ),
            "extracted_indications" => [
                Dict(
                    "indication" => pair.indication,
                    "confidence" => pair.confidence,
                    "pmid" => pair.pmid,
                    "title" => pair.title,
                    "source_text" => pair.source_text[1:min(200, length(pair.source_text))] * "...",
                    "extracted_at" => string(pair.extracted_at)
                )
                for pair in all_indications
            ]
        )
        
        write(output_file, JSON3.write(result_dict, allow_inf=true))
        println("✓ Results saved to: $output_file")
        
        # Print summary
        println("\n=== SUMMARY ===")
        println("Publications processed: $(length(test_publications))")
        println("Total indications extracted: $(length(all_indications))")
        
        if !isempty(all_indications)
            println("Unique indications found:")
            unique_indications = unique([pair.indication for pair in all_indications])
            for indication in unique_indications
                count = sum(pair.indication == indication for pair in all_indications)
                avg_confidence = mean([pair.confidence for pair in all_indications if pair.indication == indication])
                println("  - $indication (count: $count, avg confidence: $(round(avg_confidence, digits=2)))")
            end
        end
        
        return true
    else
        println("✗ No indications extracted")
        return false
    end
end

function main()
    # Check if we're on the right environment
    if !occursin("gpu", gethostname())
        println("⚠ Warning: Not on a GPU node. Consider running on gpu2004")
    end
    
    # Test Ollama first
    try
        HTTP.get("http://localhost:11434/api/tags"; connect_timeout=5)
        println("✓ Ollama server is accessible")
    catch
        println("✗ Cannot connect to Ollama. Please ensure:")
        println("  1. You're on gpu2004: ssh gpu2004")
        println("  2. Ollama is loaded: module load ollama")
        println("  3. Ollama is running: ollama serve &")
        println("  4. Model is available: ollama list")
        return false
    end
    
    # Run the test
    return test_levothyroxine_extraction()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
