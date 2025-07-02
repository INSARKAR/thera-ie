#!/usr/bin/env julia

"""
Fresh Llama 3.2 Drug-Indication Extractor for Levothyroxine
Based on the working quick test approach, but designed for full processing.

This script processes all publications for Levothyroxine using the same approach
that worked in the quick test.
"""

using HTTP
using JSON3
using Dates

println("=== Levothyroxine Drug-Indication Extractor ===")
println("Node: $(gethostname())")
println("Start time: $(now())")

# Configuration
const DRUG_FILE = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/Levothyroxine.json"
const OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
const OUTPUT_FILE = joinpath(OUTPUT_DIR, "Levothyroxine_fresh_extraction.json")
const MODEL_NAME = "llama3.2"
const BATCH_SIZE = 50  # Process in smaller batches for monitoring

# Ensure output directory exists
if !isdir(OUTPUT_DIR)
    mkpath(OUTPUT_DIR)
    println("Created output directory: $OUTPUT_DIR")
end

# Simple data structures (same as working quick test)
struct Indication
    text::String
    confidence::Float64
    pmid::String
    title::String
    extracted_at::String
end

struct ExtractionResult
    drug_name::String
    total_publications::Int
    processed_publications::Int
    successful_extractions::Int
    failed_extractions::Int
    total_indications::Int
    indications::Vector{Indication}
    processing_time_seconds::Float64
    extracted_at::String
end

function test_ollama_connection()
    println("🔍 Testing Ollama connection...")
    try
        response = HTTP.get("http://localhost:11434/api/tags"; connect_timeout=5)
        println("✓ Ollama server is accessible")
        return true
    catch e
        println("❌ Cannot connect to Ollama: $e")
        println("Please ensure Ollama is running and accessible")
        return false
    end
end

function query_llama_simple(prompt::String)
    """Simple Llama query function (same as working quick test)"""
    try
        payload = Dict(
            "model" => MODEL_NAME,
            "prompt" => prompt,
            "stream" => false,
            "options" => Dict(
                "temperature" => 0.1,
                "num_predict" => 500
            )
        )
        
        response = HTTP.post(
            "http://localhost:11434/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=10,
            readtimeout=30
        )
        
        result = JSON3.read(String(response.body))
        return get(result, "response", "")
    catch e
        println("❌ Llama query failed: $e")
        return nothing
    end
end

function extract_indication(drug_name::String, title::String, abstract::String, pmid::String)
    """Extract indications from a publication (same logic as working quick test)"""
    
    # Skip if no meaningful content
    if isempty(title) && isempty(abstract)
        return Indication[]
    end
    
    # Create focused prompt
    prompt = """
You are a medical expert analyzing a research publication about $drug_name.

Title: $title

Abstract: $abstract

Task: Identify any medical conditions, diseases, or therapeutic indications that $drug_name is used to treat based on this publication.

Rules:
1. Only extract clear therapeutic uses/indications
2. Use standard medical terminology
3. Be specific (e.g., "hypothyroidism" not "thyroid problems")
4. Rate confidence 0.1-1.0 based on how clearly the indication is stated
5. Return "NONE" if no clear therapeutic indications are found

Format your response exactly as:
INDICATION: [condition name]
CONFIDENCE: [0.1-1.0]

If multiple indications, use multiple INDICATION/CONFIDENCE pairs.
If no indications found, respond with just: NONE
"""

    response = query_llama_simple(prompt)
    if response === nothing
        return Indication[]
    end
    
    # Parse response (same logic as quick test)
    indications = Indication[]
    
    if occursin("NONE", uppercase(response))
        return indications
    end
    
    lines = split(response, '\n')
    current_indication = nothing
    current_confidence = 0.5
    
    for line in lines
        line = strip(line)
        if startswith(uppercase(line), "INDICATION:")
            indication_text = strip(replace(line, r"^INDICATION:\s*"i => ""))
            if !isempty(indication_text)
                current_indication = indication_text
            end
        elseif startswith(uppercase(line), "CONFIDENCE:")
            confidence_text = strip(replace(line, r"^CONFIDENCE:\s*"i => ""))
            try
                current_confidence = parse(Float64, confidence_text)
                current_confidence = clamp(current_confidence, 0.1, 1.0)
            catch
                current_confidence = 0.5
            end
            
            # When we have both indication and confidence, save it
            if current_indication !== nothing
                push!(indications, Indication(
                    current_indication,
                    current_confidence,
                    pmid,
                    title,
                    string(now())
                ))
                current_indication = nothing
            end
        end
    end
    
    # Handle case where indication was found but no confidence specified
    if current_indication !== nothing
        push!(indications, Indication(
            current_indication,
            current_confidence,
            pmid,
            title,
            string(now())
        ))
    end
    
    return indications
