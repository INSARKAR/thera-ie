#!/usr/bin/env julia

"""
Llama 3.2 Drug-Indication Pairing Extractor

This program analyzes drug files in the drug_pubmed_refs directory using Llama 3.2
to identify drug-indication pairings from publication data.

Usage: julia llama_drug_indication_extractor.jl [options]

Dependencies:
- HTTP.jl for API calls
- JSON3.jl for JSON parsing
- CSV.jl for output generation (optional)
"""

using HTTP
using JSON3
using Dates
using Logging

# Configuration
const DRUG_FILES_DIR = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs"
const OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
const LLAMA_API_URL = "http://localhost:11434/api/generate"  # Default Ollama URL
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
    gpu_node = get(ENV, "LLAMA_GPU_NODE", nothing)
    
    try
        if gpu_node !== nothing
            @debug "Checking Ollama on GPU node: $gpu_node"
            # For HPC environment, check via SSH
            result = read(`ssh $gpu_node curl -s http://localhost:11434/api/tags --connect-timeout 5`, String)
            return true
        else
            # Direct check for local environment
            HTTP.get("http://localhost:11434/api/tags", connect_timeout=5)
            return true
        end
    catch e
        @warn "Ollama API check failed: $e"
        return false
    end
end

"""
Query Llama 3.2 API with a prompt
"""
function query_llama(prompt::String; max_retries=3)
    # Check if we need to use SSH for HPC environment
    gpu_node = get(ENV, "LLAMA_GPU_NODE", nothing)
    use_ssh = gpu_node !== nothing
    
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
            if use_ssh
                # For HPC environment with SSH to GPU node
                @debug "Using SSH connection to GPU node: $gpu_node"
                
                # Create a temporary file with the JSON payload
                temp_file = tempname() * ".json"
                write(temp_file, JSON3.write(payload))
                
                # Use SSH to send the request
                cmd = `ssh $gpu_node curl -X POST http://localhost:11434/api/generate -H "Content-Type: application/json" -d @$temp_file --connect-timeout 30 --max-time 120`
                
                result_json = read(cmd, String)
                rm(temp_file)  # Clean up temp file
                
                result = JSON3.read(result_json)
                return result.response
                
            else
                # Direct API call for local environment
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
    
    if haskey(publication_data, "mesh_descriptors") && publication_data["mesh_descriptors"] isa Vector
        for descriptor in publication_data["mesh_descriptors"]
            if haskey(descriptor, "descriptor")
                push!(mesh_terms, descriptor["descriptor"])
            end
        end
    end
    
    return mesh_terms
end

"""
Process a single publication to extract drug-indication pairings
"""
function process_publication(drug_name::String, publication::Dict)
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
end

"""
Process a single drug file
"""
function process_drug_file(filepath::String)
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
        
        # Process each publication
        for (i, publication) in enumerate(publications)
            @info "Processing publication $i/$(length(publications))"
            
            try
                extracted_pairs = process_publication(drug_name, publication)
                append!(all_indications, extracted_pairs)
                successful_extractions += 1
                
                # Add small delay to avoid overwhelming the API
                sleep(1)
                
            catch e
                @warn "Failed to process publication: $e"
                failed_extractions += 1
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
    output_file = joinpath(OUTPUT_DIR, "$(result.drug_name)_llama_extracted.json")
    
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
            "total_indications_extracted" => length(result.indications)
        ),
        "extracted_indications" => [
            Dict(
                "indication" => pair.indication,
                "confidence" => pair.confidence,
                "pmid" => pair.pmid,
                "title" => pair.title,
                "source_text" => pair.source_text,
                "extracted_at" => string(pair.extracted_at)
            )
            for pair in result.indications
        ]
    )
    
    write(output_file, JSON3.write(result_dict, allow_inf=true))
    @info "Results saved to: $output_file"
end

