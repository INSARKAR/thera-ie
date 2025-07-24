#!/usr/bin/env julia

"""
Dual GPU Llama Drug-Disease Indication Extractor Coordinator

This script coordinates parallel extraction of drug-disease indications using two GPUs.
Each GPU runs a separate Ollama server and processes one drug simultaneously.

Usage:
    julia dual_gpu_llama_coordinator.jl [drug1] [drug2]

If no drug names are provided, it will use "Levothyroxine" and "Metformin" as defaults.
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const MAX_PUBLICATIONS_PER_PAIR = 10
const BATCH_SIZE = 20
const REQUIRE_DRUG_THERAPY_QUALIFIER = true

# GPU Server Configuration
const GPU1_HOST = "http://localhost:11434"
const GPU2_HOST = "http://localhost:11435"

# Data structures for dual GPU processing
struct Indication
    confidence::Float64
    pmid::String
    title::String
    abstract::String
    extracted_at::String
    confirmed::Bool
end

struct DrugDiseaseEvidence
    drug::String
    disease::String
    confidence::Float64
    indications::Vector{Indication}
    confirmed::Bool
end

struct ExtractionResult
    drug_name::String
    total_publications::Int
    processed_publications::Int
    total_disease_pairs::Int
    confirmed_disease_pairs::Int
    total_indications::Int
    disease_pairs::Vector{DrugDiseaseEvidence}
    processing_time_seconds::Float64
    extracted_at::String
    gpu_used::String
end

# Helper functions (copied from main extractor to avoid conflicts)
function has_drug_therapy_qualifier(pub::Dict)
    """Check if publication has drug therapy qualifier"""
    qualifiers = get(pub, "qualifiers", String[])
    for qualifier in qualifiers
        if occursin("drug therapy", lowercase(String(qualifier)))
            return true
        end
    end
    return false
end

function format_disease_publication_for_batch(disease::String, pub::Dict, index::Int)
    """Format a disease-publication pair for cross-disease batch processing"""
    pmid = get(pub, "pmid", "unknown")
    title = get(pub, "title", "")
    abstract = get(pub, "abstract", "")
    qualifiers = get(pub, "qualifiers", String[])
    
    return """Disease-Publication $index:
