#!/usr/bin/env julia

"""
Intelligent Drug-Disease Indication Extractor

This script implements an efficient approach to extract drug-disease indications:
1. Load MeSH disease associations from drug files
2. For each disease, process publications sequentially until a confirmed indication is found
3. Stop processing after first confirmation to optimize performance

Usage:
    julia intelligent_drug_extractor.jl [drug_name]

If no drug name is provided, it will use "Levothyroxine" as the default.
"""

using HTTP
using JSON3
using Dates

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

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6  # Confidence threshold for confirmed indications (lowered from 0.7)
const MAX_PUBLICATIONS_PER_PAIR = 10   # Max publications to check per disease pair

function test_ollama_connection()
    """Test if Ollama server is accessible"""
    println("🔍 Testing Ollama connection...")
    try
        response = HTTP.get("http://localhost:11434/api/tags"; connect_timeout=5)
        println("✓ Ollama server is accessible")
        return true
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
    """
    Extract drug-disease pairs from MeSH associations with full publication data
    Returns a dictionary mapping diseases to their publication data (PMID, title, abstract, qualifiers)
    """
    println("🔍 Loading MeSH disease associations for $drug_name...")
    
    # Load the drug data file to get MeSH disease associations
    drug_file = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/$drug_name.json"
    
    if !isfile(drug_file)
        println("❌ Drug file not found: $drug_file")
        return Dict{String, Vector{Dict{String, Any}}}()
    end
    
    # Parse the drug data
    data = JSON3.read(read(drug_file, String))
    
    # Create a lookup for publications by PMID to get abstracts
    publications_by_pmid = Dict{String, Any}()
    if haskey(data.result, "publications_analyzed")
        for pub in data.result.publications_analyzed
            pmid = get(pub, "pmid", "")
            if !isempty(pmid)
                publications_by_pmid[String(pmid)] = pub
            end
        end
        println("📚 Loaded $(length(publications_by_pmid)) publications with abstracts")
    end
    
    # Extract disease publications
    disease_publications = Dict{String, Vector{Dict{String, Any}}}()
    
    if haskey(data.result, "disease_analysis") && haskey(data.result.disease_analysis, "disease_associations")
        disease_associations = data.result.disease_analysis.disease_associations
        
        println("📊 Found $(length(disease_associations)) MeSH disease associations")
        
        # Extract publications for each disease
        total_publications = 0
        for (disease, disease_info) in pairs(disease_associations)
            disease_name = String(disease)
            publications = Vector{Dict{String, Any}}()
            
            # Extract each publication entry
            for entry in disease_info
                pub_data = Dict{String, Any}()
                
                if haskey(entry, "pmid")
                    pmid = String(entry["pmid"])
                    pub_data["pmid"] = pmid
                    
                    # Try to get abstract from main publications
                    if haskey(publications_by_pmid, pmid)
                        main_pub = publications_by_pmid[pmid]
                        if haskey(main_pub, "abstract")
                            pub_data["abstract"] = String(main_pub["abstract"])
                        end
                    end
                end
                
                if haskey(entry, "title")
                    pub_data["title"] = String(entry["title"])
                end
                
                if haskey(entry, "qualifiers")
                    pub_data["qualifiers"] = [String(q) for q in entry["qualifiers"]]
                end
                
                push!(publications, pub_data)
                total_publications += 1
            end
            
            disease_publications[disease_name] = publications
        end
        
        println("✅ Extracted $(total_publications) publications across $(length(disease_publications)) diseases")
        
        # Remove diseases with no publications
        disease_publications = filter(p -> !isempty(p.second), disease_publications)
        
    else
        println("⚠️  No disease associations found in $drug_file")
        if haskey(data, "result")
            println("Available keys in result: $(keys(data.result))")
            if haskey(data.result, "disease_analysis")
                println("Available keys in disease_analysis: $(keys(data.result.disease_analysis))")
            end
        end
        return Dict{String, Vector{Dict{String, Any}}}()
    end
    
    println("✓ Found $(length(disease_publications)) diseases with publications ready for LLM processing")
    
    return disease_publications
