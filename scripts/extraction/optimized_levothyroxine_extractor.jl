#!/usr/bin/env julia

"""
Optimized Llama 3.2 Drug-Indication Extractor for Levothyroxine
High-performance version with reduced delays, batch processing, and optimizations.
"""

using HTTP
using JSON3
using Dates

println("=== OPTIMIZED Levothyroxine Drug-Indication Extractor ===")
println("Node: $(gethostname())")
println("Start time: $(now())")

# Configuration
const DRUG_FILE = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/Levothyroxine.json"
const OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
const OUTPUT_FILE = joinpath(OUTPUT_DIR, "Levothyroxine_optimized_extraction.json")
const MODEL_NAME = "llama3.2"
const BATCH_SIZE = 100  # Larger batches for progress reporting
const API_DELAY = 0.05  # Reduced from 0.5 to 0.05 seconds
const CHECKPOINT_INTERVAL = 500  # Save intermediate results every 500 publications
const MAX_RETRIES = 2  # Retry failed API calls

# Ensure output directory exists
if !isdir(OUTPUT_DIR)
    mkpath(OUTPUT_DIR)
    println("Created output directory: $OUTPUT_DIR")
end

# Optimized data structures
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
        return false
    end
end

function query_llama_optimized(prompt::String; max_retries::Int=MAX_RETRIES)
    """Optimized Llama query with retry logic and reduced timeout"""
    for attempt in 1:max_retries
        try
            payload = Dict(
                "model" => MODEL_NAME,
                "prompt" => prompt,
                "stream" => false,
                "options" => Dict(
                    "temperature" => 0.1,
                    "num_predict" => 300,  # Reduced from 500
                    "top_p" => 0.9,
                    "top_k" => 40
                )
            )
            
            response = HTTP.post(
                "http://localhost:11434/api/generate",
                ["Content-Type" => "application/json"],
                JSON3.write(payload);
                connect_timeout=5,  # Reduced from 10
                readtimeout=20      # Reduced from 30
            )
            
            result = JSON3.read(String(response.body))
            return get(result, "response", "")
            
        catch e
            if attempt == max_retries
                println("❌ Llama query failed after $max_retries attempts: $e")
                return nothing
            else
                println("⚠️  Retry $attempt/$max_retries for API call")
                sleep(0.1)  # Brief pause before retry
            end
        end
    end
    return nothing
end

function extract_indication_optimized(drug_name::String, title::String, abstract::String, pmid::String)
    """Optimized extraction with shorter prompt and faster parsing"""
    
    # Skip if no meaningful content
    if isempty(title) && isempty(abstract)
        return Indication[]
    end
    
    # Shorter, more focused prompt
    prompt = """Analyze this $drug_name publication for therapeutic indications.

Title: $title
Abstract: $abstract

Extract medical conditions/diseases that $drug_name treats. Use format:
INDICATION: [condition]
CONFIDENCE: [0.1-1.0]

Return "NONE" if no therapeutic uses found."""

    response = query_llama_optimized(prompt)
    if response === nothing
        return Indication[]
    end
    
    # Optimized parsing with fewer operations
    indications = Indication[]
    
    if occursin("NONE", uppercase(response))
        return indications
    end
    
    # Fast line-by-line parsing
    lines = split(response, '\n')
    current_indication = nothing
    current_confidence = 0.5
    current_time = string(now())  # Cache timestamp
    
    for line in lines
        line_upper = uppercase(strip(line))
        if startswith(line_upper, "INDICATION:")
            indication_text = strip(line[12:end])  # Skip "INDICATION:"
            if !isempty(indication_text)
                current_indication = indication_text
            end
        elseif startswith(line_upper, "CONFIDENCE:")
            confidence_text = strip(line[12:end])  # Skip "CONFIDENCE:"
            try
                current_confidence = clamp(parse(Float64, confidence_text), 0.1, 1.0)
            catch
                current_confidence = 0.5
            end
            
            # Save when we have both
            if current_indication !== nothing
                push!(indications, Indication(
                    current_indication,
                    current_confidence,
                    pmid,
                    title,
                    current_time
                ))
                current_indication = nothing
            end
        end
    end
    
    # Handle unpaired indication
    if current_indication !== nothing
        push!(indications, Indication(
            current_indication,
            current_confidence,
            pmid,
            title,
            current_time
        ))
    end
    
    return indications
end

