#!/usr/bin/env julia

"""
Enhanced Naive Llama Drug Indication Extractor

This script uses Llama 3.2's pre-trained knowledge to extract drug indications
and includes the raw LLM response for later analysis.

Usage:
    julia enhanced_naive_llama_extractor.jl [drug_name]

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

struct EnhancedNaiveExtractionResult
    drug_name::String
    total_indications::Int
    confirmed_indications::Int
    indications::Vector{NaiveIndication}
    processing_time_seconds::Float64
    extracted_at::String
    model_used::String
    approach::String
    raw_llm_response::String  # NEW: Include raw LLM response
    prompt_used::String       # NEW: Include the prompt for analysis
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
    """Parse LLM response for naive extraction - simplified robust approach"""
    indications = NaiveIndication[]
    
    # Split response into lines and process line by line
    lines = split(response, '\n')
    current_indication = Dict()
    
    for line in lines
        line = strip(line)
        
        # Skip empty lines
        if isempty(line)
            continue
        end
        
        # Check if this line starts a new indication (numbered pattern, "Indication X:", or condition name with colon)
        if occursin(r"^\d+\.", line) || occursin(r"^Indication\s+\d+:", line) || 
           (occursin(r"^[A-Za-z].*:$", line) && !occursin(r"^(EVIDENCE|CONFIDENCE|REASONING):", line))
            # Process previous indication if complete
            if haskey(current_indication, "evidence") && haskey(current_indication, "confidence") && haskey(current_indication, "reasoning")
                indication = create_indication_from_dict(current_indication)
                if indication !== nothing
                    push!(indications, indication)
                end
            end
            
            # Start new indication
            current_indication = Dict()
            
            # Extract header - handle multiple formats
            if occursin(r"Indication", line)
                # Format: "1. Indication 1:" or "Indication 1:" or "1. Indication 1: Condition Name"
                if occursin(r"^\d+\.", line)
                    # Check if there's a condition name after "Indication X:"
                    if occursin(r"Indication\s+\d+:\s*(.+)", line)
                        match_result = match(r"Indication\s+\d+:\s*(.+)", line)
                        if match_result !== nothing && !isempty(strip(match_result.captures[1]))
                            current_indication["header"] = strip(match_result.captures[1])
                        else
                            current_indication["header"] = strip(replace(line, r"^\d+\.\s*" => ""))
                        end
                    else
                        current_indication["header"] = strip(replace(line, r"^\d+\.\s*" => ""))
                    end
                else
                    # Check if there's a condition name after "Indication X:"
                    if occursin(r"Indication\s+\d+:\s*(.+)", line)
                        match_result = match(r"Indication\s+\d+:\s*(.+)", line)
                        if match_result !== nothing && !isempty(strip(match_result.captures[1]))
                            current_indication["header"] = strip(match_result.captures[1])
                        else
                            current_indication["header"] = strip(replace(line, r"^Indication\s+\d+:\s*" => ""))
                        end
                    else
                        current_indication["header"] = strip(replace(line, r"^Indication\s+\d+:\s*" => ""))
                    end
                end
            elseif occursin(r"^\d+\.\s+.*:", line) && !occursin(r"^\d+\.\s+(EVIDENCE|CONFIDENCE|REASONING)", line)
                # Format: "1. CONDITION NAME:" (any condition name followed by colon, excluding field names)
                header = strip(replace(line, r"^\d+\.\s+" => ""))
                header = strip(replace(header, r":$" => ""))
                current_indication["header"] = header
            elseif occursin(r"^[A-Za-z].*:$", line) && !occursin(r"^(EVIDENCE|CONFIDENCE|REASONING):", line)
                # Format: "Condition Name:" (condition name without numbers)
                header = strip(replace(line, r":$" => ""))
                current_indication["header"] = header
            end
        elseif occursin(r"^EVIDENCE:\s*"i, line)
            evidence_text = strip(replace(line, r"^EVIDENCE:\s*"i => ""))
            # Handle various evidence formats: YES, NO, PARTIALLY CONFIRMED, etc.
            current_indication["evidence"] = occursin(r"YES|PARTIALLY|CONFIRMED|TRUE"i, evidence_text)
        elseif occursin(r"^CONFIDENCE:\s*"i, line)
            confidence_text = strip(replace(line, r"^CONFIDENCE:\s*"i => ""))
            try
                confidence = parse(Float64, confidence_text)
                current_indication["confidence"] = clamp(confidence, 0.0, 1.0)
            catch
                current_indication["confidence"] = 0.0
            end
        elseif occursin(r"^REASONING:\s*"i, line)
            reasoning = strip(replace(line, r"^REASONING:\s*"i => ""))
            current_indication["reasoning"] = reasoning
        end
    end
    
    # Process the last indication
    if haskey(current_indication, "evidence") && haskey(current_indication, "confidence") && haskey(current_indication, "reasoning")
        indication = create_indication_from_dict(current_indication)
        if indication !== nothing
            push!(indications, indication)
        end
    end
    
    return indications
end

function create_indication_from_dict(indication_dict::Dict)
    """Create NaiveIndication from parsed dictionary"""
    try
        evidence = get(indication_dict, "evidence", false)
        confidence = get(indication_dict, "confidence", 0.0)
        reasoning = get(indication_dict, "reasoning", "")
        
        # Extract condition name
        condition = ""
        
        # Method 1: Use header if available
        if haskey(indication_dict, "header") && !isempty(indication_dict["header"])
            header = indication_dict["header"]
            if !occursin(r"^(Indication|Evidence|Confidence|Reasoning)"i, header)
                condition = strip(header)
            end
        end
        
        # Method 2: Extract from reasoning field
        if isempty(condition) && !isempty(reasoning)
            if contains(reasoning, " - ")
                condition = strip(split(reasoning, " - ")[1])
            elseif contains(reasoning, ": ")
                condition = strip(split(reasoning, ": ")[1])
            else
                # Extract first few words, avoiding drug description patterns
                if !occursin(r"^[A-Za-z]+\s+(has|have|been|is|are|was|were|will|can|may|might|should|could|would)"i, reasoning)
                    words = split(reasoning)
                    if length(words) >= 1
                        condition = join(words[1:min(3, length(words))], " ")
                    end
                end
            end
        end
        
        # Clean up condition name
        condition = strip(condition)
        
        # For cases where condition extraction fails but we have valid data, use a generic description
        if isempty(condition) && confidence > 0.0 && !isempty(reasoning)
            if evidence == false
                # For negative evidence, extract condition from reasoning or use "No therapeutic indication"
                if occursin(r"antidiabetic|diabetes"i, reasoning)
                    condition = "Diabetes/Antidiabetic use"
                elseif occursin(r"withdrawn|discontinued|removed"i, reasoning)
                    condition = "Withdrawn/Discontinued indication"
                else
                    condition = "No established therapeutic indication"
                end
            else
                # For positive evidence, try harder to extract condition
                words = split(reasoning)
                if length(words) >= 1
                    condition = join(words[1:min(2, length(words))], " ")
                end
            end
        end
        
        # Only create indication if we have all required fields
        if !isempty(condition) && confidence > 0.0 && !isempty(reasoning)
            return NaiveIndication(
                condition,
                confidence,
                evidence,
                reasoning,
                string(now())
            )
        end
        
        return nothing
    catch e
        println("Error creating indication: $e")
        return nothing
    end
end

function process_drug_enhanced_naive(drug_name::String)
    """Process a single drug using enhanced naive knowledge-based extraction"""
    
    start_time = time()
    println("\\n🎯 Processing $drug_name using enhanced naive knowledge-based extraction...")
    
    # Load prompt template
    prompt_template = load_prompt_template()
    if prompt_template === nothing
        println("❌ Failed to load prompt template")
        return nothing
    end
    
    # Format the prompt with drug name
    formatted_prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
    
    # Query Llama
    println("🤖 Querying Llama 3.2 for known indications...")
    response = query_llama(formatted_prompt)
    
    if response === nothing
        println("❌ Failed to get response from Llama")
        return nothing
    end
    
    # Parse response
    indications = parse_naive_response(response)
    
    # Count confirmed indications
    confirmed_count = count(ind -> ind.confidence >= CONFIDENCE_THRESHOLD, indications)
    
    # Create enhanced result with raw response
    processing_time = time() - start_time
    result = EnhancedNaiveExtractionResult(
        drug_name,
        length(indications),
        confirmed_count,
        indications,
        processing_time,
        string(now()),
        MODEL_NAME,
        "enhanced_naive_knowledge_based",
        response,           # NEW: Store raw LLM response
        formatted_prompt    # NEW: Store the prompt used
    )
    
    # Print summary
    println("\\n=== ENHANCED NAIVE EXTRACTION COMPLETE ===")
    println("🎯 Drug: $(result.drug_name)")
    println("📋 Total indications found: $(result.total_indications)")
    println("✅ Confirmed indications (≥$(CONFIDENCE_THRESHOLD)): $(result.confirmed_indications)")
    println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2)) seconds")
    println("📄 Raw response length: $(length(result.raw_llm_response)) characters")
    
    # Print indications
    if !isempty(result.indications)
        println("\\n📋 Indications found:")
        for (i, ind) in enumerate(result.indications)
            status = ind.confidence >= CONFIDENCE_THRESHOLD ? "✓" : "○"
            println("   $status $(ind.condition) (confidence: $(ind.confidence))")
            println("     → $(ind.reasoning)")
        end
    end
    
    return result
end

function save_enhanced_results(result::EnhancedNaiveExtractionResult, output_file::String)
    """Save enhanced results to JSON file"""
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
            ) for ind in result.indications],
            "raw_data" => Dict(
                "llm_response" => result.raw_llm_response,
                "prompt_used" => result.prompt_used
            )
        )
        
        # Create output directory if it doesn't exist
        mkpath(dirname(output_file))
        
        # Write results to file
        open(output_file, "w") do file
            JSON3.pretty(file, output_data)
        end
        
        println("\\n✓ Enhanced results saved to: $output_file")
        return true
    catch e
        println("\\n❌ Failed to save enhanced results: $e")
        return false
    end
end

function main()
    """Main function to run the enhanced naive extraction"""
    println("=== Enhanced Naive Llama Drug Indication Extractor ===")
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
    result = process_drug_enhanced_naive(drug_name)
    
    if result !== nothing
        # Define output file
        output_dir = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications"
        output_file = joinpath(output_dir, "$(drug_name)_enhanced_naive_extracted_indications.json")
        
        # Save results
        if save_enhanced_results(result, output_file)
            println("\\n✅ Enhanced naive extraction completed successfully!")
        else
            println("\\n⚠️  Enhanced naive extraction completed but failed to save results")
            exit(1)
        end
    else
        println("\\n❌ Enhanced naive extraction failed")
        exit(1)
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end