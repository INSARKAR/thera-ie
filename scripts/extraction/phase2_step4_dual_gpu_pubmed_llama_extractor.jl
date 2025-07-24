#!/usr/bin/env julia

"""
Phase 2 Step 4: Dual GPU MeSH-Guided PubMed Llama Extraction
Processes drugs from Phase 1 using MeSH-guided analysis with Llama 3.2 on dual GPUs

Usage: julia phase2_step4_dual_gpu_pubmed_llama_extractor.jl <start_index> <total_batch_size> <gpu_id>
Example: julia phase2_step4_dual_gpu_pubmed_llama_extractor.jl 1 200 0
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const MAX_PUBLICATIONS_PER_MESH = 5
const INPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera/phase1_drug_pubmed_mesh"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera/phase2_indications_llama_pubmed"
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera/prompts/llm_prompt_pubmed.txt"

# Data structures
struct PubMedIndication
    indication::String
    confidence::Float64
    evidence::Bool
    confirmed::Bool
    mesh_context::String
    supporting_pmids::Vector{String}
    publication_count::Int
    reasoning::String
    extracted_at::String
end

struct MeshAnalysisSummary
    mesh_descriptor::String
    publications_analyzed::Int
    indications_extracted::Vector{String}
    max_confidence::Float64
end

function sanitize_filename(drug_name::String)
    """Convert drug name to safe filename"""
    sanitized = replace(drug_name, "\"" => "", "'" => "", " " => "_")
    sanitized = replace(sanitized, r"[<>:\"/\\|?*]" => "_")
    return sanitized
end

function load_prompt_template()
    """Load the PubMed prompt template"""
    try
        return read(PROMPT_FILE, String)
    catch e
        println("❌ Failed to load prompt template: $e")
        return nothing
    end
end

function get_all_drug_files()
    """Get all drug files from Phase 1"""
    try
        files = filter(f -> endswith(f, ".json"), readdir(INPUT_DIR))
        # Extract drug names from filenames
        drugs = [replace(f, ".json" => "") for f in files]
        return sort(drugs)
    catch e
        println("❌ Failed to read input directory: $e")
        return String[]
    end
end

function get_ollama_host(gpu_id::Int)
    """Get Ollama host based on GPU ID for dual GPU setup"""
    if gpu_id == 0
        return "http://127.0.0.1:11434"
    else
        return "http://127.0.0.1:11435"
    end
end

function test_ollama_connection(ollama_host::String)
    """Test if Ollama server is accessible"""
    try
        response = HTTP.get("$ollama_host/api/tags"; connect_timeout=5, readtimeout=10)
        return response.status == 200
    catch e
        println("❌ Cannot connect to Ollama at $ollama_host: $e")
        return false
    end
end

function query_llama(prompt::String, ollama_host::String; temperature=0.3, max_tokens=2000)
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
            "$ollama_host/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=10,
            readtimeout=300
        )
        
        result = JSON3.read(String(response.body))
        return get(result, "response", "")
    catch e
        println("❌ Llama query failed: $e")
        return nothing
    end
end

function select_publications_per_mesh(mesh_organized_publications)
    """Select up to MAX_PUBLICATIONS_PER_MESH publications per MeSH descriptor"""
    mesh_batches = []
    
    for (mesh_descriptor, publications) in mesh_organized_publications
        # Select up to MAX_PUBLICATIONS_PER_MESH publications
        selected_pubs = publications[1:min(MAX_PUBLICATIONS_PER_MESH, length(publications))]
        push!(mesh_batches, (mesh_descriptor, selected_pubs))
    end
    
    return mesh_batches
end

function format_abstracts_for_mesh(publications)
    """Format abstracts for a single MeSH descriptor"""
    formatted_abstracts = []
    
    for (index, pub) in enumerate(publications)
        abstract_text = """
