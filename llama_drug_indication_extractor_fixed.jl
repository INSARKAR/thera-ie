#!/usr/bin/env julia

"""
Fixed Llama 3.2 Drug-Indication Pairing Extractor

This is a robust version that fixes the MethodError issue in the original extractor.
"""

using HTTP
using JSON3
using Dates
using Logging

# Configuration
const DRUG_FILES_DIR = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs"
const OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
const LLAMA_API_URL = "http://localhost:11434/api/generate"
const MODEL_NAME = "llama3.2"

# Create output directory if it doesn't exist
if !isdir(OUTPUT_DIR)
    mkpath(OUTPUT_DIR)
end

# Configure logging
logger = ConsoleLogger(stdout, Logging.Info)
global_logger(logger)

"""
Structure to hold drug-indication extraction results
"""
struct DrugIndicationPair
    drug_name::String
    indication::String
    confidence::Float64
    pmid::String
    title::String
    source_text::String
    extracted_at::DateTime
end

"""
Structure to hold analysis results for a drug
"""
struct DrugAnalysisResult
    drug_name::String
    total_publications::Int
    successful_extractions::Int
    failed_extractions::Int
    indications::Vector{DrugIndicationPair}
    analysis_time::DateTime
    processing_duration::Float64
end

"""
Create a prompt for Llama 3.2 to extract drug-indication pairings
"""
function create_extraction_prompt(drug_name::String, title::String, abstract::String, mesh_terms::Vector{String})
    mesh_str = isempty(mesh_terms) ? "None provided" : join(mesh_terms, ", ")
    
    prompt = """
You are a medical expert tasked with extracting drug-indication pairings from scientific literature.

DRUG: $drug_name

PUBLICATION TITLE: $title

ABSTRACT: $abstract

MESH TERMS: $mesh_str

TASK: Analyze the above publication and extract specific medical conditions, diseases, or therapeutic indications that the drug "$drug_name" is used to treat, prevent, or manage based on the content.

INSTRUCTIONS:
1. Only extract indications that are clearly stated or strongly implied in the text
2. Focus on therapeutic uses, not side effects or contraindications
3. Use standard medical terminology when possible
4. If the publication mentions the drug but doesn't indicate a therapeutic use, respond with "NO_INDICATION"
5. Rate your confidence (0.0-1.0) in each extraction

FORMAT YOUR RESPONSE EXACTLY AS:
INDICATION: [condition/disease name]
CONFIDENCE: [0.0-1.0]

If multiple indications are found, list each separately with the same format.
If no therapeutic indication is found, respond with:
NO_INDICATION
CONFIDENCE: 1.0
"""
    return prompt
end

"""
Parse Llama response to extract indication pairs
"""
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
                return pairs  # Return empty if no indication found
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
                    current_confidence = 0.0
                end
            catch e
                @warn "Failed to parse confidence: $confidence_text"
            end
        end
    end
    
    return pairs
end

"""
Check if Ollama/GPU server is available
"""
function check_ollama_availability()
    try
        HTTP.get("http://localhost:11434/api/tags", connect_timeout=5)
        return true
    catch e
        @warn "Ollama API check failed: $e"
        return false
    end
end

"""
Query Llama 3.2 API with a prompt
"""
function query_llama(prompt::String; max_retries=3)
    payload = Dict(
        "model" => MODEL_NAME,
        "prompt" => prompt,
        "stream" => false,
        "options" => Dict(
            "temperature" => 0.1,
            "top_p" => 0.9,
            "max_tokens" => 1000
        )
    )
    
    for attempt in 1:max_retries
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
                @warn "API request failed with status $(response.status), attempt $attempt"
            end
            
        catch e
            @warn "Error querying Llama API (attempt $attempt): $e"
            if attempt < max_retries
                sleep(2^attempt)  # Exponential backoff
            end
        end
    end
    
    return nothing
end

"""
Extract mesh descriptors from publication data
"""
function extract_mesh_terms(publication_data::Dict)
    mesh_terms = String[]
    
    try
        if haskey(publication_data, "mesh_descriptors") && publication_data["mesh_descriptors"] isa Vector
            for descriptor in publication_data["mesh_descriptors"]
                if isa(descriptor, Dict) && haskey(descriptor, "descriptor")
                    push!(mesh_terms, descriptor["descriptor"])
                end
            end
        end
    catch e
        @debug "Error extracting mesh terms: $e"
    end
    
    return mesh_terms
