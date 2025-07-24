#!/usr/bin/env julia

"""
DrugBank Indication Extractor using Llama 3.2

This script extracts therapeutic indications from DrugBank indication text fields
using the Llama 3.2 model. It processes the approved_drugs_dict.json file and
extracts individual indications from the indication text for each drug.

Usage:
    julia drugbank_llama_extractor.jl [drug_name]
    
If no drug name is provided, processes all drugs in the approved_drugs_dict.json file.
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const OLLAMA_HOST = get(ENV, "OLLAMA_HOST", "http://localhost:11434")

# File paths
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/approved_drugs_dict.json"
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/prompts/llm_prompt_drugbank.txt"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera-ie/phase1_llama_drugbank_extracted_indications"

# Data structures
struct Indication
    condition::String
    confidence::Float64
    reasoning::String
    confirmed::Bool
    extracted_at::String
end

struct DrugBankExtractionResult
    drug_name::String
    original_indication_text::String
    extracted_indications::Vector{Indication}
    total_indications::Int
    confirmed_indications::Int
    processing_time_seconds::Float64
    extracted_at::String
end

function test_ollama_connection()
    """Test if Ollama server is accessible"""
    try
        response = HTTP.get("$(OLLAMA_HOST)/api/tags"; connect_timeout=5, readtimeout=10)
        if response.status == 200
            println("✓ Ollama server accessible at $OLLAMA_HOST")
            return true
        else
            println("❌ Ollama server returned status $(response.status)")
            return false
        end
    catch e
        println("❌ Cannot connect to Ollama: $e")
        println("Please ensure Ollama is running and accessible")
        return false
    end
end

function load_drugbank_prompt()
    """Load the DrugBank indication extraction prompt template"""
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
            elseif in_template && !contains(line, "=======")
                push!(template_lines, line)
            end
        end
        
        # Find the actual prompt text (skip header lines)
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

function query_llama(prompt::String; temperature=0.3, max_tokens=800)
    """Query the Llama model with the given prompt"""
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
            "$(OLLAMA_HOST)/api/generate",
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

function parse_llama_response(response::String)
    """Parse the Llama response to extract indications"""
    indications = Indication[]
    
    # Split response by "Indication" markers
    sections = split(response, r"Indication\s+\d+:")
    
    # Skip first section (usually empty or contains preamble)
    for section in sections[2:end]
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
        
        if evidence && !isempty(reasoning)
            # Extract condition name from reasoning (before the dash)
            condition_parts = split(reasoning, " - ", limit=2)
            condition = strip(condition_parts[1])
            
            indication = Indication(
                condition,
                confidence,
                reasoning,
                confidence >= CONFIDENCE_THRESHOLD,
                string(now())
            )
            push!(indications, indication)
        end
    end
    
    return indications
end

function process_drug_indication(drug_name::String, indication_text::String, prompt_template::String)
    """Process a single drug's indication text using Llama"""
    
    start_time = time()
    
    println("🔍 Processing: $drug_name")
    println("📝 Indication text length: $(length(indication_text)) characters")
    
    # Create the prompt by substituting variables
    prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name)
    prompt = replace(prompt, "{INDICATION_TEXT}" => indication_text)
    
    println("🤖 Querying Llama 3.2...")
    response = query_llama(prompt)
    
    if response === nothing
        println("❌ Failed to get response from Llama")
        return nothing
    end
    
    println("📊 Parsing Llama response...")
    indications = parse_llama_response(response)
    
    processing_time = time() - start_time
    confirmed_count = count(ind -> ind.confirmed, indications)
    
    result = DrugBankExtractionResult(
        drug_name,
        indication_text,
        indications,
        length(indications),
        confirmed_count,
        processing_time,
        string(now())
    )
    
    println("✅ Extracted $(length(indications)) indications ($(confirmed_count) confirmed) in $(round(processing_time, digits=2))s")
    
    return result
end

