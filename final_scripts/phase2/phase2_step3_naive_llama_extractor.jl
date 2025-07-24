#!/usr/bin/env julia

"""
Phase 2 Step 3: Naive Llama Drug Indication Extractor

This script processes batches of approved drugs using Llama 3.2's pre-trained knowledge
to extract drug indications without requiring external data sources.

Usage:
    julia phase2_step3_naive_llama_extractor.jl <start_index> <batch_size>

Example:
    julia phase2_step3_naive_llama_extractor.jl 1 100
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera/prompts/llm_prompt_naive.txt"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera/phase2_indications_llama_naive"
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera/generated_dependency_files/approved_drugs_dict.jl"

# Data structures
struct NaiveIndication
    condition::String
    confidence::Float64
    evidence::Bool
    reasoning::String
    extracted_at::String
end

struct NaiveExtractionResult
    drug_name::String
    total_indications::Int
    confirmed_indications::Int
    indications::Vector{NaiveIndication}
    processing_time_seconds::Float64
    extracted_at::String
    model_used::String
    approach::String
end

function load_approved_drugs()
    """Load approved drugs dictionary from generated file"""
    try
        # Include the file to load the APPROVED_DRUGS_DICT constant
        include(APPROVED_DRUGS_FILE)
        
        # Convert to array of drug names
        drug_names = collect(keys(APPROVED_DRUGS_DICT))
        sort!(drug_names)  # Ensure consistent ordering
        
        println("✓ Loaded $(length(drug_names)) approved drugs")
        return drug_names
    catch e
        println("❌ Failed to load approved drugs: $e")
        return String[]
    end
end

function get_processed_drugs()
    """Scan output directory to identify already processed drugs"""
    processed_drugs = Set{String}()
    
    if !isdir(OUTPUT_DIR)
        println("📁 Output directory doesn't exist: $OUTPUT_DIR")
        return processed_drugs
    end
    
    try
        for filename in readdir(OUTPUT_DIR)
            if endswith(filename, "_naive_indications.json")
                # Extract sanitized drug name from filename
                sanitized_name = replace(filename, "_naive_indications.json" => "")
                # Convert back to original name (replace underscores with spaces)
                drug_name = replace(sanitized_name, "_" => " ")
                push!(processed_drugs, drug_name)
            end
        end
        
        println("✓ Found $(length(processed_drugs)) already processed drugs")
        return processed_drugs
    catch e
        println("⚠️ Warning: Failed to scan output directory: $e")
        return processed_drugs
    end
end

function load_prompt_template()
    """Load the naive prompt template from file"""
    try
        prompt_content = read(PROMPT_FILE, String)
        
        # Extract just the prompt template section
        lines = split(prompt_content, '\n')
        in_template = false
        template_lines = String[]
        
        for line in lines
            if contains(line, "PROMPT TEMPLATE:")
                in_template = true
                continue
            elseif in_template && contains(line, "INPUT DATA FORMAT:")
                break
            elseif in_template && !contains(line, "================")
                push!(template_lines, line)
            end
        end
        
        # Find the actual prompt text
        prompt_start = 1
        for (i, line) in enumerate(template_lines)
            if startswith(strip(line), "You are a pharmaceutical researcher") || startswith(strip(line), "You are a medical expert")
                prompt_start = i
                break
            end
        end
        
        return join(template_lines[prompt_start:end], '\n')
    catch e
        println("❌ Failed to load prompt template: $e")
        return nothing
    end
end

function test_ollama_connection()
    """Test if Ollama server is accessible"""
    ollama_host = get(ENV, "OLLAMA_HOST", "http://localhost:11434")
    try
        response = HTTP.get("$ollama_host/api/tags"; connect_timeout=5, readtimeout=10)
        return response.status == 200
    catch e
        println("❌ Cannot connect to Ollama at $ollama_host: $e")
        return false
    end
end

function query_llama(prompt::String; temperature=0.3, max_tokens=1000)
    """Query the Llama model with the given prompt"""
    ollama_host = get(ENV, "OLLAMA_HOST", "http://localhost:11434")
    try
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
            "$ollama_host/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=10,
            readtimeout=120
        )
        
        result = JSON3.read(String(response.body))
        return get(result, "response", "")
    catch e
        println("❌ Llama query failed: $e")
        return nothing
    end
end

function parse_naive_response(response::String)
    """Parse LLM response for naive extraction"""
    indications = NaiveIndication[]
    
    # Split response by "Indication" markers
    sections = split(response, r"Indication\s+\d+:")
    
    # Skip first section (usually empty or contains preamble)
    for section in sections[2:end]
        # Parse evidence, confidence, and reasoning from section
        evidence = false
        confidence = 0.0
        reasoning = ""
        
        for line in split(section, '\n')
            line = strip(line)
            if startswith(uppercase(line), "EVIDENCE:")
                evidence_text = strip(replace(line, r"^EVIDENCE:\s*"i => ""))
                evidence = uppercase(evidence_text) == "YES"
            elseif startswith(uppercase(line), "CONFIDENCE:")
                confidence_text = strip(replace(line, r"^CONFIDENCE:\s*"i => ""))
                try
                    confidence = parse(Float64, confidence_text)
                    confidence = clamp(confidence, 0.0, 1.0)
                catch
                    confidence = 0.0
                end
            elseif startswith(uppercase(line), "REASONING:")
                reasoning = strip(replace(line, r"^REASONING:\s*"i => ""))
            end
        end
        
        # Extract condition name from reasoning
        condition = ""
        if !isempty(reasoning)
            # Look for pattern "ConditionName - Description"
            if contains(reasoning, " - ")
                condition = strip(split(reasoning, " - ")[1])
            else
                # Use first few words as condition name
                words = split(reasoning)
                condition = join(words[1:min(3, length(words))], " ")
            end
        end
        
        if !isempty(condition) && confidence > 0
            indication = NaiveIndication(
                condition,
                confidence,
                evidence,
                reasoning,
                string(now())
            )
            push!(indications, indication)
        end
    end
    
    return indications
end

function process_drug_naive(drug_name::String, prompt_template::String)
    """Process a single drug using naive knowledge-based extraction"""
    
    start_time = time()
    
    # Format the prompt with drug name
    prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
    
    # Query Llama
    response = query_llama(prompt)
    
    if response === nothing
        println("❌ Failed to get response from Llama for $drug_name")
        return nothing
    end
    
    # Parse response
    indications = parse_naive_response(response)
    
    # Count confirmed indications
    confirmed_count = count(ind -> ind.confidence >= CONFIDENCE_THRESHOLD, indications)
    
    # Create result
    processing_time = time() - start_time
    result = NaiveExtractionResult(
        drug_name,
        length(indications),
        confirmed_count,
        indications,
        processing_time,
        string(now()),
        MODEL_NAME,
        "naive_knowledge_based"
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

function save_results(result::NaiveExtractionResult)
    """Save results to JSON file"""
    safe_filename = sanitize_filename(result.drug_name)
    output_file = joinpath(OUTPUT_DIR, "$(safe_filename)_naive_indications.json")
    
    try
        # Convert to dictionary for JSON serialization
        output_data = Dict(
            "metadata" => Dict(
                "drug_name" => result.drug_name,
                "total_indications" => result.total_indications,
                "confirmed_indications" => result.confirmed_indications,
                "confirmation_rate_percent" => result.total_indications > 0 ? 
                    round(result.confirmed_indications / result.total_indications * 100, digits=1) : 0.0,
                "processing_time_seconds" => result.processing_time_seconds,
                "extracted_at" => result.extracted_at,
                "model_used" => result.model_used,
                "approach" => result.approach,
                "confidence_threshold" => CONFIDENCE_THRESHOLD
            ),
            "indications" => [Dict(
                "indication" => ind.condition,
                "confidence" => ind.confidence,
                "evidence" => ind.evidence,
                "reasoning" => ind.reasoning,
                "extracted_at" => ind.extracted_at,
                "confirmed" => ind.confidence >= CONFIDENCE_THRESHOLD
            ) for ind in result.indications]
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

function main()
    """Main function to run batch naive extraction"""
    println("=== Phase 2 Step 3: Naive Llama Drug Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    
    # Parse command line arguments
    if length(ARGS) != 2
        println("Usage: julia phase2_step3_naive_llama_extractor.jl <start_index> <batch_size>")
        println("Example: julia phase2_step3_naive_llama_extractor.jl 1 100")
        exit(1)
    end
    
    start_index = parse(Int, ARGS[1])
    batch_size = parse(Int, ARGS[2])
    
    println("📋 Processing batch: start_index=$start_index, batch_size=$batch_size")
    
    # Test Ollama connection
    if !test_ollama_connection()
        println("❌ Exiting due to Ollama connection failure")
        exit(1)
    end
    
    # Load approved drugs
    all_drugs = load_approved_drugs()
    if isempty(all_drugs)
        println("❌ No approved drugs loaded")
        exit(1)
    end
    
    # Get already processed drugs
    processed_drugs = get_processed_drugs()
    
    # Filter out processed drugs
    remaining_drugs = filter(drug -> drug ∉ processed_drugs, all_drugs)
    println("📊 Total drugs: $(length(all_drugs)), Processed: $(length(processed_drugs)), Remaining: $(length(remaining_drugs))")
    
    # Calculate batch boundaries
    end_index = min(start_index + batch_size - 1, length(remaining_drugs))
    
    if start_index > length(remaining_drugs)
        println("✅ All drugs already processed for this batch range")
        exit(0)
    end
    
    batch_drugs = remaining_drugs[start_index:end_index]
    println("🎯 Processing $(length(batch_drugs)) drugs in this batch")
    
    # Load prompt template
    prompt_template = load_prompt_template()
    if prompt_template === nothing
        println("❌ Failed to load prompt template")
        exit(1)
    end
    
    # Process each drug in the batch
    processed_count = 0
    failed_count = 0
    
    for (i, drug_name) in enumerate(batch_drugs)
        println("\n[$(i)/$(length(batch_drugs))] Processing: $drug_name")
        
        result = process_drug_naive(drug_name, prompt_template)
        
        if result !== nothing
            if save_results(result)
                processed_count += 1
                println("   ✓ $(result.confirmed_indications)/$(result.total_indications) confirmed indications")
            else
                failed_count += 1
                println("   ❌ Failed to save results")
            end
        else
            failed_count += 1
            println("   ❌ Processing failed")
        end
        
        # Small delay to avoid overwhelming the server
        sleep(0.5)
    end
    
    # Final summary
    println("\n=== BATCH PROCESSING COMPLETE ===")
    println("🎯 Batch: $(start_index) to $(end_index)")
    println("✅ Successfully processed: $processed_count")
    println("❌ Failed: $failed_count")
    println("📁 Results saved to: $OUTPUT_DIR")
    println("End time: $(now())")
    
    if failed_count > 0
        println("⚠️ Some drugs failed processing")
        exit(1)
    else
        println("✅ Batch processing completed successfully!")
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end