function save_checkpoint(indications::Vector{Indication}, processed_count::Int, successful_count::Int, failed_count::Int)
    """Save intermediate results"""
    checkpoint_file = joinpath(OUTPUT_DIR, "Levothyroxine_checkpoint_$(processed_count).json")
    try
        checkpoint_data = Dict(
            "checkpoint_info" => Dict(
                "processed_publications" => processed_count,
                "successful_extractions" => successful_count,
                "failed_extractions" => failed_count,
                "total_indications" => length(indications),
                "checkpoint_time" => string(now())
            ),
            "indications" => [Dict(
                "indication" => ind.text,
                "confidence" => ind.confidence,
                "pmid" => ind.pmid,
                "title" => ind.title,
                "extracted_at" => ind.extracted_at
            ) for ind in indications]
        )
        
        open(checkpoint_file, "w") do f
            JSON3.write(f, checkpoint_data)
        end
        println("💾 Checkpoint saved: $processed_count publications processed")
    catch e
        println("⚠️  Failed to save checkpoint: $e")
    end
end

function save_results(result::ExtractionResult)
    """Save final results"""
    try
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
                "model_used" => MODEL_NAME,
                "optimization_settings" => Dict(
                    "api_delay" => API_DELAY,
                    "batch_size" => BATCH_SIZE,
                    "max_retries" => MAX_RETRIES
                )
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
    """Optimized main processing function"""
    
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
    publications = data.result.publications_analyzed
    
    println("📊 Found $(length(publications)) publications for Levothyroxine")
    println("🚀 Using optimized settings:")
    println("   - API delay: $(API_DELAY)s (vs 0.5s original)")
    println("   - Batch reporting: every $BATCH_SIZE publications")
    println("   - Checkpoints: every $CHECKPOINT_INTERVAL publications")
    println("   - Max retries: $MAX_RETRIES")
    
    # Initialize tracking
    start_time = time()
    all_indications = Indication[]
    successful_extractions = 0
    failed_extractions = 0
    processed_count = 0
    
    # Optimized processing loop
    for (i, publication) in enumerate(publications)
        processed_count += 1
        
        # Less frequent progress reporting
        if i % BATCH_SIZE == 0 || i == length(publications)
            elapsed = time() - start_time
            rate = i / elapsed
            eta = (length(publications) - i) / rate
            println("📈 Progress: $i/$(length(publications)) ($(round(i/length(publications)*100, digits=1))%) | Rate: $(round(rate, digits=1)) pubs/sec | ETA: $(round(eta/60, digits=1)) min")
        end
        
        try
            pmid = get(publication, "pmid", "unknown_$i")
            title = get(publication, "title", "")
            abstract = get(publication, "abstract", "")
            
            # Extract indications (no verbose logging per publication)
            indications = extract_indication_optimized("Levothyroxine", title, abstract, pmid)
            
            if !isempty(indications)
                append!(all_indications, indications)
                successful_extractions += 1
                # Only log significant finds
                if length(indications) > 1
                    println("🎯 Found $(length(indications)) indications in PMID $pmid")
                end
            end
            
            # Minimal delay (10x faster than original)
            sleep(API_DELAY)
            
        catch e
            failed_extractions += 1
            # Only log failures occasionally
            if failed_extractions % 10 == 0
                println("❌ $failed_extractions failures so far (latest: publication $i)")
            end
        end
        
        # Periodic checkpoints
        if i % CHECKPOINT_INTERVAL == 0
            save_checkpoint(all_indications, processed_count, successful_extractions, failed_extractions)
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
    
    # Print optimized summary
    println("\n=== OPTIMIZED EXTRACTION COMPLETE ===")
    println("🎯 Drug: Levothyroxine")
    println("📚 Total publications: $(result.total_publications)")
    println("✅ Successful extractions: $(result.successful_extractions)")
    println("❌ Failed extractions: $(result.failed_extractions)")
    println("🔬 Total indications found: $(result.total_indications)")
    println("⏱️  Processing time: $(round(result.processing_time_seconds/60, digits=2)) minutes")
    println("🚀 Processing rate: $(round(result.total_publications/result.processing_time_seconds, digits=1)) publications/second")
    
    if !isempty(result.indications)
        println("\n📋 Unique indications found:")
        unique_indications = unique([ind.text for ind in result.indications])
        for indication in sort(unique_indications)
            count = length([ind for ind in result.indications if ind.text == indication])
            println("   - $indication (found in $count publications)")
        end
    end
    
    # Save results
    if save_results(result)
        println("\n✅ Optimized extraction completed successfully!")
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