function save_drug_result(result::DrugBankExtractionResult)
    """Save extraction results to JSON file"""
    
    output_file = joinpath(OUTPUT_DIR, "$(result.drug_name)_drugbank_extracted_indications.json")
    
    try
        # Convert to dictionary for JSON serialization
        output_data = Dict(
            "metadata" => Dict(
                "drug_name" => String(result.drug_name),
                "original_indication_text" => String(result.original_indication_text),
                "total_indications" => Int(result.total_indications),
                "confirmed_indications" => Int(result.confirmed_indications),
                "processing_time_seconds" => Float64(result.processing_time_seconds),
                "extracted_at" => String(result.extracted_at),
                "model_used" => String(MODEL_NAME),
                "approach" => "drugbank_text_extraction"
            ),
            "indications" => [Dict(
                "condition" => String(ind.condition),
                "confidence" => Float64(ind.confidence),
                "reasoning" => String(ind.reasoning),
                "confirmed" => Bool(ind.confirmed),
                "extracted_at" => String(ind.extracted_at)
            ) for ind in result.extracted_indications]
        )
        
        # Create output directory if it doesn't exist
        mkpath(OUTPUT_DIR)
        
        # Write results to file with pretty formatting
        open(output_file, "w") do file
            JSON3.pretty(file, output_data)
        end
        
        println("✓ Results saved to: $output_file")
        return true
    catch e
        println("❌ Failed to save results: $e")
        return false
    end
end

function load_approved_drugs()
    """Load the approved drugs dictionary"""
    try
        data = JSON3.read(read(APPROVED_DRUGS_FILE, String))
        return data.drugs
    catch e
        println("❌ Failed to load approved drugs file: $e")
        return nothing
    end
end

function process_single_drug(drug_name::String)
    """Process a single drug by name"""
    
    println("=== DrugBank Indication Extractor ===")
    println("Drug: $drug_name")
    println("Start time: $(now())")
    println("")
    
    # Load approved drugs data
    drugs_data = load_approved_drugs()
    if drugs_data === nothing
        exit(1)
    end
    
    # Find the drug
    if !haskey(drugs_data, drug_name)
        println("❌ Drug '$drug_name' not found in approved drugs dictionary")
        available_drugs = sort(collect(keys(drugs_data)))
        println("Available drugs (first 10): $(join(available_drugs[1:min(10, length(available_drugs))], ", "))")
        exit(1)
    end
    
    indication_text = drugs_data[drug_name]
    
    # Test Ollama connection
    if !test_ollama_connection()
        exit(1)
    end
    
    # Load prompt template
    prompt_template = load_drugbank_prompt()
    if prompt_template === nothing
        exit(1)
    end
    
    # Process the drug
    result = process_drug_indication(drug_name, indication_text, prompt_template)
    if result === nothing
        exit(1)
    end
    
    # Save results
    if !save_drug_result(result)
        exit(1)
    end
    
    println("")
    println("=== EXTRACTION COMPLETE ===")
    println("✅ Successfully processed $drug_name")
    exit(0)
end

function process_all_drugs()
    """Process all drugs in the approved drugs dictionary"""
    
    println("=== DrugBank Indication Extractor - All Drugs ===")
    println("Start time: $(now())")
    println("")
    
    # Load approved drugs data
    drugs_data = load_approved_drugs()
    if drugs_data === nothing
        exit(1)
    end
    
    total_drugs = length(drugs_data)
    println("📊 Found $total_drugs drugs in approved drugs dictionary")
    
    # Test Ollama connection
    if !test_ollama_connection()
        exit(1)
    end
    
    # Load prompt template
    prompt_template = load_drugbank_prompt()
    if prompt_template === nothing
        exit(1)
    end
    
    # Process each drug
    processed_count = 0
    failed_count = 0
    
    for (i, (drug_name, indication_text)) in enumerate(drugs_data)
        println("")
        println("=== Processing $i/$total_drugs ===")
        
        # Check if already processed (convert Symbol to String if needed)
        drug_name_str = string(drug_name)
        output_file = joinpath(OUTPUT_DIR, "$(drug_name_str)_drugbank_extracted_indications.json")
        if isfile(output_file)
            println("⏭️  Skipping $drug_name (already processed)")
            processed_count += 1
            continue
        end
        
        # Process the drug (convert Symbol to String if needed)
        drug_name_str = string(drug_name)
        result = process_drug_indication(drug_name_str, indication_text, prompt_template)
        if result === nothing
            failed_count += 1
            continue
        end
        
        # Save results
        if save_drug_result(result)
            processed_count += 1
        else
            failed_count += 1
        end
        
        # Small delay to avoid overwhelming the API
        sleep(1)
    end
    
    println("")
    println("=== ALL DRUGS PROCESSING COMPLETE ===")
    println("✅ Successfully processed: $processed_count drugs")
    println("❌ Failed: $failed_count drugs")
    println("📊 Total: $total_drugs drugs")
    println("End time: $(now())")
end

function main()
    """Main function to run the DrugBank indication extractor"""
    
    if length(ARGS) > 0
        drug_name = ARGS[1]
        process_single_drug(drug_name)
    else
        process_all_drugs()
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end