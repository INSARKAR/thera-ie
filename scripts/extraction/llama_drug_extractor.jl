#!/usr/bin/env julia

"""
Llama Drug-Disease Indication Extractor

This script uses Llama 3.2 to extract drug-disease indications with optimal performance:
1. Disease-parallel processing: Process multiple diseases simultaneously 
2. Drug therapy qualifier filtering: Only analyze therapeutically relevant publications
3. Early termination: Stop after finding confirmed indications

Usage:
    julia llama_drug_extractor.jl [drug_name]

If no drug name is provided, it will use "Levothyroxine" as the default.
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

# File paths
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera/prompts/llm_prompt_pubmed.txt"

# Data structures
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
end

# Helper functions
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

function load_prompt_template()
    """Load the prompt template from file"""
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
        
        # Find the actual prompt text (skip empty lines and headers)
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
    try
        response = HTTP.get("http://localhost:11434/api/tags"; connect_timeout=5, readtimeout=10)
        return response.status == 200
    catch e
        println("❌ Cannot connect to Ollama: $e")
        println("Please ensure Ollama is running and accessible")
        return false
    end
end

function query_llama(prompt::String; temperature=0.3, max_tokens=600)
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
            "http://localhost:11434/api/generate",
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            connect_timeout=10,
            readtimeout=60
        )
        
        result = JSON3.read(String(response.body))
        return get(result, "response", "")
    catch e
        println("❌ Llama query failed: $e")
        return nothing
    end
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
            # You could add more sophisticated disease filtering here
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

function process_drug_optimal(drug_name::String)
    """Process a single drug using optimal disease-parallel batch processing"""
    
    start_time = time()
    
    # Define file paths
    drug_file = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/$drug_name.json"
    output_dir = "/users/isarkar/sarkarcode/thera/phase1_llama_pubmed_extracted_indications"
    output_file = joinpath(output_dir, "$(drug_name)_llama_extracted_indications.json")
    
    # Validate input file
    if !isfile(drug_file)
        println("❌ Drug file not found: $drug_file")
        return false
    end
    
    # Load drug publications
    println("📖 Loading publications for $drug_name...")
    data = JSON3.read(read(drug_file, String))
    publications = data.result.publications_analyzed
    
    println("📊 Found $(length(publications)) publications for $drug_name")
    
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
    
    println("\n🚀 Starting optimal disease-parallel batch processing...")
    println("📊 Processing $(length(disease_publications)) diseases in parallel")
    if REQUIRE_DRUG_THERAPY_QUALIFIER
        println("🎯 Filtering: Only publications with 'drug therapy' MeSH qualifier")
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
            println("  - Batch $batch_num: No valid disease-publication pairs, ending")
            break
        end
        
        # Limit batch size
        if length(batch_pairs) > BATCH_SIZE
            batch_pairs = batch_pairs[1:BATCH_SIZE]
        end
        
        # Count unique diseases in this batch
        unique_diseases = length(unique([pair[1] for pair in batch_pairs]))
        println("  - Batch $batch_num: Processing $(length(batch_pairs)) publications from $unique_diseases diseases")
        
        # Load and create batch prompt from template
        prompt_template = load_prompt_template()
        if prompt_template === nothing
            println("  - Batch $batch_num: Failed to load prompt template")
            continue
        end
        
        # Format the prompt with actual values
        batch_prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name)
        batch_prompt = replace(batch_prompt, "{NUMBER_OF_PAIRS}" => string(length(batch_pairs)))
        batch_prompt = replace(batch_prompt, "{FORMATTED_DISEASE_PUBLICATION_PAIRS}" => 
            join([format_disease_publication_for_batch(pair[1], pair[2], i) for (i, pair) in enumerate(batch_pairs)], "\n\n"))
        
        response = query_llama(batch_prompt)
        
        if response === nothing
            println("  - Batch $batch_num: LLM query failed")
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
                println("    ✓ $disease confirmed (confidence: $(result.confidence))")
                println("      PMID: $pmid")
                println("      Reasoning: $(result.reasoning)")
                
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
        
        println("  - Batch $batch_num: Confirmed $(length(confirmed_diseases))/$(length(disease_publications)) diseases")
        
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
        string(now())
    )
    
    # Print summary
    println("\n=== OPTIMAL EXTRACTION COMPLETE ===")
    println("🎯 Drug: $(result.drug_name)")
    println("📚 Total publications available: $(result.total_publications)")
    println("📊 Publications processed: $(result.processed_publications)")
    println("🔍 Total disease pairs identified: $(result.total_disease_pairs)")
    println("✅ Confirmed disease pairs: $(result.confirmed_disease_pairs)")
    println("📋 Total indication evidence: $(result.total_indications)")
    println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2)) seconds")
    println("🚀 Batches processed: $batch_num")
    
    approach_desc = REQUIRE_DRUG_THERAPY_QUALIFIER ? 
        "Optimal disease-parallel processing with 1 publication per disease (drug therapy qualifier required)" :
        "Optimal disease-parallel processing with 1 publication per disease"
    println("📝 Approach: $approach_desc")
    
    # Print confirmed indications
    if confirmed_pairs > 0
        println("\n📋 Confirmed indications:")
        for pair in filter(p -> p.confirmed, verified_pairs_vector)
            println("   - $(pair.disease) (confidence: $(pair.confidence))")
        end
    end
    
    # Save results
    return save_results(result, output_file)
end

function save_results(result::ExtractionResult, output_file::String)
    """Save results to JSON file"""
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
                "approach" => "optimal_disease_parallel"
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
        
        println("✓ Results saved to: $output_file")
        return true
    catch e
        println("❌ Failed to save results: $e")
        return false
    end
end

function main()
    """Main function to run the extraction"""
    println("=== Llama Drug-Disease Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    
    # Get drug name from command line argument or use default
    drug_name = length(ARGS) > 0 ? ARGS[1] : "Levothyroxine"
    println("Drug: $drug_name")
    
    # Test Ollama connection
    if !test_ollama_connection()
        println("❌ Exiting due to Ollama connection failure")
        exit(1)
    end
    
    # Process the drug using optimal approach
    if process_drug_optimal(drug_name)
        println("\n✅ Optimal extraction completed successfully!")
    else
        println("\n⚠️  Optimal extraction completed but encountered errors")
        exit(1)
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end