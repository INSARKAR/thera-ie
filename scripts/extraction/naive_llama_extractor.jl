#!/usr/bin/env julia

"""
Naive Llama Drug Indication Extractor

This script uses Llama 3.2's pre-trained knowledge to extract drug indications
without requiring external data sources like PubMed or DrugBank.

Usage:
    julia naive_llama_extractor.jl [drug_name]

If no drug name is provided, it will use "Levothyroxine" as the default.
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera/prompts/llm_prompt_naive.txt"

# Ollama configuration
# Note: OLLAMA_HOST will be read from environment when needed, not as a constant

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
            if startswith(strip(line), "You are a medical expert")
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

function process_drug_naive(drug_name::String)
    """Process a single drug using naive knowledge-based extraction"""
    
    start_time = time()
    println("\n🎯 Processing $drug_name using naive knowledge-based extraction...")
    
    # Load prompt template
    prompt_template = load_prompt_template()
    if prompt_template === nothing
        println("❌ Failed to load prompt template")
        return nothing
    end
    
    # Format the prompt with drug name
    prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
    
    # Query Llama
    println("🤖 Querying Llama 3.2 for known indications...")
    response = query_llama(prompt)
    
    if response === nothing
        println("❌ Failed to get response from Llama")
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
    
    # Print summary
    println("\n=== NAIVE EXTRACTION COMPLETE ===")
    println("🎯 Drug: $(result.drug_name)")
    println("📋 Total indications found: $(result.total_indications)")
    println("✅ Confirmed indications (≥$(CONFIDENCE_THRESHOLD)): $(result.confirmed_indications)")
    println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2)) seconds")
    
    # Print indications
    if !isempty(result.indications)
        println("\n📋 Indications found:")
        for (i, ind) in enumerate(result.indications)
            status = ind.confidence >= CONFIDENCE_THRESHOLD ? "✓" : "○"
            println("   $status $(ind.condition) (confidence: $(ind.confidence))")
            println("     → $(ind.reasoning)")
        end
    end
    
    return result
end

function save_results(result::NaiveExtractionResult, output_file::String)
    """Save results to JSON file"""
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
                "condition" => ind.condition,
                "confidence" => ind.confidence,
                "evidence" => ind.evidence,
                "reasoning" => ind.reasoning,
                "extracted_at" => ind.extracted_at,
                "confirmed" => ind.confidence >= CONFIDENCE_THRESHOLD
            ) for ind in result.indications]
        )
        
        # Create output directory if it doesn't exist
        mkpath(dirname(output_file))
        
        # Write results to file
        open(output_file, "w") do file
            JSON3.pretty(file, output_data)
        end
        
        println("\n✓ Results saved to: $output_file")
        return true
    catch e
        println("\n❌ Failed to save results: $e")
        return false
    end
end

function main()
    """Main function to run the naive extraction"""
    println("=== Naive Llama Drug Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    
    # Get drug name from command line argument or use default
    drug_name = length(ARGS) > 0 ? ARGS[1] : "Levothyroxine"
    
    # Test Ollama connection
    if !test_ollama_connection()
        println("❌ Exiting due to Ollama connection failure")
        exit(1)
    end
    
    # Process the drug
    result = process_drug_naive(drug_name)
    
    if result !== nothing
        # Define output file
        output_dir = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications"
        output_file = joinpath(output_dir, "$(drug_name)_naive_extracted_indications.json")
        
        # Save results
        if save_results(result, output_file)
            println("\n✅ Naive extraction completed successfully!")
        else
            println("\n⚠️  Naive extraction completed but failed to save results")
            exit(1)
        end
    else
        println("\n❌ Naive extraction failed")
        exit(1)
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end