Abstract $index:
PMID: $(pub.pmid)
Title: $(pub.title)
Abstract: $(pub.abstract)
"""
        push!(formatted_abstracts, abstract_text)
    end
    
    return join(formatted_abstracts, "\n")
end

function parse_llama_response(response::String, mesh_descriptor::String)
    """Parse Llama response for indications from a single MeSH context"""
    indications = PubMedIndication[]
    
    # Look for indication blocks in the response
    lines = split(response, '\n')
    current_indication = nothing
    current_confidence = 0.0
    current_evidence = false
    current_reasoning = ""
    
    for line in lines
        line = strip(line)
        
        if startswith(uppercase(line), "INDICATION")
            # Extract indication name
            if contains(line, ":")
                current_indication = strip(split(line, ":", 2)[2])
            end
        elseif startswith(uppercase(line), "CONFIDENCE:")
            confidence_text = strip(replace(line, r"^CONFIDENCE:\s*"i => ""))
            try
                current_confidence = parse(Float64, confidence_text)
                current_confidence = clamp(current_confidence, 0.0, 1.0)
            catch
                current_confidence = 0.0
            end
        elseif startswith(uppercase(line), "EVIDENCE:")
            evidence_text = strip(replace(line, r"^EVIDENCE:\s*"i => ""))
            current_evidence = uppercase(evidence_text) == "YES"
        elseif startswith(uppercase(line), "REASONING:")
            current_reasoning = strip(replace(line, r"^REASONING:\s*"i => ""))
        end
        
        # If we have complete information, create indication
        if current_indication !== nothing && current_confidence > 0 && !isempty(current_reasoning)
            if current_evidence && current_confidence >= 0.1  # Very low threshold for any valid indication
                indication_entry = PubMedIndication(
                    current_indication,
                    current_confidence,
                    current_evidence,
                    current_confidence >= CONFIDENCE_THRESHOLD,
                    mesh_descriptor,
                    String[],  # PMIDs would be populated from context
                    1,
                    current_reasoning,
                    string(now())
                )
                
                push!(indications, indication_entry)
            end
            
            # Reset for next indication
            current_indication = nothing
            current_confidence = 0.0
            current_evidence = false
            current_reasoning = ""
        end
    end
    
    return indications
end

function process_drug_mesh_guided(drug_name::String, prompt_template::String, ollama_host::String)
    """Process a single drug using MeSH-guided PubMed analysis"""
    
    input_file = joinpath(INPUT_DIR, "$(drug_name).json")
    
    if !isfile(input_file)
        println("❌ Input file not found: $input_file")
        return nothing
    end
    
    try
        # Load Phase 1 data
        data = JSON3.read(read(input_file, String))
        mesh_organized_publications = data.result.mesh_organized_publications
        
        println("✓ Loaded data for $drug_name")
        println("  📊 MeSH descriptors: $(length(mesh_organized_publications))")
        
        total_pubs = sum(length(pubs) for pubs in values(mesh_organized_publications))
        println("  📚 Total publications: $total_pubs")
        
        # Select publications per MeSH descriptor
        mesh_batches = select_publications_per_mesh(mesh_organized_publications)
        
        total_selected = sum(length(pubs) for (_, pubs) in mesh_batches)
        println("  🔍 Selected publications: $total_selected (max $MAX_PUBLICATIONS_PER_MESH per MeSH)")
        
        # Process each MeSH batch
        all_indications = PubMedIndication[]
        all_mesh_summaries = MeshAnalysisSummary[]
        
        for (batch_idx, (mesh_descriptor, publications)) in enumerate(mesh_batches)
            if batch_idx % 10 == 0
                println("  [$batch_idx/$(length(mesh_batches))] Processing: $mesh_descriptor")
            end
            
            # Format abstracts for this MeSH descriptor
            formatted_abstracts = format_abstracts_for_mesh(publications)
            
            # Create prompt for this MeSH context
            mesh_prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name)
            mesh_prompt = replace(mesh_prompt, "{MESH_DESCRIPTOR}" => mesh_descriptor)
            mesh_prompt = replace(mesh_prompt, "{NUMBER_OF_ABSTRACTS}" => string(length(publications)))
            mesh_prompt = replace(mesh_prompt, "{FORMATTED_ABSTRACTS}" => formatted_abstracts)
            
            # Query Llama for this MeSH context
            response = query_llama(mesh_prompt, ollama_host)
            
            if response === nothing
                continue
            end
            
            # Parse response for this MeSH context
            mesh_indications = parse_llama_response(response, mesh_descriptor)
            
            # Add to overall results
            append!(all_indications, mesh_indications)
            
            # Create mesh summary
            if !isempty(mesh_indications)
                indication_names = [ind.indication for ind in mesh_indications]
                max_conf = maximum([ind.confidence for ind in mesh_indications])
                
                summary = MeshAnalysisSummary(
                    mesh_descriptor,
                    length(publications),
                    indication_names,
                    max_conf
                )
                push!(all_mesh_summaries, summary)
            end
        end
        
        return all_indications, all_mesh_summaries, total_selected
        
    catch e
        println("❌ Error processing $drug_name: $e")
        return nothing
    end
end

function main()
    """Main processing function"""
    
    if length(ARGS) < 3
        println("Usage: julia phase2_step4_dual_gpu_pubmed_llama_extractor.jl <start_index> <total_batch_size> <gpu_id>")
        println("Example: julia phase2_step4_dual_gpu_pubmed_llama_extractor.jl 1 200 0")
        exit(1)
    end
    
    start_index = parse(Int, ARGS[1])
    total_batch_size = parse(Int, ARGS[2])
    gpu_id = parse(Int, ARGS[3])
    
    # Calculate this GPU's batch size (half of total)
    gpu_batch_size = div(total_batch_size, 2)
    if gpu_id == 1 && total_batch_size % 2 != 0
        gpu_batch_size += 1  # GPU 1 gets the extra drug if odd total
    end
    
    # Calculate this GPU's start index
    gpu_start_index = start_index + (gpu_id * div(total_batch_size, 2))
    
    # Get Ollama host for this GPU
    ollama_host = get_ollama_host(gpu_id)
    
    # Test Ollama connection
    if !test_ollama_connection(ollama_host)
        println("❌ Exiting due to Ollama connection failure on GPU $gpu_id")
        exit(1)
    end
    
    # Load prompt template
    prompt_template = load_prompt_template()
    if prompt_template === nothing
        println("❌ Failed to load prompt template")
        exit(1)
    end
    
    # Get all drugs
    all_drugs = get_all_drug_files()
    if isempty(all_drugs)
        println("❌ No drug files found in $INPUT_DIR")
        exit(1)
    end
    
    # Create output directory
    mkpath(OUTPUT_DIR)
    
    # Calculate batch range for this GPU
    end_index = min(gpu_start_index + gpu_batch_size - 1, length(all_drugs))
    batch_drugs = all_drugs[gpu_start_index:end_index]
    
    println("=== Phase 2 Step 4: Dual GPU MeSH-Guided PubMed Llama Extraction ===")
    println("📊 Total drugs available: $(length(all_drugs))")
    println("🎯 GPU $gpu_id processing: $gpu_start_index to $end_index ($(length(batch_drugs)) drugs)")
    println("🤖 Model: $MODEL_NAME")
    println("🔗 Ollama host: $ollama_host")
    println("📁 Output directory: $OUTPUT_DIR")
    println("Start time: $(now())")
    
    start_time = time()
    processed_count = 0
    failed_count = 0
    
    for (drug_idx, drug_name) in enumerate(batch_drugs)
        println("\\n[GPU$gpu_id $drug_idx/$(length(batch_drugs))] Processing: $drug_name")
        
        # Check if already processed
        output_file = joinpath(OUTPUT_DIR, "$(sanitize_filename(drug_name))_pubmed_llama_indications.json")
        if isfile(output_file)
            println("  ⏭️  Already processed, skipping")
            continue
        end
        
        drug_start_time = time()
        result = process_drug_mesh_guided(drug_name, prompt_template, ollama_host)
        
        if result !== nothing
            indications, mesh_summaries, total_pubs_analyzed = result
            processing_time = time() - drug_start_time
            confirmed_count = count(ind -> ind.confirmed, indications)
            
            # Create results
            results = Dict(
                "metadata" => Dict(
                    "drug_name" => drug_name,
                    "total_mesh_descriptors" => length(mesh_summaries),
                    "total_publications_analyzed" => total_pubs_analyzed,
                    "total_indications_found" => length(indications),
                    "confirmed_indications" => confirmed_count,
                    "processing_time_seconds" => processing_time,
                    "extracted_at" => string(now()),
                    "model_used" => MODEL_NAME,
                    "gpu_id" => gpu_id,
                    "approach" => "dual_gpu_mesh_guided_pubmed_llama",
                    "confidence_threshold" => CONFIDENCE_THRESHOLD
                ),
                "indications" => [Dict(
                    "indication" => ind.indication,
                    "confidence" => ind.confidence,
                    "evidence" => ind.evidence,
                    "confirmed" => ind.confirmed,
                    "mesh_context" => ind.mesh_context,
                    "supporting_pmids" => ind.supporting_pmids,
                    "publication_count" => ind.publication_count,
                    "reasoning" => ind.reasoning,
                    "extracted_at" => ind.extracted_at
                ) for ind in indications],
                "mesh_analysis_summary" => [Dict(
                    "mesh_descriptor" => summary.mesh_descriptor,
                    "publications_analyzed" => summary.publications_analyzed,
                    "indications_extracted" => summary.indications_extracted,
                    "max_confidence" => summary.max_confidence
                ) for summary in mesh_summaries]
            )
            
            # Save results
            open(output_file, "w") do file
                JSON3.pretty(file, results)
            end
            
            println("  ✅ Processed successfully: $(length(indications)) indications, $confirmed_count confirmed")
            println("  💾 Saved to: $(basename(output_file))")
            processed_count += 1
        else
            println("  ❌ Processing failed")
            failed_count += 1
        end
    end
    
    total_time = time() - start_time
    
    println("\\n=== GPU $gpu_id BATCH PROCESSING COMPLETE ===")
    println("✅ Successfully processed: $processed_count drugs")
    println("❌ Failed to process: $failed_count drugs")
    println("⏱️  Total processing time: $(round(total_time/60, digits=2)) minutes")
    println("📁 Results saved in: $OUTPUT_DIR")
    println("Completed at: $(now())")
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end