end

function save_results(result::ExtractionResult)
    """Save results to JSON file"""
    try
        # Convert to dictionary for JSON serialization
        output_data = Dict(
            "metadata" => Dict(
                "drug_name" => result.drug_name,
                "total_publications" => result.total_publications,
                "processed_publications" => result.processed_publications,
                "successful_extractions" => result.successful_extractions,
                "failed_extractions" => result.failed_extractions,
                "total_indications" => result.total_indications,
                "success_rate_percent" => result.successful_extractions / max(1, result.processed_publications) * 100,
                "processing_time_seconds" => result.processing_time_seconds,
                "extracted_at" => result.extracted_at,
                "model_used" => MODEL_NAME
            ),
            "indications" => [Dict(
                "indication" => ind.text,
                "confidence" => ind.confidence,
                "pmid" => ind.pmid,
                "title" => ind.title,
                "extracted_at" => ind.extracted_at
            ) for ind in result.indications]
        )
        
        open(OUTPUT_FILE, "w") do f
            JSON3.pretty(f, output_data)
        end
        
        println("✓ Results saved to: $OUTPUT_FILE")
        return true
    catch e
        println("❌ Failed to save results: $e")
        return false
    end
end

function main()
    """Main processing function"""
    
    # Test Ollama connection
    if !test_ollama_connection()
        println("❌ Exiting due to Ollama connection failure")
        exit(1)
    end
    
    # Load drug data
    println("📖 Loading Levothyroxine publications...")
    if !isfile(DRUG_FILE)
        println("❌ Drug file not found: $DRUG_FILE")
        exit(1)
    end
    
    data = JSON3.read(read(DRUG_FILE, String))
    publications = data.result.publications_analyzed  # Correct path based on structure analysis
    
    println("📊 Found $(length(publications)) publications for Levothyroxine")
    
    # Initialize tracking
    start_time = time()
    all_indications = Indication[]
    successful_extractions = 0
    failed_extractions = 0
    processed_count = 0
    
    # Process publications
    for (i, publication) in enumerate(publications)
        processed_count += 1
        
        # Progress reporting
        if i % BATCH_SIZE == 0 || i == length(publications)
            println("📈 Progress: $i/$(length(publications)) publications processed")
        end
        
        try
            pmid = get(publication, "pmid", "unknown_$i")
            title = get(publication, "title", "")
            abstract = get(publication, "abstract", "")
            
            println("🔍 Processing publication $i: PMID $pmid")
            
            # Extract indications using the working approach
            indications = extract_indication("Levothyroxine", title, abstract, pmid)
            
            if !isempty(indications)
                append!(all_indications, indications)
                successful_extractions += 1
                println("✓ Extracted $(length(indications)) indication(s) from PMID $pmid")
                for ind in indications
                    println("   - $(ind.text) (confidence: $(ind.confidence))")
                end
            else
                println("  No indications found in PMID $pmid")
            end
            
            # Small delay to avoid overwhelming the API
            sleep(0.5)
            
        catch e
            failed_extractions += 1
            println("❌ Failed to process publication $i: $e")
        end
    end
    
    # Calculate final results
    processing_time = time() - start_time
    
    result = ExtractionResult(
        "Levothyroxine",
        length(publications),
        processed_count,
        successful_extractions,
        failed_extractions,
        length(all_indications),
        all_indications,
        processing_time,
        string(now())
    )
    
    # Print summary
    println("\n=== EXTRACTION COMPLETE ===")
    println("🎯 Drug: Levothyroxine")
    println("📚 Total publications: $(result.total_publications)")
    println("✅ Successful extractions: $(result.successful_extractions)")
    println("❌ Failed extractions: $(result.failed_extractions)")
    println("🔬 Total indications found: $(result.total_indications)")
    println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2)) seconds")
    
    if !isempty(result.indications)
        println("\n📋 Unique indications found:")
        unique_indications = unique([ind.text for ind in result.indications])
        for indication in unique_indications
            count = length([ind for ind in result.indications if ind.text == indication])
            println("   - $indication (found in $count publications)")
        end
    end
    
    # Save results
    if save_results(result)
        println("\n✅ Extraction completed successfully!")
        println("📁 Results saved to: $OUTPUT_FILE")
    else
        println("\n⚠️  Extraction completed but failed to save results")
        exit(1)
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