end

function verify_drug_disease_pair(drug_name::String, disease::String, disease_publications::Vector{Dict{String, Any}})
    """
    Verify if a specific drug-disease pair is a valid indication
    by analyzing the publications already associated with this disease from MeSH data
    """
    println("\n🔍 Verifying if $disease is an indication for $drug_name...")
    println("  Found $(length(disease_publications)) publications for this disease")
    
    # Use the publications already identified for this disease
    # Limit to MAX_PUBLICATIONS_PER_PAIR to avoid overwhelming the LLM
    publications_to_check = disease_publications[1:min(MAX_PUBLICATIONS_PER_PAIR, length(disease_publications))]
    
    # Process these publications to verify the indication
    indications = Indication[]
    confirmed = false
    
    for (i, publication) in enumerate(publications_to_check)
        # Stop if we've already confirmed this indication
        if confirmed
            println("  ✓ Indication confirmed, stopping further publication checks")
            break
        end
        
        pmid = get(publication, "pmid", "unknown")
        title = get(publication, "title", "")
        abstract = get(publication, "abstract", "")
        qualifiers = get(publication, "qualifiers", String[])
        
        # Skip if no meaningful content
        if isempty(title) && isempty(abstract)
            println("  - Skipping publication $i: no title or abstract")
            continue
        end
        
        # Create a focused prompt specifically for this disease
        prompt = """
You are a medical expert analyzing a research publication about $drug_name and its potential use for treating $disease.

Title: $title

Abstract: $abstract

MeSH Qualifiers: $(join(qualifiers, ", "))

Task: Determine if this publication provides evidence that $drug_name is used to treat $disease.

Rules:
1. Focus ONLY on $disease, not other conditions
2. Look for clear statements that $drug_name treats $disease
3. Rate confidence 0.1-1.0 based on how clearly the indication is stated
4. A confidence of 0.6+ means clear evidence of therapeutic use
5. Consider MeSH qualifiers - "drug therapy" suggests therapeutic use

Format your response exactly as:
EVIDENCE: [YES or NO]
CONFIDENCE: [0.1-1.0]
REASONING: [Brief explanation of why you gave this confidence score]

If no relevant evidence, respond with:
EVIDENCE: NO
CONFIDENCE: 0.0
REASONING: No evidence found for $drug_name treating $disease
"""

        response = query_llama(prompt)
        
        if response === nothing
            println("  - Publication $i: LLM query failed")
            continue
        end
        
        # Parse response
        evidence = false
        confidence = 0.0
        reasoning = ""
        
        for line in split(response, '\n')
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
        
        # Create an indication record
        ind = Indication(
            confidence,
            pmid,
            title,
            abstract,
            string(now()),
            confidence >= CONFIDENCE_THRESHOLD
        )
        
        push!(indications, ind)
        
        # Check if this confirms the indication
        if confidence >= CONFIDENCE_THRESHOLD
            println("  ✓ Indication confirmed (confidence: $confidence)")
            println("    Reasoning: $reasoning")
            confirmed = true
        else
            println("  - Publication $i: confidence $confidence (below threshold)")
        end
        
        # Small delay to avoid overwhelming the API
        sleep(0.5)
    end
    
    # Create the drug-disease evidence object
    evidence = DrugDiseaseEvidence(
        drug_name,
        disease,
        confirmed ? maximum([ind.confidence for ind in indications]) : 0.0,
        indications,
        confirmed
    )
    
    return evidence
end