end

"""
Process a single publication to extract drug-indication pairings
"""
function process_publication_safe(drug_name::String, publication::Dict)
    try
        pmid = get(publication, "pmid", "unknown")
        title = get(publication, "title", "")
        abstract = get(publication, "abstract", "")
        
        # Skip if no meaningful content
        if isempty(title) && isempty(abstract)
            @debug "Skipping publication $pmid - no title or abstract"
            return DrugIndicationPair[]
        end
        
        mesh_terms = extract_mesh_terms(publication)
        source_text = "Title: $title\nAbstract: $abstract"
        
        # Create prompt for Llama
        prompt = create_extraction_prompt(drug_name, title, abstract, mesh_terms)
        
        # Query Llama
        @info "Processing publication $pmid for drug $drug_name"
        response = query_llama(prompt)
        
        if response === nothing
            @warn "Failed to get response from Llama for publication $pmid"
            return DrugIndicationPair[]
        end
        
        # Parse response
        pairs = parse_llama_response(response, drug_name, pmid, title, source_text)
        
        @info "Extracted $(length(pairs)) indication(s) from publication $pmid"
        for pair in pairs
            @info "  - $(pair.indication) (confidence: $(pair.confidence))"
        end
        
        return pairs
        
    catch e
        @error "Error in process_publication_safe for publication: $e"
        @debug "Publication data: $publication"
        return DrugIndicationPair[]
    end
end

"""
Process a single drug file with improved error handling
"""
function process_drug_file_safe(filepath::String)
    @info "Processing drug file: $filepath"
    start_time = time()
    
    try
        # Read and parse the drug file
        file_content = read(filepath, String)
        drug_data = JSON3.read(file_content)
        
        drug_name = get(drug_data.metadata, "drug_name", "unknown")
        publications = get(drug_data.result, "publications_analyzed", [])
        
        @info "Found $(length(publications)) publications for drug $drug_name"
        
        all_indications = DrugIndicationPair[]
        successful_extractions = 0
        failed_extractions = 0
        
        # Process each publication with better error handling
        for (i, publication) in enumerate(publications)
            @info "Processing publication $i/$(length(publications))"
            
            try
                # Ensure publication is a Dict
                if !(publication isa Dict)
                    @warn "Publication $i is not a Dict, skipping"
                    failed_extractions += 1
                    continue
                end
                
                extracted_pairs = process_publication_safe(drug_name, publication)
                append!(all_indications, extracted_pairs)
                successful_extractions += 1
                
                # Add small delay to avoid overwhelming the API
                sleep(1)
                
            catch e
                @warn "Failed to process publication $i: $e"
                failed_extractions += 1
                
                # If we're getting consistent errors, maybe stop early
                if failed_extractions > 10 && successful_extractions == 0
                    @error "Too many consecutive failures, stopping processing"
                    break
                end
            end
        end
        
        processing_duration = time() - start_time
        
        result = DrugAnalysisResult(
            drug_name,
            length(publications),
            successful_extractions,
            failed_extractions,
            all_indications,
            now(),
            processing_duration
        )
        
        @info "Completed analysis for $drug_name: $(length(all_indications)) total indications extracted"
        @info "Success rate: $(successful_extractions)/$(length(publications)) = $(round(100 * successful_extractions / length(publications), digits=1))%"
        
        return result
        
    catch e
        @error "Error processing drug file $filepath: $e"
        return nothing
    end
end

