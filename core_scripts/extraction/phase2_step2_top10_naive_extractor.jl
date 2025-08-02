#!/usr/bin/env julia

"""
THERA-IE Phase 2 Step 2: Top 10 Knowledge-Based SNOMED Indication Extractor

This script processes the top 10 US prescribed drugs using Llama 3.2's pre-trained pharmaceutical knowledge
to extract drug indications with direct SNOMED CT terminology output, eliminating the need 
for post-processing normalization.

Key Features:
- Uses LLM's pre-trained knowledge (no external data dependencies)
- Outputs standardized SNOMED CT codes and terms directly
- Research categorization prompt to avoid LLM safety restrictions
- Efficient single-query per drug approach
- Comprehensive retry logic with exponential backoff
- Resume capability for fault tolerance

Usage:
    julia phase2_step2_top10_naive_extractor.jl

Author: THERA-IE System
Date: 2025-08-02
Version: 1.0 (Top 10 Knowledge-Based SNOMED CT Extraction)
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const PROMPT_FILE = "prompts/llm_prompt_naive_snomed_top10.txt"
const OUTPUT_DIR = "phase2_step2_naive_snomed"
const TOP10_FILE = "top_10_drugs_us.txt"

# Data structures for SNOMED CT output
struct SnomedNaiveIndication
    snomed_code::String
    snomed_term::String
    confidence::Float64
    evidence::Bool
    reasoning::String
    extracted_at::String
end

struct SnomedNaiveExtractionResult
    drug_name::String
    total_indications::Int
    confirmed_indications::Int
    snomed_indications::Vector{SnomedNaiveIndication}
    processing_time_seconds::Float64
    extracted_at::String
    model_used::String
    approach::String
    raw_llm_response::String
end

function get_ollama_host()
    """Get Ollama host from environment or default"""
    return get(ENV, "OLLAMA_HOST", "http://localhost:11434")
end

function test_ollama_connection(ollama_host::String)
    """Test if Ollama server is accessible"""
    try
        response = HTTP.get("$(ollama_host)/api/tags"; connect_timeout=5, readtimeout=10)
        if response.status == 200
            println("✓ Ollama server accessible at $ollama_host")
            return true
        else
            println("❌ Ollama server returned status $(response.status)")
            return false
        end
    catch e
        println("❌ Cannot connect to Ollama at $ollama_host: $e")
        println("Please ensure Ollama is running and accessible")
        return false
    end
end

function load_top10_drugs()
    """Load top 10 drugs list"""
    try
        drugs = String[]
        open(TOP10_FILE, "r") do f
            for line in eachline(f)
                drug = strip(line)
                if !isempty(drug)
                    push!(drugs, drug)
                end
            end
        end
        
        # Take only first 10
        drugs = drugs[1:min(10, length(drugs))]
        println("✓ Loaded $(length(drugs)) top drugs")
        return drugs
    catch e
        println("❌ Failed to load top 10 drugs: $e")
        return nothing
    end
end

function load_snomed_naive_prompt_template()
    """Load the SNOMED CT naive prompt template from file"""
    try
        if !isfile(PROMPT_FILE)
            println("❌ Prompt file not found: $PROMPT_FILE")
            return nothing
        end
        
        prompt_content = read(PROMPT_FILE, String)
        println("✓ Loaded prompt template ($(length(prompt_content)) characters)")
        return prompt_content
    catch e
        println("❌ Failed to load SNOMED CT naive prompt template: $e")
        return nothing
    end
end

function query_llama(prompt::String, ollama_host::String; temperature=0.3, max_tokens=2000, max_retries=5)
    """Query the Llama model with the given prompt, with retry logic"""
    
    for attempt in 1:max_retries
        try
            if attempt > 1
                wait_time = 2^(attempt-1)
                println("  ⏳ Retry attempt $attempt/$max_retries, waiting $wait_time seconds...")
                sleep(wait_time)
            end
            
            payload = Dict(
                "model" => MODEL_NAME,
                "prompt" => prompt,
                "stream" => false,
                "options" => Dict(
                    "temperature" => temperature,
                    "num_predict" => max_tokens
                )
            )
            
            response = HTTP.post(
                "$(ollama_host)/api/generate",
                ["Content-Type" => "application/json"],
                JSON3.write(payload);
                connect_timeout=10,
                readtimeout=180
            )
            
            if response.status == 200
                result = JSON3.read(String(response.body))
                llm_response = strip(get(result, "response", ""))
                
                if isempty(llm_response)
                    println("⚠️ Warning: LLM returned empty response on attempt $attempt")
                    continue
                elseif length(llm_response) < 50
                    println("⚠️ Warning: LLM returned very short response on attempt $attempt")
                    continue
                end
                return llm_response
            else
                println("❌ HTTP error $(response.status) on attempt $attempt")
                continue
            end
        catch e
            println("❌ Llama query failed on attempt $attempt/$max_retries: $e")
            if attempt == max_retries
                return ""
            end
        end
    end
    
    return ""
end

function parse_snomed_naive_response(llm_response::AbstractString)
    """Parse LLM response to extract SNOMED indications for naive approach"""
    indications = SnomedNaiveIndication[]
    
    # Convert to string for consistency
    response_str = string(llm_response)
    
    # Check for safety refusal
    if contains(response_str, "I can't provide medical advice") || 
       contains(response_str, "I cannot provide medical") ||
       contains(response_str, "medical advice")
        return indications
    end
    
    # Split response into indication blocks using regex split
    # This handles "Research Finding N:", "Research Finding 1:", etc.
    blocks = split(response_str, r"(?=Research Finding)")
    
    # Remove the first block if it's just introductory text
    if length(blocks) > 1 && !contains(blocks[1], r"Research Finding")
        blocks = blocks[2:end]
    end
    
    for block in blocks
        try
            # Extract SNOMED code (handle complex codes like "123456007 | 117427009")
            snomed_code_match = match(r"SNOMED_CODE:\s*([^\n]+)", block)
            raw_snomed_code = snomed_code_match !== nothing ? strip(snomed_code_match.captures[1]) : ""
            
            # Clean up SNOMED code - extract first code if multiple codes are present
            snomed_code = ""
            if !isempty(raw_snomed_code)
                # Extract primary code (before any | or parentheses)
                primary_match = match(r"(\d+)", raw_snomed_code)
                snomed_code = primary_match !== nothing ? primary_match.captures[1] : strip(raw_snomed_code)
            end
            
            # Extract SNOMED term (handle various formatting including SNOMED.Term and SNOMED_TERM)
            snomed_term_match = match(r"SNOMED[._\s]*T[Ee]?[Rr]?[Mm]?[._\s]*:\s*([^\n]+)", block)
            if snomed_term_match === nothing
                # Try alternative format
                snomed_term_match = match(r"SNOMED_TERM:\s*([^\n]+)", block)
            end
            snomed_term = snomed_term_match !== nothing ? strip(snomed_term_match.captures[1]) : ""
            
            # Extract confidence
            confidence_match = match(r"CONFIDENCE:\s*([0-9.]+)", block)
            confidence = confidence_match !== nothing ? parse(Float64, confidence_match.captures[1]) : 0.0
            
            # Extract evidence flag
            evidence_match = match(r"EVIDENCE:\s*(YES|NO)", block)
            evidence = evidence_match !== nothing ? (evidence_match.captures[1] == "YES") : false
            
            # Extract reasoning (improved to capture full text)
            reasoning_match = match(r"REASONING:\s*([^\n]*(?:\n(?!Research Finding)[^\n]*)*)", block)
            reasoning = reasoning_match !== nothing ? strip(reasoning_match.captures[1]) : ""
            
            # Only add if we have valid SNOMED code and term
            if !isempty(snomed_code) && !isempty(snomed_term)
                indication = SnomedNaiveIndication(
                    snomed_code,
                    snomed_term,
                    confidence,
                    evidence,
                    reasoning,
                    string(now())
                )
                push!(indications, indication)
            end
        catch e
            println("⚠️ Warning: Failed to parse indication block: $e")
            continue
        end
    end
    
    # Deduplicate based on SNOMED term to avoid repetitive entries
    unique_indications = SnomedNaiveIndication[]
    seen_terms = Set{String}()
    
    for indication in indications
        if !(indication.snomed_term in seen_terms)
            push!(unique_indications, indication)
            push!(seen_terms, indication.snomed_term)
        end
    end
    
    return unique_indications
end

function process_drug_snomed_naive(drug_name::String, prompt_template::String, ollama_host::String)
    """Process a single drug using SNOMED CT knowledge-based extraction"""
    
    start_time = time()
    
    # Format the prompt with drug name
    prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
    
    # Query Llama with retry logic
    llm_response = query_llama(prompt, ollama_host)
    
    if isempty(llm_response)
        println("❌ Failed to get response from Llama for $drug_name")
        return nothing
    end
    
    # Check for LLM refusal
    if contains(llm_response, "I can't provide medical advice") || 
       contains(llm_response, "I cannot provide medical") ||
       contains(llm_response, "medical advice")
        println("⚠️ LLM refused to provide medical information for $drug_name")
        # Still create a result but with empty indications
        processing_time = time() - start_time
        return SnomedNaiveExtractionResult(
            drug_name,
            0,
            0,
            SnomedNaiveIndication[],
            processing_time,
            string(now()),
            MODEL_NAME,
            "snomed_naive_knowledge_based",
            llm_response
        )
    end
    
    # Parse response for SNOMED indications
    snomed_indications = parse_snomed_naive_response(llm_response)
    
    # Count confirmed indications
    confirmed_count = count(ind -> ind.confidence >= CONFIDENCE_THRESHOLD, snomed_indications)
    
    # Create result
    processing_time = time() - start_time
    result = SnomedNaiveExtractionResult(
        drug_name,
        length(snomed_indications),
        confirmed_count,
        snomed_indications,
        processing_time,
        string(now()),
        MODEL_NAME,
        "snomed_naive_knowledge_based",
        llm_response
    )
    
    return result
end

function sanitize_filename(drug_name::String)
    """Convert drug name to safe filename by replacing spaces with underscores and removing problematic characters"""
    # Remove quotes and replace spaces with underscores
    sanitized = replace(drug_name, "\"" => "", "'" => "", " " => "_")
    # Remove other problematic characters for filenames
    sanitized = replace(sanitized, r"[<>:\"/\\|?*]" => "_")
    return sanitized
end

function save_snomed_naive_results(result::SnomedNaiveExtractionResult)
    """Save SNOMED CT naive results to JSON file with consistent format"""
    safe_filename = sanitize_filename(result.drug_name)
    output_file = joinpath(OUTPUT_DIR, "$(safe_filename)_naive_snomed.json")
    
    try
        # Convert to dictionary for JSON serialization
        output_data = Dict(
            "drug_name" => result.drug_name,
            "snomed_indications" => [Dict(
                "snomed_code" => ind.snomed_code,
                "snomed_term" => ind.snomed_term,
                "confidence" => ind.confidence,
                "evidence" => ind.evidence,
                "reasoning" => ind.reasoning,
                "extracted_at" => ind.extracted_at,
                "confirmed" => ind.confidence >= CONFIDENCE_THRESHOLD
            ) for ind in result.snomed_indications],
            "metadata" => Dict(
                "total_indications_found" => result.total_indications,
                "confirmed_indications" => result.confirmed_indications,
                "confirmation_rate_percent" => result.total_indications > 0 ? 
                    round(result.confirmed_indications / result.total_indications * 100, digits=1) : 0.0,
                "processing_time_seconds" => result.processing_time_seconds,
                "processing_timestamp" => result.extracted_at,
                "model_used" => result.model_used,
                "approach" => result.approach,
                "confidence_threshold" => CONFIDENCE_THRESHOLD
            ),
            "debug_info" => Dict(
                "raw_llm_response" => result.raw_llm_response,
                "llm_failed" => result.total_indications == 0 && contains(result.raw_llm_response, "medical advice"),
                "failure_reason" => result.total_indications == 0 && contains(result.raw_llm_response, "medical advice") ? "LLM safety refusal" : "",
                "processing_notes" => result.total_indications > 0 ? "Successful SNOMED CT knowledge-based extraction" : "No indications extracted"
            )
        )
        
        # Create output directory if it doesn't exist
        mkpath(OUTPUT_DIR)
        
        # Write results to file
        open(output_file, "w") do file
            JSON3.pretty(file, output_data)
        end
        
        return true
    catch e
        println("❌ Failed to save results for $(result.drug_name): $e")
        return false
    end
end

function check_existing_output(drug_name::String)
    """Check if output file already exists for this drug"""
    safe_filename = sanitize_filename(drug_name)
    output_file = joinpath(OUTPUT_DIR, "$(safe_filename)_naive_snomed.json")
    return isfile(output_file)
end

function main()
    """Main function to process top 10 drugs with knowledge-based SNOMED CT extraction"""
    
    println("=== THERA-IE Phase 2 Step 2: Top 10 Knowledge-Based SNOMED Extraction ===")
    println("Start time: $(now())")
    println("")
    
    # Get Ollama host
    ollama_host = get_ollama_host()
    println("Using Ollama host: $ollama_host")
    
    # Test Ollama connection
    if !test_ollama_connection(ollama_host)
        exit(1)
    end
    
    # Load top 10 drugs
    top10_drugs = load_top10_drugs()
    if top10_drugs === nothing
        exit(1)
    end
    
    println("📊 Top 10 drugs to process: $(length(top10_drugs))")
    for (i, drug) in enumerate(top10_drugs)
        println("   $i. $drug")
    end
    println("")
    
    # Load SNOMED CT naive prompt template
    prompt_template = load_snomed_naive_prompt_template()
    if prompt_template === nothing
        exit(1)
    end
    
    # Filter drugs to process (skip already completed)
    drugs_to_process = []
    for drug_name in top10_drugs
        if !check_existing_output(drug_name)
            push!(drugs_to_process, drug_name)
        end
    end
    
    already_processed = length(top10_drugs) - length(drugs_to_process)
    println("✅ Already processed: $already_processed drugs")
    println("📋 To process: $(length(drugs_to_process)) drugs")
    println("")
    
    # Process each drug
    processed_count = 0
    failed_count = 0
    start_time = time()
    
    for (idx, drug_name) in enumerate(drugs_to_process)
        println("=== Processing $idx/$(length(drugs_to_process)) ===")
        println("🔍 Drug: $drug_name")
        
        # Process the drug using knowledge-based approach
        result = process_drug_snomed_naive(drug_name, prompt_template, ollama_host)
        if result === nothing
            failed_count += 1
            continue
        end
        
        # Save results
        if save_snomed_naive_results(result)
            processed_count += 1
            println("✅ Extracted $(result.total_indications) SNOMED CT indications ($(result.confirmed_indications) confirmed)")
            println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2))s")
        else
            failed_count += 1
        end
        
        println("")
        
        # Small delay to avoid overwhelming the API
        sleep(1.0)
    end
    
    # Final summary
    total_time = time() - start_time
    println("")
    println("=== PHASE 2 STEP 2 COMPLETE ===")
    println("✅ Successfully processed: $processed_count drugs")
    println("⏭️  Already processed: $already_processed drugs")
    println("❌ Failed: $failed_count drugs")
    println("📊 Total drugs: $(length(top10_drugs)) drugs")
    println("⏱️  Total time: $(round(total_time / 60, digits=1)) minutes")
    if processed_count > 0
        println("📈 Processing rate: $(round(processed_count / (total_time / 60), digits=1)) drugs/min")
    end
    println("📁 Output directory: $OUTPUT_DIR")
    println("End time: $(now())")
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end