function save_results(result::ExtractionResult, output_file::String)
    """Save results to JSON file"""
    try
        # Convert to dictionary for JSON serialization
        output_data = Dict(
            "metadata" => Dict(
                "drug_name" => result.drug_name,
                "total_publications" => result.total_publications,
                "processed_publications" => result.processed_publications,
                "total_disease_pairs" => result.total_disease_pairs,
                "confirmed_disease_pairs" => result.confirmed_disease_pairs,
                "total_indications" => result.total_indications,
                "confirmation_rate_percent" => result.confirmed_disease_pairs / max(1, result.total_disease_pairs) * 100,
                "processing_time_seconds" => result.processing_time_seconds,
                "extracted_at" => result.extracted_at,
                "model_used" => MODEL_NAME
            ),
            "disease_pairs" => [Dict(
                "drug" => pair.drug,
                "disease" => pair.disease,
                "confidence" => pair.confidence,
                "confirmed" => pair.confirmed,
                "evidence_count" => length(pair.indications),
                "evidence" => [Dict(
                    "pmid" => ind.pmid,
                    "confidence" => ind.confidence,
                    "title" => ind.title,
                    "extracted_at" => ind.extracted_at,
                    "confirmed" => ind.confirmed
                ) for ind in pair.indications]
            ) for pair in result.disease_pairs]
        )
        
        # Create output directory if needed
        output_dir = dirname(output_file)
        if !isdir(output_dir)
            mkpath(output_dir)
        end
        
        open(output_file, "w") do f
            JSON3.pretty(f, output_data)
        end
        
        println("✓ Results saved to: $output_file")
        return true
    catch e
        println("❌ Failed to save results: $e")
        return false
    end
end

function process_drug(drug_name::String)
    """Process a single drug to extract and verify indications"""
    
    start_time = time()
    
    # Define file paths
    drug_file = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs/$drug_name.json"
    output_dir = "/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications"
    output_file = joinpath(output_dir, "$(drug_name)_intelligent_extraction.json")
    
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
    
    # Step 2: Verify each drug-disease pair
    verified_pairs = DrugDiseaseEvidence[]
    processed_count = 0
    
    for (disease, disease_pubs) in disease_publications
        evidence = verify_drug_disease_pair(drug_name, disease, disease_pubs)
        push!(verified_pairs, evidence)
        processed_count += length(evidence.indications)
        
        # Print status update
        if evidence.confirmed
            println("✓ Confirmed: $drug_name treats $disease (confidence: $(evidence.confidence))")
        else
            println("✗ Not confirmed: $drug_name for $disease (max confidence: $(evidence.confidence))")
        end
    end
    
    # Calculate final results
    confirmed_pairs = count(p -> p.confirmed, verified_pairs)
    total_indications = sum(p -> length(p.indications), verified_pairs)
    processing_time = time() - start_time
    
    result = ExtractionResult(
        drug_name,
        length(publications),
        processed_count,
        length(verified_pairs),
        confirmed_pairs,
        total_indications,
        verified_pairs,
        processing_time,
        string(now())
    )
    
    # Print summary
    println("\n=== EXTRACTION COMPLETE ===")
    println("🎯 Drug: $(result.drug_name)")
    println("📚 Total publications available: $(result.total_publications)")
    println("📊 Publications processed: $(result.processed_publications)")
    println("🔍 Total disease pairs identified: $(result.total_disease_pairs)")
    println("✅ Confirmed disease pairs: $(result.confirmed_disease_pairs)")
    println("📋 Total indication evidence: $(result.total_indications)")
    println("⏱️  Processing time: $(round(result.processing_time_seconds, digits=2)) seconds")
    
    # Print confirmed indications
    if confirmed_pairs > 0
        println("\n📋 Confirmed indications:")
        for pair in filter(p -> p.confirmed, verified_pairs)
            println("   - $(pair.disease) (confidence: $(pair.confidence))")
        end
    end
    
    # Save results
    return save_results(result, output_file)
end

function main()
    # Get drug name from command line argument or use default
    drug_name = length(ARGS) > 0 ? ARGS[1] : "Levothyroxine"
    
    println("=== Intelligent Drug-Indication Extractor ===")
    println("Node: $(gethostname())")
    println("Start time: $(now())")
    println("Drug: $drug_name")
    
    # Test Ollama connection
    if !test_ollama_connection()
        println("❌ Exiting due to Ollama connection failure")
        exit(1)
    end
    
    # Process the drug
    if process_drug(drug_name)
        println("\n✅ Extraction completed successfully!")
    else
        println("\n⚠️  Extraction completed but encountered errors")
        exit(1)
    end
end

# Run the script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