Disease: $disease
PMID: $pmid
Title: $title
Abstract: $abstract
MeSH Qualifiers: $(join(qualifiers, ", "))"""
end

struct DiseaseBatchResult
    disease::String
    confidence::Float64
    evidence::Bool
    reasoning::String
end

function parse_disease_batch_response(response::String, disease_pub_pairs::Vector)
    """Parse LLM response for cross-disease batch processing"""
    results = DiseaseBatchResult[]
    
    # Split response by "Disease-Publication" markers
    sections = split(response, r"Disease-Publication\s+\d+:")
    
    # Skip first section (usually empty or contains preamble)
    for (i, section) in enumerate(sections[2:end])
        if i > length(disease_pub_pairs)
            break
        end
        
        disease_name, pub = disease_pub_pairs[i]
        
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
        
        result = DiseaseBatchResult(disease_name, confidence, evidence, reasoning)
        push!(results, result)
    end
    
    return results
end

function identify_disease_pairs(drug_name::String, publications)
    """Identify diseases from MeSH descriptors in publications"""
    disease_publications = Dict{String, Vector{Dict{String, Any}}}()
    
    for pub in publications
        mesh_descriptors = get(pub, "mesh_descriptors", [])
        for mesh_desc in mesh_descriptors
            descriptor = get(mesh_desc, "descriptor", "")
            qualifiers = get(mesh_desc, "qualifiers", [])
            
            # Check if this is a disease-related descriptor
            if !isempty(descriptor) && !isempty(qualifiers)
                # Convert publication to Dict format
                pub_dict = Dict{String, Any}(
                    "pmid" => get(pub, "pmid", ""),
                    "title" => get(pub, "title", ""),
                    "abstract" => get(pub, "abstract", ""),
                    "qualifiers" => qualifiers
                )
                
                if !haskey(disease_publications, descriptor)
                    disease_publications[descriptor] = Dict{String, Any}[]
                end
                push!(disease_publications[descriptor], pub_dict)
            end
        end
    end
    
    println("📊 Found $(length(disease_publications)) unique diseases")
    return disease_publications
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

function query_llama_gpu(prompt::String, host::String, gpu_name::String; temperature=0.3, max_tokens=600)
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
            readtimeout=60
        )
        
        result = JSON3.read(String(response.body))
        return get(result, "response", "")
    catch e
        println("❌ $gpu_name Llama query failed: $e")
        return nothing
    end
end

function process_drug_dual_gpu(drug_name::String, gpu_host::String, gpu_name::String)
    """Process a single drug using specified GPU"""
    
    start_time = time()
    
    # Define file paths
    drug_file = "/users/isarkar/sarkarcode/thera/phase1_drug_pubmed_refs/$drug_name.json"
    output_dir = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
    output_file = joinpath(output_dir, "$(drug_name)_llama_extracted_indications.json")
    
    # Validate input file
    if !isfile(drug_file)
        println("❌ [$gpu_name] Drug file not found: $drug_file")
        return nothing
    end
    
    # Load drug publications
    println("📖 [$gpu_name] Loading publications for $drug_name...")
    data = JSON3.read(read(drug_file, String))
    publications = data.result.publications_analyzed
    
    println("📊 [$gpu_name] Found $(length(publications)) publications for $drug_name")
    
    # Step 1: Identify potential drug-disease pairs from MeSH associations
    disease_publications = identify_disease_pairs(drug_name, publications)
    
    # Step 2: Create disease iterators for optimal processing
    disease_iterators = Dict{String, Int}()
    for disease in keys(disease_publications)
        disease_iterators[disease] = 1
    end
    
    # Step 3: Process diseases using optimal parallel batches
    verified_pairs = Dict{String, DrugDiseaseEvidence}()
    processed_count = 0
    batch_num = 0
    confirmed_diseases = Set{String}()
    
    # Initialize disease evidence tracking
    for disease in keys(disease_publications)
        verified_pairs[disease] = DrugDiseaseEvidence(
            drug_name,
            disease,
            0.0,
            Indication[],
            false
        )
    end
    
    println("🚀 [$gpu_name] Starting disease-parallel batch processing for $drug_name...")
    println("📊 [$gpu_name] Processing $(length(disease_publications)) diseases in parallel")
    if REQUIRE_DRUG_THERAPY_QUALIFIER
        println("🎯 [$gpu_name] Filtering: Only publications with 'drug therapy' MeSH qualifier")
    end
    
    while length(confirmed_diseases) < length(disease_publications) && batch_num < MAX_PUBLICATIONS_PER_PAIR
        batch_num += 1
        
        # Create batch of disease-publication pairs (1 publication per disease)
        batch_pairs = Tuple{String, Dict{String, Any}}[]
        
        for disease in keys(disease_publications)
            # Skip if already confirmed
            if disease in confirmed_diseases
                continue
            end
            
            # Get next publication for this disease
            pub_index = disease_iterators[disease]
            disease_pubs = disease_publications[disease]
            
            # Find next valid publication for this disease
            while pub_index <= length(disease_pubs)
                pub = disease_pubs[pub_index]
                
                # Check if publication meets criteria
                has_content = !isempty(get(pub, "title", "")) || !isempty(get(pub, "abstract", ""))
                has_drug_therapy = REQUIRE_DRUG_THERAPY_QUALIFIER ? has_drug_therapy_qualifier(pub) : true
                
                if has_content && has_drug_therapy
                    push!(batch_pairs, (disease, pub))
                    break
                end
                pub_index += 1
            end
            
            # Update iterator to next publication
            disease_iterators[disease] = pub_index + 1
        end
        
        # Skip if no valid pairs in this batch
        if isempty(batch_pairs)
            println("  - [$gpu_name] Batch $batch_num: No valid disease-publication pairs, ending")
            break
        end
        
        # Limit batch size
        if length(batch_pairs) > BATCH_SIZE
            batch_pairs = batch_pairs[1:BATCH_SIZE]
        end
        
        # Count unique diseases in this batch
        unique_diseases = length(unique([pair[1] for pair in batch_pairs]))
        println("  - [$gpu_name] Batch $batch_num: Processing $(length(batch_pairs)) publications from $unique_diseases diseases")
        
        # Create batch prompt
        batch_prompt = """
You are a medical expert analyzing research publications about $drug_name and its potential therapeutic uses.

Analyze these $(length(batch_pairs)) disease-publication pairs:

$(join([format_disease_publication_for_batch(pair[1], pair[2], i) for (i, pair) in enumerate(batch_pairs)], "\n\n"))

