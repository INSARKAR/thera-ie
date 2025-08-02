#!/usr/bin/env julia

"""
THERA-IE Phase 2 Step 3: Top 10 PubMed Evidence-Based SNOMED Indication Extractor

This script processes the top 10 US prescribed drugs using Llama 3.2 analysis of PubMed abstracts
to extract drug indications with direct SNOMED CT terminology output. Uses intelligent sampling
of 5 articles per MeSH descriptor for efficient and comprehensive coverage.

Key Features:
- Samples 5 publications per unique MeSH descriptor for balanced coverage
- Outputs standardized SNOMED CT codes and terms directly
- Research categorization prompt to avoid LLM safety restrictions
- Enhanced parsing logic with PMID linking
- Comprehensive retry logic with exponential backoff
- Resume capability for fault tolerance

Usage:
    julia phase2_step3_top10_pubmed_extractor.jl

Author: THERA-IE System
Date: 2025-08-02
Version: 1.0 (Top 10 PubMed Evidence-Based SNOMED CT Extraction)
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const MAX_PUBLICATIONS_PER_MESH = 5
const PROMPT_FILE = "prompts/llm_prompt_pubmed_snomed_top10.txt"
const OUTPUT_DIR = "phase2_step3_pubmed_snomed"
const INPUT_DIR = "phase1_step2_pubmed_extraction"
const TOP10_FILE = "top_10_drugs_us.txt"

# Data structures for SNOMED CT output
struct SnomedPubMedIndication
    snomed_code::String
    snomed_term::String
    confidence::Float64
    evidence::Bool
    supporting_pmids::Vector{String}
    reasoning::String
    extracted_at::String
end

struct SnomedPubMedExtractionResult
    drug_name::String
    total_abstracts_analyzed::Int
    mesh_descriptors_sampled::Int
    total_indications::Int
    confirmed_indications::Int
    snomed_indications::Vector{SnomedPubMedIndication}
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

function load_pubmed_snomed_prompt_template()
    """Load the SNOMED CT PubMed prompt template from file"""
    try
        if !isfile(PROMPT_FILE)
            println("❌ Prompt file not found: $PROMPT_FILE")
            return nothing
        end
        
        prompt_content = read(PROMPT_FILE, String)
        println("✓ Loaded prompt template ($(length(prompt_content)) characters)")
        return prompt_content
    catch e
        println("❌ Failed to load SNOMED CT PubMed prompt template: $e")
        return nothing
    end
end

function sample_publications_by_mesh(phase1_data)
    """Sample up to 5 publications per unique MeSH descriptor"""
    
    # Group publications by MeSH descriptors
    mesh_groups = Dict{String, Vector{Any}}()
    
    if haskey(phase1_data, :result) && haskey(phase1_data.result, :publications)
        for pub in phase1_data.result.publications
            if haskey(pub, :abstract) && !isempty(strip(get(pub, :abstract, "")))
                # Get MeSH descriptors for this publication
                if haskey(pub, :mesh_descriptors)
                    for mesh in pub.mesh_descriptors
                        mesh_name = get(mesh, :name, "")
                        if !isempty(mesh_name)
                            if !haskey(mesh_groups, mesh_name)
                                mesh_groups[mesh_name] = Any[]
                            end
                            push!(mesh_groups[mesh_name], pub)
                        end
                    end
                end
            end
        end
    end
    
    # Sample up to MAX_PUBLICATIONS_PER_MESH from each group
    sampled_abstracts = String[]
    sampled_pmids = String[]
    mesh_count = 0
    
    for (mesh_name, pubs) in mesh_groups
        mesh_count += 1
        # Take up to MAX_PUBLICATIONS_PER_MESH publications from this MeSH group
        selected_pubs = pubs[1:min(length(pubs), MAX_PUBLICATIONS_PER_MESH)]
        
        for pub in selected_pubs
            abstract = strip(get(pub, :abstract, ""))
            pmid = get(pub, :pmid, "")
            
            if !isempty(abstract) && !isempty(pmid)
                # Format: "PMID: [pmid] Abstract: [abstract]"
                formatted_abstract = "PMID: $pmid\nAbstract: $abstract"
                push!(sampled_abstracts, formatted_abstract)
                push!(sampled_pmids, pmid)
            end
        end
    end
    
    return sampled_abstracts, sampled_pmids, mesh_count
end

function query_llama(prompt::String, ollama_host::String; temperature=0.3, max_tokens=3000, max_retries=5)
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
                readtimeout=300
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

function parse_snomed_pubmed_response(llm_response::AbstractString, available_pmids::Vector{String})
    """Parse LLM response to extract SNOMED indications for PubMed approach"""
    indications = SnomedPubMedIndication[]
    
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
            
            # Extract PMIDs with enhanced validation
            pmids_match = match(r"PMIDS:\s*([^\n]+)", block)
            pmids_str = pmids_match !== nothing ? pmids_match.captures[1] : ""
            
            # Clean and validate PMIDs
            supporting_pmids = String[]
            if !isempty(pmids_str) && 
               !contains(pmids_str, "REASONING") && 
               !contains(pmids_str, "No evidence") &&
               !contains(pmids_str, "[insert") &&
               strip(pmids_str) != ""
                
                # Split by comma and clean each PMID
                for p in split(pmids_str, ",")
                    cleaned = strip(p)
                    # Only include if it looks like a valid PMID (7-8 digits) and is in our available PMIDs
                    if match(r"^\d{7,8}$", cleaned) !== nothing && cleaned in available_pmids
                        push!(supporting_pmids, cleaned)
                    end
                end
            end
            
            # Extract reasoning (improved to capture full text)
            reasoning_match = match(r"REASONING:\s*([^\n]*(?:\n(?!Research Finding)[^\n]*)*)", block)
            reasoning = reasoning_match !== nothing ? strip(reasoning_match.captures[1]) : ""
            
            # Only add if we have valid SNOMED code and term
            if !isempty(snomed_code) && !isempty(snomed_term)
                indication = SnomedPubMedIndication(
                    snomed_code,
                    snomed_term,
                    confidence,
                    evidence,
                    supporting_pmids,
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
    unique_indications = SnomedPubMedIndication[]
    seen_terms = Set{String}()
    
    for indication in indications
        if !(indication.snomed_term in seen_terms)
            push!(unique_indications, indication)
            push!(seen_terms, indication.snomed_term)
        end
    end
    
    return unique_indications
end

function process_drug_snomed_pubmed(drug_name::String, prompt_template::String, ollama_host::String)
    """Process a single drug's PubMed abstracts using SNOMED CT extraction"""
    
    start_time = time()
    
    # Load Phase 1 PubMed data
    input_file = joinpath(INPUT_DIR, "$(drug_name)_pubmed.json")
    if !isfile(input_file)
        println("❌ Phase 1 data not found: $input_file")
        return nothing
    end
    
    try
        phase1_data = JSON3.read(read(input_file, String))
        
        # Sample publications by MeSH descriptor
        sampled_abstracts, sampled_pmids, mesh_count = sample_publications_by_mesh(phase1_data)
        
        if isempty(sampled_abstracts)
            println("⚠️ No abstracts found for $drug_name")
            processing_time = time() - start_time
            return SnomedPubMedExtractionResult(
                drug_name,
                0,
                0,
                0,
                0,
                SnomedPubMedIndication[],
                processing_time,
                string(now()),
                MODEL_NAME,
                "snomed_pubmed_evidence_based",
                "No abstracts available"
            )
        end
        
        println("📊 Sampled $(length(sampled_abstracts)) abstracts from $mesh_count MeSH descriptors")
        
        # Create combined abstracts text (limit to prevent token overflow)
        max_abstracts = min(50, length(sampled_abstracts))  # Limit for token management
        abstracts_text = join(sampled_abstracts[1:max_abstracts], "\n\n---\n\n")
        
        # Format the prompt with drug name and abstracts
        prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name, count=10)
        prompt = replace(prompt, "{FORMATTED_ABSTRACTS}" => abstracts_text, count=10)
        
        # Query Llama with retry logic
        println("🔄 Querying LLM with $max_abstracts abstracts...")
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
            processing_time = time() - start_time
            return SnomedPubMedExtractionResult(
                drug_name,
                length(sampled_abstracts),
                mesh_count,
                0,
                0,
                SnomedPubMedIndication[],
                processing_time,
                string(now()),
                MODEL_NAME,
                "snomed_pubmed_evidence_based",
                llm_response
            )
        end
        
        # Parse response for SNOMED indications
        snomed_indications = parse_snomed_pubmed_response(llm_response, sampled_pmids)
        
        # Count confirmed indications
        confirmed_count = count(ind -> ind.confidence >= CONFIDENCE_THRESHOLD, snomed_indications)
        
        # Create result
        processing_time = time() - start_time
        result = SnomedPubMedExtractionResult(
            drug_name,
            length(sampled_abstracts),
            mesh_count,
            length(snomed_indications),
            confirmed_count,
            snomed_indications,
            processing_time,
            string(now()),
            MODEL_NAME,
            "snomed_pubmed_evidence_based",
            llm_response
        )
        
        return result
        
    catch e
        println("❌ Error processing $drug_name: $e")
        return nothing
    end