"""
Save results to JSON file
"""
function save_results(result::DrugAnalysisResult)
    output_file = joinpath(OUTPUT_DIR, "$(result.drug_name)_llama_extracted_fixed.json")
    
    # Convert to serializable format
    result_dict = Dict(
        "metadata" => Dict(
            "drug_name" => result.drug_name,
            "analysis_time" => string(result.analysis_time),
            "processing_duration_seconds" => result.processing_duration,
            "model_used" => MODEL_NAME,
            "total_publications" => result.total_publications,
            "successful_extractions" => result.successful_extractions,
            "failed_extractions" => result.failed_extractions,
            "total_indications_extracted" => length(result.indications),
            "success_rate_percent" => round(100 * result.successful_extractions / result.total_publications, digits=2)
        ),
        "extracted_indications" => [
            Dict(
                "indication" => pair.indication,
                "confidence" => pair.confidence,
                "pmid" => pair.pmid,
                "title" => pair.title,
                "source_text" => pair.source_text[1:min(500, length(pair.source_text))] * (length(pair.source_text) > 500 ? "..." : ""),
                "extracted_at" => string(pair.extracted_at)
            )
            for pair in result.indications
        ]
    )
    
    write(output_file, JSON3.write(result_dict, allow_inf=true))
    @info "Results saved to: $output_file"
end

"""
Main execution function
"""
function main()
    @info "Starting Fixed Llama 3.2 Drug-Indication Extraction Analysis"
    @info "Input directory: $DRUG_FILES_DIR"
    @info "Output directory: $OUTPUT_DIR"
    @info "Model: $MODEL_NAME"
    @info "Node: $(gethostname())"
    
    # Check for single drug mode
    single_drug_env = get(ENV, "LLAMA_SINGLE_DRUG", "")
    single_drug = isempty(single_drug_env) ? nothing : single_drug_env
    
    if single_drug !== nothing
        @info "Running SINGLE DRUG analysis for: $single_drug"
    end
    
    # Check Ollama availability
    @info "Checking Ollama availability..."
    if !check_ollama_availability()
        @error "Ollama/GPU not available. Please ensure:"
        @error "1. Ollama server is running (ollama serve &)"
        @error "2. Llama 3.2 model is loaded (ollama run llama3.2)"
        return false
    end
    @info "✓ Ollama is available"
    
    # Find all JSON files in the drug directory
    if !isdir(DRUG_FILES_DIR)
        @error "Drug files directory not found: $DRUG_FILES_DIR"
        return false
    end
    
    all_json_files = [f for f in readdir(DRUG_FILES_DIR) if endswith(f, ".json")]
    
    # Filter files based on mode
    json_files = if single_drug !== nothing
        # Single drug mode
        single_file = "$single_drug.json"
        if single_file in all_json_files
            [single_file]
        else
            @error "Drug file not found: $single_file"
            @info "Available files: $(all_json_files[1:min(10, length(all_json_files))])"
            return false
        end
    else
        # Full mode - limit to first 5 for debugging
        @warn "Running all drugs - limiting to first 5 for testing"
        all_json_files[1:min(5, length(all_json_files))]
    end
    
    @info "Found $(length(all_json_files)) total drug files, processing $(length(json_files)) files"
    
    if isempty(json_files)
        @warn "No JSON files found to process"
        return false
    end
    
    # Process each drug file
    results = DrugAnalysisResult[]
    
    for (i, filename) in enumerate(json_files)
        filepath = joinpath(DRUG_FILES_DIR, filename)
        @info "Processing file $i/$(length(json_files)): $filename"
        
        result = process_drug_file_safe(filepath)
        if result !== nothing
            push!(results, result)
            save_results(result)
        end
        
        # Add delay between files to be respectful to the API
        if i < length(json_files)
            @info "Waiting before processing next file..."
            sleep(3)
        end
    end
    
    # Summary
    if !isempty(results)
        @info "Analysis complete! Processed $(length(results)) drugs successfully."
        total_indications = sum(length(r.indications) for r in results)
        total_publications = sum(r.total_publications for r in results)
        total_successful = sum(r.successful_extractions for r in results)
        
        @info "Total indications extracted: $total_indications"
        @info "Overall success rate: $(total_successful)/$total_publications = $(round(100 * total_successful / total_publications, digits=1))%"
        
        # Show per-drug summary
        for result in results
            @info "$(result.drug_name): $(length(result.indications)) indications from $(result.successful_extractions)/$(result.total_publications) publications"
        end
        
        return true
    else
        @warn "No files were processed successfully"
        return false
    end
end

# Run the program if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    success = main()
    exit(success ? 0 : 1)
end