Task: For each disease-publication pair, determine if the publication provides evidence that $drug_name is used to treat that specific disease.

Rules:
1. Focus ONLY on the specified disease for each pair
2. Look for clear statements that $drug_name treats the disease
3. Rate confidence 0.1-1.0 based on how clearly the indication is stated
4. A confidence of 0.6+ means clear evidence of therapeutic use
5. Consider MeSH qualifiers - "drug therapy" suggests therapeutic use

Format your response for each disease-publication pair exactly as:
Disease-Publication 1:
EVIDENCE: [YES or NO]
CONFIDENCE: [0.1-1.0]
REASONING: [Brief explanation]

Disease-Publication 2:
EVIDENCE: [YES or NO]
CONFIDENCE: [0.1-1.0]
REASONING: [Brief explanation]

Continue for all disease-publication pairs...
"""
        
        response = query_llama_gpu(batch_prompt, gpu_host, gpu_name)
        
        if response === nothing
            println("  - [$gpu_name] Batch $batch_num: LLM query failed")
            continue
        end
        
        # Parse batch response
        batch_results = parse_disease_batch_response(response, batch_pairs)
        
        # Process each result in the batch
        for result in batch_results
            disease = result.disease
            
            # Find the corresponding publication
            pub = nothing
            for (d, p) in batch_pairs
                if d == disease
                    pub = p
                    break
                end
            end
            
            if pub === nothing
                continue
            end
            
            pmid = get(pub, "pmid", "unknown")
            title = get(pub, "title", "")
            abstract = get(pub, "abstract", "")
            
            # Create an indication record
            ind = Indication(
                result.confidence,
                pmid,
                title,
                abstract,
                string(now()),
                result.confidence >= CONFIDENCE_THRESHOLD
            )
            
            # Add to disease evidence
            push!(verified_pairs[disease].indications, ind)
            processed_count += 1
            
            # Check if this confirms the indication
            if result.confidence >= CONFIDENCE_THRESHOLD
                println("    ✓ [$gpu_name] $disease confirmed (confidence: $(result.confidence))")
                println("      PMID: $pmid")
                
                # Update disease evidence
                verified_pairs[disease] = DrugDiseaseEvidence(
                    drug_name,
                    disease,
                    result.confidence,
                    verified_pairs[disease].indications,
                    true
                )
                
                push!(confirmed_diseases, disease)
            else
                # Update max confidence if higher
                if result.confidence > verified_pairs[disease].confidence
                    verified_pairs[disease] = DrugDiseaseEvidence(
                        drug_name,
                        disease,
                        result.confidence,
                        verified_pairs[disease].indications,
                        false
                    )
                end
            end
        end
        
        println("  - [$gpu_name] Batch $batch_num: Confirmed $(length(confirmed_diseases))/$(length(disease_publications)) diseases")
        
        # Small delay to avoid overwhelming the API
        sleep(0.5)
    end
    
    # Convert to vector for final results
    verified_pairs_vector = collect(values(verified_pairs))
    
    # Calculate final results
    confirmed_pairs = length(confirmed_diseases)
    total_indications = isempty(verified_pairs_vector) ? 0 : sum(p -> length(p.indications), verified_pairs_vector)
    processing_time = time() - start_time
    
    result = ExtractionResult(
        drug_name,
        length(publications),
        processed_count,
        length(verified_pairs_vector),
        confirmed_pairs,
        total_indications,
        verified_pairs_vector,
        processing_time,
        string(now()),
        gpu_name
    )
    
    # Print summary
    println("\\n=== [$gpu_name] EXTRACTION COMPLETE ===")
    println("🎯 Drug: $(result.drug_name)")
    println("📚 Total publications available: $(result.total_publications)")
    println("📊 Publications processed: $(result.processed_publications)")
    println("🔍 Total disease pairs identified: $(result.total_disease_pairs)")
    println("✅ Confirmed disease pairs: $(result.confirmed_disease_pairs)")
    println("📋 Total indication evidence: $(result.total_indications)")
    println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2)) seconds")
    println("🚀 Batches processed: $batch_num")
    
    # Save results
    if save_results_dual_gpu(result, output_file)
        println("✓ [$gpu_name] Results saved successfully")
        return result
    else
        println("❌ [$gpu_name] Failed to save results")
        return nothing
    end
end

function save_results_dual_gpu(result::ExtractionResult, output_file::String)
    """Save results to JSON file with GPU info"""
    try
        # Convert to dictionary for JSON serialization with explicit type conversion
        output_data = Dict(
            "metadata" => Dict(
                "drug_name" => String(result.drug_name),
                "total_publications" => Int(result.total_publications),
                "processed_publications" => Int(result.processed_publications),
                "total_disease_pairs" => Int(result.total_disease_pairs),
                "confirmed_disease_pairs" => Int(result.confirmed_disease_pairs),
                "total_indications" => Int(result.total_indications),
                "confirmation_rate_percent" => Float64(result.confirmed_disease_pairs / max(1, result.total_disease_pairs) * 100),
                "processing_time_seconds" => Float64(result.processing_time_seconds),
                "extracted_at" => String(result.extracted_at),
                "model_used" => String(MODEL_NAME),
                "approach" => "dual_gpu_disease_parallel",
                "gpu_used" => String(result.gpu_used)
            ),
            "disease_pairs" => [Dict(
                "drug" => String(pair.drug),
                "disease" => String(pair.disease),
                "confidence" => Float64(pair.confidence),
                "confirmed" => Bool(pair.confirmed),
                "evidence_count" => Int(length(pair.indications)),
                "evidence" => [Dict(
                    "confidence" => Float64(ind.confidence),
                    "pmid" => String(ind.pmid),
                    "title" => String(ind.title),
                    "abstract" => String(ind.abstract),
                    "extracted_at" => String(ind.extracted_at),
                    "confirmed" => Bool(ind.confirmed)
                ) for ind in pair.indications]
            ) for pair in result.disease_pairs]
        )
        
        # Create output directory if it doesn't exist
        mkpath(dirname(output_file))
        
        # Write results to file with pretty formatting
        open(output_file, "w") do file
            JSON3.pretty(file, output_data)
        end
        
        return true
    catch e
        println("❌ Failed to save results: $e")
        return false
    end
end

function main()
    """Main function to run dual GPU extraction"""
    println("=== Dual GPU Llama Drug-Disease Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    
    # Get drug names from command line arguments or use defaults
    drug1 = length(ARGS) > 0 ? ARGS[1] : "Levothyroxine"
    drug2 = length(ARGS) > 1 ? ARGS[2] : "Metformin"
    
    println("Drug 1 (GPU 0): $drug1")
    println("Drug 2 (GPU 1): $drug2")
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
    
    # Start parallel processing
    println("=== Starting Parallel Drug Processing ===")
    
    # Create tasks for parallel execution
    task1 = @async process_drug_dual_gpu(drug1, GPU1_HOST, "GPU 0")
    task2 = @async process_drug_dual_gpu(drug2, GPU2_HOST, "GPU 1")
    
    # Wait for both tasks to complete
    result1 = fetch(task1)
    result2 = fetch(task2)
    
    # Print final summary
    println("\\n=== DUAL GPU EXTRACTION COMPLETE ===")
    
    if result1 !== nothing
        println("✅ $drug1 (GPU 0): $(result1.confirmed_disease_pairs) confirmed diseases in $(round(result1.processing_time_seconds, digits=2))s")
    else
        println("❌ $drug1 (GPU 0): Processing failed")
    end
    
    if result2 !== nothing
        println("✅ $drug2 (GPU 1): $(result2.confirmed_disease_pairs) confirmed diseases in $(round(result2.processing_time_seconds, digits=2))s")
    else
        println("❌ $drug2 (GPU 1): Processing failed")
    end
    
    # Calculate total time (should be approximately max of the two)
    if result1 !== nothing && result2 !== nothing
        total_time = max(result1.processing_time_seconds, result2.processing_time_seconds)
        combined_diseases = result1.confirmed_disease_pairs + result2.confirmed_disease_pairs
        println("🚀 Total parallel processing time: $(round(total_time, digits=2)) seconds")
        println("📊 Combined confirmed diseases: $combined_diseases")
        println("⚡ Effective speedup: ~2x vs sequential processing")
    end
    
    # Determine exit code
    success1 = result1 !== nothing
    success2 = result2 !== nothing
    
    if success1 && success2
        println("\\n✅ Dual GPU extraction completed successfully!")
        exit(0)
    elseif success1 || success2
        println("\\n⚠️  Partial success - one extraction completed")
        exit(1)
    else
        println("\\n❌ Both extractions failed")
        exit(1)
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end