end

function sanitize_filename(drug_name::String)
    """Convert drug name to safe filename by replacing spaces with underscores and removing problematic characters"""
    # Remove quotes and replace spaces with underscores
    sanitized = replace(drug_name, "\"" => "", "'" => "", " " => "_")
    # Remove other problematic characters for filenames
    sanitized = replace(sanitized, r"[<>:\"/\\|?*]" => "_")
    return sanitized
end

function save_snomed_pubmed_results(result::SnomedPubMedExtractionResult)
    """Save SNOMED CT PubMed results to JSON file with consistent format"""
    safe_filename = sanitize_filename(result.drug_name)
    output_file = joinpath(OUTPUT_DIR, "$(safe_filename)_pubmed_snomed.json")
    
    try
        # Convert to dictionary for JSON serialization
        output_data = Dict(
            "drug_name" => result.drug_name,
            "snomed_indications" => [Dict(
                "snomed_code" => ind.snomed_code,
                "snomed_term" => ind.snomed_term,
                "confidence" => ind.confidence,
                "evidence" => ind.evidence,
                "supporting_pmids" => ind.supporting_pmids,
                "reasoning" => ind.reasoning,
                "extracted_at" => ind.extracted_at,
                "confirmed" => ind.confidence >= CONFIDENCE_THRESHOLD
            ) for ind in result.snomed_indications],
            "metadata" => Dict(
                "total_abstracts_analyzed" => result.total_abstracts_analyzed,
                "mesh_descriptors_sampled" => result.mesh_descriptors_sampled,
                "sampling_strategy" => "$(MAX_PUBLICATIONS_PER_MESH)_per_mesh_descriptor",
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
                "processing_notes" => result.total_indications > 0 ? "Successful SNOMED CT extraction from PubMed abstracts" : "No indications extracted"
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
    output_file = joinpath(OUTPUT_DIR, "$(safe_filename)_pubmed_snomed.json")
    return isfile(output_file)
end

function main()
    """Main function to process top 10 drugs with PubMed evidence-based SNOMED CT extraction"""
    
    println("=== THERA-IE Phase 2 Step 3: Top 10 PubMed Evidence-Based SNOMED Extraction ===")
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
    
    # Load SNOMED CT PubMed prompt template
    prompt_template = load_pubmed_snomed_prompt_template()
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
        
        # Process the drug using PubMed evidence-based approach
        result = process_drug_snomed_pubmed(drug_name, prompt_template, ollama_host)
        if result === nothing
            failed_count += 1
            continue
        end
        
        # Save results
        if save_snomed_pubmed_results(result)
            processed_count += 1
            println("✅ Extracted $(result.total_indications) SNOMED CT indications ($(result.confirmed_indications) confirmed)")
            println("📊 Analyzed $(result.total_abstracts_analyzed) abstracts from $(result.mesh_descriptors_sampled) MeSH descriptors")
            println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2))s")
        else
            failed_count += 1
        end
        
        println("")
        
        # Small delay to avoid overwhelming the API
        sleep(2.0)
    end
    
    # Final summary
    total_time = time() - start_time
    println("")
    println("=== PHASE 2 STEP 3 COMPLETE ===")
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