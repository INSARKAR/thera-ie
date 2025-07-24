#!/usr/bin/env julia

"""
Dual GPU DrugBank Indication Extractor Coordinator

This script coordinates parallel extraction of drug indications from DrugBank text using two GPUs.
Each GPU runs a separate Ollama server and processes one drug simultaneously.

Usage:
    julia dual_gpu_drugbank_coordinator.jl [drug1] [drug2]

If no drug names are provided, it will process the next unprocessed drugs from approved_drugs_dict.json.
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6

# GPU Server Configuration
const GPU1_HOST = "http://localhost:11434"
const GPU2_HOST = "http://localhost:11435"

# File paths
const APPROVED_DRUGS_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/approved_drugs_dict.json"
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/prompts/llm_prompt_drugbank.txt"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera-ie/llama_drugbank_extracted_indications"

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
    gpu_used::String
end

function test_ollama_connection(host::String, gpu_name::String)
    """Test if Ollama server is accessible on specified host"""
    try
        response = HTTP.get("$(host)/api/tags"; connect_timeout=5, readtimeout=10)
        if response.status == 200
            println("✓ $gpu_name Ollama server accessible at $host")
            return true
        else
            println("❌ $gpu_name Ollama server returned status $(response.status)")
            return false
        end
    catch e
        println("❌ Cannot connect to $gpu_name Ollama at $host: $e")
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

function query_llama_gpu(prompt::String, host::String, gpu_name::String; temperature=0.3, max_tokens=800)
    """Query the Llama model on a specific GPU/host"""
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
            "$(host)/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=10,
            readtimeout=120
        )
        
        result = JSON3.read(String(response.body))
        return get(result, "response", "")
    catch e
        println("❌ [$gpu_name] Llama query failed: $e")
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

function process_drug_dual_gpu(drug_name::String, indication_text::String, prompt_template::String, gpu_host::String, gpu_name::String)
    """Process a single drug's indication text using specified GPU"""
    
    start_time = time()
    
    println("🔍 [$gpu_name] Processing: $drug_name")
    println("📝 [$gpu_name] Indication text length: $(length(indication_text)) characters")
    
    # Create the prompt by substituting variables
    prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name)
    prompt = replace(prompt, "{INDICATION_TEXT}" => indication_text)
    
    println("🤖 [$gpu_name] Querying Llama 3.2...")
    response = query_llama_gpu(prompt, gpu_host, gpu_name)
    
    if response === nothing
        println("❌ [$gpu_name] Failed to get response from Llama for $drug_name")
        return nothing
    end
    
    println("📊 [$gpu_name] Parsing Llama response...")
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
        string(now()),
        gpu_name
    )
    
    println("✅ [$gpu_name] Extracted $(length(indications)) indications ($(confirmed_count) confirmed) for $drug_name in $(round(processing_time, digits=2))s")
    
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
                "approach" => "drugbank_text_extraction",
                "gpu_used" => String(result.gpu_used)
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
        println("❌ Failed to save results for $(result.drug_name): $e")
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

function get_next_unprocessed_drugs(drugs_data, count::Int=2)
    """Get the next unprocessed drugs from the dataset"""
    unprocessed = String[]
    
    for (drug_name, _) in drugs_data
        drug_name_str = string(drug_name)
        output_file = joinpath(OUTPUT_DIR, "$(drug_name_str)_drugbank_extracted_indications.json")
        
        if !isfile(output_file)
            push!(unprocessed, drug_name_str)
            if length(unprocessed) >= count
                break
            end
        end
    end
    
    return unprocessed
end