"""
Generate summary report of all extractions
"""
function generate_summary_report(results::Vector{DrugAnalysisResult})
    summary_file = joinpath(OUTPUT_DIR, "extraction_summary.json")
    
    total_drugs = length(results)
    total_publications = sum(r.total_publications for r in results)
    total_indications = sum(length(r.indications) for r in results)
    total_processing_time = sum(r.processing_duration for r in results)
    
    # Find most common indications
    indication_counts = Dict{String, Int}()
    for result in results
        for pair in result.indications
            indication_counts[pair.indication] = get(indication_counts, pair.indication, 0) + 1
        end
    end
    
    top_indications = sort(collect(indication_counts), by=x->x[2], rev=true)[1:min(20, length(indication_counts))]
    
    summary = Dict(
        "analysis_summary" => Dict(
            "total_drugs_analyzed" => total_drugs,
            "total_publications_processed" => total_publications,
            "total_indications_extracted" => total_indications,
            "total_processing_time_seconds" => total_processing_time,
            "average_indications_per_drug" => round(total_indications / total_drugs, digits=2),
            "analysis_completed_at" => string(now()),
            "model_used" => MODEL_NAME
        ),
        "drug_results" => [
            Dict(
                "drug_name" => r.drug_name,
                "publications_count" => r.total_publications,
                "indications_extracted" => length(r.indications),
                "processing_time_seconds" => r.processing_duration
            )
            for r in results
        ],
        "top_indications" => [
            Dict("indication" => indication, "frequency" => count)
            for (indication, count) in top_indications
        ]
    )
    
    write(summary_file, JSON3.write(summary, allow_inf=true))
    @info "Summary report saved to: $summary_file"
end

"""
Main execution function
"""
function main()
    @info "Starting Llama 3.2 Drug-Indication Extraction Analysis"
    @info "Input directory: $DRUG_FILES_DIR"
    @info "Output directory: $OUTPUT_DIR"
    @info "Model: $MODEL_NAME"
    
    # Check for test mode or single drug mode
    test_mode = haskey(ENV, "LLAMA_TEST_MODE") && ENV["LLAMA_TEST_MODE"] == "true"
    single_drug_env = get(ENV, "LLAMA_SINGLE_DRUG", "")
    single_drug = isempty(single_drug_env) ? nothing : single_drug_env
    max_files = test_mode ? parse(Int, get(ENV, "LLAMA_MAX_FILES", "5")) : 0
    
    if test_mode
        @info "Running in TEST MODE - processing first $max_files files"
    elseif single_drug !== nothing
        @info "Running SINGLE DRUG analysis for: $single_drug"
    end
    
    # Initial Ollama availability check will be done before each drug file processing
    @info "Note: GPU/Ollama availability will be checked before processing each drug file"
    
    # Find all JSON files in the drug directory
    if !isdir(DRUG_FILES_DIR)
        @error "Drug files directory not found: $DRUG_FILES_DIR"
        return
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
            return
        end
    elseif test_mode && max_files > 0
        # Test mode - take first N files
        all_json_files[1:min(max_files, length(all_json_files))]
    else
        # Full mode
        all_json_files
    end
    
    @info "Found $(length(all_json_files)) total drug files, processing $(length(json_files)) files"
    
    if isempty(json_files)
        @warn "No JSON files found to process"
        return
    end
    
    # Process each drug file
    results = DrugAnalysisResult[]
    
    for (i, filename) in enumerate(json_files)
        filepath = joinpath(DRUG_FILES_DIR, filename)
        @info "Processing file $i/$(length(json_files)): $filename"
        
        # Check Ollama availability before processing each drug file
        if !check_ollama_availability()
            @error "Ollama/GPU not available before processing $filename. Stopping execution."
            
            # Write checkpoint for resume (only if processing multiple files)
            if length(json_files) > 1
                checkpoint_data = Dict(
                    "last_processed_index" => i - 1,
                    "last_processed_file" => i > 1 ? json_files[i-1] : "",
                    "total_processed" => length(results),
                    "remaining_files" => json_files[i:end],
                    "timestamp" => string(now())
                )
                checkpoint_path = joinpath(OUTPUT_DIR, "processing_checkpoint.json")
                open(checkpoint_path, "w") do f
                    JSON3.write(f, checkpoint_data)
                end
                @info "Checkpoint saved to $checkpoint_path"
            end
            
            break
        end
        
        result = process_drug_file(filepath)
        if result !== nothing
            push!(results, result)
            save_results(result)
        end
        
        # Add delay between files to be respectful to the API
        if i < length(json_files)
            @info "Waiting before processing next file..."
            sleep(2)
        end
    end
    
    # Generate summary report
    if !isempty(results)
        generate_summary_report(results)
        @info "Analysis complete! Processed $(length(results)) drugs successfully."
        @info "Total indications extracted: $(sum(length(r.indications) for r in results))"
    else
        @warn "No files were processed successfully"
    end
end

# Run the program if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