function main()
    """Main function to run dual GPU DrugBank extraction"""
    println("=== Dual GPU DrugBank Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    
    # Load approved drugs data
    drugs_data = load_approved_drugs()
    if drugs_data === nothing
        exit(1)
    end
    
    # Get drug names from command line arguments or find next unprocessed
    drug1 = ""
    drug2 = ""
    
    if length(ARGS) >= 2
        drug1 = ARGS[1]
        drug2 = ARGS[2]
    else
        # Find next unprocessed drugs
        unprocessed = get_next_unprocessed_drugs(drugs_data, 2)
        if length(unprocessed) >= 1
            drug1 = unprocessed[1]
        end
        if length(unprocessed) >= 2
            drug2 = unprocessed[2]
        end
    end
    
    if isempty(drug1) && isempty(drug2)
        println("✅ All drugs have been processed!")
        exit(0)
    end
    
    println("Drug 1 (GPU 0): $(isempty(drug1) ? "None" : drug1)")
    println("Drug 2 (GPU 1): $(isempty(drug2) ? "None" : drug2)")
    println("")
    
    # Test both Ollama connections
    println("=== Testing Ollama Connections ===")
    if !test_ollama_connection(GPU1_HOST, "GPU 0")
        println("❌ Exiting due to GPU 0 Ollama connection failure")
        exit(1)
    end
    
    if !test_ollama_connection(GPU2_HOST, "GPU 1")
        println("❌ Exiting due to GPU 1 Ollama connection failure")
        exit(1)
    end
    
    println("✓ Both Ollama servers are accessible")
    println("")
    
    # Load prompt template
    prompt_template = load_drugbank_prompt()
    if prompt_template === nothing
        exit(1)
    end
    
    # Start parallel processing
    println("=== Starting Parallel Drug Processing ===")
    
    # Prepare tasks
    tasks = Task[]
    
    if !isempty(drug1) && haskey(drugs_data, drug1)
        indication_text1 = drugs_data[drug1]
        task1 = @async process_drug_dual_gpu(drug1, indication_text1, prompt_template, GPU1_HOST, "GPU 0")
        push!(tasks, task1)
    elseif !isempty(drug1)
        println("⚠️ Drug '$drug1' not found in approved drugs dictionary")
    end
    
    if !isempty(drug2) && haskey(drugs_data, drug2)
        indication_text2 = drugs_data[drug2]
        task2 = @async process_drug_dual_gpu(drug2, indication_text2, prompt_template, GPU2_HOST, "GPU 1")
        push!(tasks, task2)
    elseif !isempty(drug2)
        println("⚠️ Drug '$drug2' not found in approved drugs dictionary")
    end
    
    # Wait for all tasks to complete
    results = []
    for task in tasks
        result = fetch(task)
        if result !== nothing
            push!(results, result)
        end
    end
    
    # Save results
    saved_count = 0
    for result in results
        if save_drug_result(result)
            saved_count += 1
        end
    end
    
    # Print final summary
    println("\n=== DUAL GPU EXTRACTION COMPLETE ===")
    
    if !isempty(drug1)
        result1 = findfirst(r -> r.drug_name == drug1, results)
        if result1 !== nothing
            r = results[result1]
            println("✅ $drug1 (GPU 0): $(r.total_indications) indications extracted in $(round(r.processing_time_seconds, digits=2))s")
        else
            println("❌ $drug1 (GPU 0): Processing failed")
        end
    end
    
    if !isempty(drug2)
        result2 = findfirst(r -> r.drug_name == drug2, results)
        if result2 !== nothing
            r = results[result2]
            println("✅ $drug2 (GPU 1): $(r.total_indications) indications extracted in $(round(r.processing_time_seconds, digits=2))s")
        else
            println("❌ $drug2 (GPU 1): Processing failed")
        end
    end
    
    # Determine exit code
    if saved_count == length(tasks) && length(tasks) > 0
        println("\n✅ All extractions completed successfully!")
        exit(0)
    elseif saved_count > 0
        println("\n⚠️  Partial success - $(saved_count)/$(length(tasks)) extractions completed")
        exit(1)
    else
        println("\n❌ All extractions failed")
        exit(1)
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end