#!/usr/bin/env julia

"""
Phase 2 Step 4: MeSH-Guided PubMed Llama Extraction
Processes drugs from Phase 1 using MeSH-guided analysis with Llama 3.2

Usage: julia phase2_step4_pubmed_llama_extractor.jl <start_index> <batch_size>
Example: julia phase2_step4_pubmed_llama_extractor.jl 1 100
"""

using HTTP
using JSON3
using Dates

# Configuration
const MODEL_NAME = "llama3.2"
const CONFIDENCE_THRESHOLD = 0.6
const MAX_PUBLICATIONS_PER_MESH = 5
const INPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera-ie/phase1_drug_pubmed_mesh"
const OUTPUT_DIR = "/oscar/home/isarkar/sarkarcode/thera-ie/phase2_indications_llama_pubmed"
const PROMPT_FILE = "/oscar/home/isarkar/sarkarcode/thera-ie/prompts/llm_prompt_pubmed.txt"

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

function query_llama(prompt::String; temperature=0.3, max_tokens=2000)
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

function parse_confidence_value(confidence_text::String)
    """Parse confidence value from various formats"""
    confidence_text = strip(uppercase(confidence_text))
    
    # Handle direct numeric values (0.0 to 1.0)
    try
        val = parse(Float64, confidence_text)
        if 0.0 <= val <= 1.0
            return val
        elseif val > 1.0  # Handle values like 0.8, 8.0, etc.
            return val > 10.0 ? val / 100.0 : val / 10.0
        end
    catch
        # Continue to text parsing
    end
    
    # Handle text-based confidence levels
    if occursin("HIGH", confidence_text)
        return 0.9
    elseif occursin("MODERATE", confidence_text) || occursin("MEDIUM", confidence_text)
        return 0.7
    elseif occursin("LOW", confidence_text)
        return 0.4
    elseif occursin("VERY HIGH", confidence_text)
        return 0.95
    elseif occursin("VERY LOW", confidence_text)
        return 0.2
    end
    
    # Handle ranges like "0.1-1.0", "0.8-0.9"
    range_match = match(r"(\d+\.?\d*)\s*[-–]\s*(\d+\.?\d*)", confidence_text)
    if !isnothing(range_match)
        try
            min_val = parse(Float64, range_match.captures[1])
            max_val = parse(Float64, range_match.captures[2])
            # Use midpoint of range
            return (min_val + max_val) / 2.0
        catch
            # Fall through to default
        end
    end
    
    # Handle percentages like "80%", "90%"
    percent_match = match(r"(\d+)%", confidence_text)
    if !isnothing(percent_match)
        try
            percent_val = parse(Float64, percent_match.captures[1])
            return percent_val / 100.0
        catch
            # Fall through to default
        end
    end
    
    # Default fallback for unparseable values
    println("⚠️  Warning: Could not parse confidence '$confidence_text', defaulting to 0.5")
    return 0.5
end

function parse_llama_response(response::String, mesh_descriptor)
    """Parse Llama response for indications from a single MeSH context"""
    indications = PubMedIndication[]
    
    # Split response by various indication markers
    sections_indication = split(response, r"Indication\s+\d+:")           # "Indication 1:"
    sections_numbered = split(response, r"\b\d+\.\s*\n")                  # "1." followed by newline
    sections_numbered_indication = split(response, r"\b\d+\.\s+Indication:") # "1. Indication:"
    sections_bold_numbered = split(response, r"\b\d+\.\s+\*\*")           # "1. **"
    sections_direct_numbered = split(response, r"\b\d+\.\s+(?![Cc]onfidence:|[Ee]vidence:|[Pp]mids:|[Rr]easoning:)(?!\*\*)") # "1. [Direct Name]"
    sections_confidence_format = split(response, r"\b\d+\.\s+[^(]+\s*\(CONFIDENCE:")  # "1. Drug Name (CONFIDENCE:"
    
    # Find the split pattern that found the most sections (most specific match)
    all_sections = [
        (sections_indication, "Indication X:", length(sections_indication)),
        (sections_numbered, "X.", length(sections_numbered)),
        (sections_numbered_indication, "X. Indication:", length(sections_numbered_indication)),
        (sections_bold_numbered, "X. **", length(sections_bold_numbered)),
        (sections_direct_numbered, "X. [Direct]", length(sections_direct_numbered)),
        (sections_confidence_format, "X. Name (CONFIDENCE:", length(sections_confidence_format))
    ]
    
    # Choose the pattern with most sections (indicating best match)
    best_match = all_sections[1]
    for section_info in all_sections
        if section_info[3] > best_match[3]
            best_match = section_info
        end
    end
    
    sections, pattern_used = best_match[1], best_match[2]
    
    println("    🔍 PARSE DEBUG - Using pattern '$pattern_used', found $(length(sections)) sections")
    
    # DEBUG: Print section info
    println("    🔍 PARSE DEBUG - Split into $(length(sections)) sections")
    if length(sections) > 1
        println("    🔍 PARSE DEBUG - First section preview: '$(first(sections[2], min(50, length(sections[2]))))'")
    end
    
    # Skip first section (usually empty or contains preamble)
    for section in sections[2:end]
        # Parse indication name, evidence, confidence, PMIDs, and reasoning from section
        indication_name = ""
        evidence = false
        confidence = 0.0
        pmids = String[]
        reasoning = ""
        
        lines = split(section, '\n')
        
        # Special handling for different formats
        if pattern_used == "X. Name (CONFIDENCE:" && !isempty(lines)
            first_line = strip(lines[1])
            # Extract indication name and confidence from first line: "Drug Name (CONFIDENCE: 0.X)"
            confidence_match = match(r"^([^(]+)\s*\(CONFIDENCE:\s*([\d.]+)\)", first_line)
            if !isnothing(confidence_match)
                indication_name = strip(confidence_match.captures[1])
                confidence_text = strip(confidence_match.captures[2])
                confidence = parse_confidence_value(confidence_text)
            end
        end
        
        # Alternative parsing approach for minimal structured format
        # Handle cases where indications appear without explicit numbering
        if isempty(indication_name) && length(lines) >= 3
            # Check if this looks like: "Indication Name\nCONFIDENCE: X\nEVIDENCE: YES\nPMIDS: ..."
            first_line = strip(lines[1])
            if !startswith(uppercase(first_line), r"INDICATION:|EVIDENCE:|CONFIDENCE:|PMIDS:|REASONING:")
                # First line is likely the indication name
                potential_indication = first_line
                # Check if following lines contain CONFIDENCE/EVIDENCE patterns
                for line in lines[2:end]
                    if startswith(uppercase(strip(line)), "CONFIDENCE:")
                        indication_name = potential_indication
                        break
                    end
                end
            end
        end
        
        for (i, line) in enumerate(lines)
            line = strip(line)
            if startswith(uppercase(line), "INDICATION:")
                indication_name = strip(replace(line, r"^INDICATION:\s*"i => ""))
            elseif startswith(uppercase(line), "EVIDENCE:")
                evidence_text = strip(replace(line, r"^EVIDENCE:\s*"i => ""))
                evidence = uppercase(evidence_text) == "YES"
            elseif startswith(uppercase(line), "CONFIDENCE:")
                confidence_text = strip(replace(line, r"^CONFIDENCE:\s*"i => ""))
                # Inline confidence parsing to avoid scoping issues
                confidence_upper = strip(uppercase(confidence_text))
                try
                    # Try direct numeric parse first
                    val = parse(Float64, confidence_upper)
                    if 0.0 <= val <= 1.0
                        confidence = val
                    elseif val > 1.0
                        confidence = val > 10.0 ? val / 100.0 : val / 10.0
                    else
                        confidence = 0.5
                    end
                catch
                    # Handle text-based values
                    if occursin("HIGH", confidence_upper)
                        confidence = 0.9
                    elseif occursin("MODERATE", confidence_upper) || occursin("MEDIUM", confidence_upper)
                        confidence = 0.7
                    elseif occursin("LOW", confidence_upper)
                        confidence = 0.4
                    elseif occursin("VERY HIGH", confidence_upper)
                        confidence = 0.95
                    elseif occursin("VERY LOW", confidence_upper)
                        confidence = 0.2
                    else
                        # Handle ranges like "0.1-1.0"
                        range_match = match(r"(\d+\.?\d*)\s*[-–]\s*(\d+\.?\d*)", confidence_upper)
                        if !isnothing(range_match)
                            try
                                min_val = parse(Float64, range_match.captures[1])
                                max_val = parse(Float64, range_match.captures[2])
                                confidence = (min_val + max_val) / 2.0
                            catch
                                confidence = 0.5
                            end
                        else
                            # Handle percentages
                            percent_match = match(r"(\d+)%", confidence_upper)
                            if !isnothing(percent_match)
                                try
                                    percent_val = parse(Float64, percent_match.captures[1])
                                    confidence = percent_val / 100.0
                                catch
                                    confidence = 0.5
                                end
                            else
                                confidence = 0.5
                            end
                        end
                    end
                end
            elseif startswith(uppercase(line), "PMIDS:")
                pmids_text = strip(replace(line, r"^PMIDS:\s*"i => ""))
                # Split by comma and clean up PMIDs
                if !isempty(pmids_text)
                    pmids = [strip(pmid) for pmid in split(pmids_text, ",") if !isempty(strip(pmid))]
                end
            elseif startswith(uppercase(line), "REASONING:")
                reasoning = strip(replace(line, r"^REASONING:\s*"i => ""))
            elseif isempty(indication_name) && !isempty(line) && !startswith(uppercase(line), r"INDICATION:|EVIDENCE:|CONFIDENCE:|PMIDS:|REASONING:")
                # First non-empty line that doesn't start with a keyword is likely the indication name
                # Handle bold markdown format: **Indication Name**
                indication_name = replace(line, r"^\*\*(.*?)\*\*$" => s"\1")
                if indication_name == line  # No bold formatting found
                    indication_name = line
                end
            end
        end
        
        # Create indication if we have valid data
        if !isempty(indication_name) && confidence > 0
            indication_entry = PubMedIndication(
                indication_name,
                confidence,
                evidence,
                confidence >= CONFIDENCE_THRESHOLD,
                string(mesh_descriptor),
                pmids,  # PMIDs extracted from LLM response
                length(pmids),
                reasoning,
                string(now())
            )
            
            push!(indications, indication_entry)
        end
    end
    
    return indications
end

function process_drug_mesh_guided(drug_name::String, prompt_template::String)
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
        
        # Handle empty mesh_organized_publications
        if isempty(mesh_organized_publications)
            println("  ⚠️  No MeSH descriptors found, creating zero-publications output file")
            
            # Create results for drug with no publications
            results = Dict(
                "metadata" => Dict(
                    "drug_name" => drug_name,
                    "total_mesh_descriptors" => 0,
                    "total_publications_analyzed" => 0,
                    "total_indications_found" => 0,
                    "confirmed_indications" => 0,
                    "processing_time_seconds" => 0.0,
                    "extracted_at" => string(now()),
                    "model_used" => MODEL_NAME,
                    "approach" => "mesh_guided_pubmed_llama",
                    "confidence_threshold" => CONFIDENCE_THRESHOLD
                ),
                "raw_llama_response" => "No publications available for analysis - drug has 0 MeSH descriptors in Phase 1 data",
                "indications" => [],
                "mesh_analysis_summary" => []
            )
            
            return [], [], 0, "No publications available for analysis - drug has 0 MeSH descriptors in Phase 1 data"
        end
        
        total_pubs = sum(length(pubs) for pubs in values(mesh_organized_publications))
        println("  📚 Total publications: $total_pubs")
        
        # Select publications per MeSH descriptor
        mesh_batches = select_publications_per_mesh(mesh_organized_publications)
        
        total_selected = sum(length(pubs) for (_, pubs) in mesh_batches)
        println("  🔍 Selected publications: $total_selected (max $MAX_PUBLICATIONS_PER_MESH per MeSH)")
        
        # Collect ALL abstracts from ALL MeSH descriptors for single API call
        all_formatted_abstracts = String[]
        mesh_descriptor_list = String[]
        
        for (mesh_descriptor, publications) in mesh_batches
            # Format abstracts for this MeSH descriptor
            formatted_abstracts = format_abstracts_for_mesh(publications)
            push!(all_formatted_abstracts, formatted_abstracts)
            push!(mesh_descriptor_list, string(mesh_descriptor))
        end
        
        # Combine all abstracts into single prompt
        combined_abstracts = join(all_formatted_abstracts, "\n\n")
        mesh_descriptors_text = join(mesh_descriptor_list, ", ")
        
        println("  🔍 Combined abstracts from $(length(mesh_batches)) MeSH descriptors")
        println("  📝 Total abstract sections: $(length(all_formatted_abstracts))")
        
        # Create single prompt with all abstracts
        combined_prompt = replace(prompt_template, "{DRUG_NAME}" => drug_name)
        combined_prompt = replace(combined_prompt, "{NUMBER_OF_ABSTRACTS}" => string(total_selected))
        combined_prompt = replace(combined_prompt, "{FORMATTED_ABSTRACTS}" => combined_abstracts)
        
        # Single API call for entire drug
        println("  🚀 Making single API call for all MeSH contexts...")
        response = query_llama(combined_prompt)
        
        if response === nothing
            println("  ❌ No response from Llama")
            return nothing
        end
        
        # DEBUG: Print actual response
        println("  🔍 DEBUG - Llama response preview (first 500 chars):")
        println("  " * first(response, min(500, length(response))))
        println("  ...")
        
        # Parse combined response
        all_indications = parse_llama_response(response, "combined_mesh")
        
        # DEBUG: Print parsing results
        println("  🔍 DEBUG - Parsed $(length(all_indications)) indications")
        
        # Create simplified summary (without listing all MeSH descriptors)
        all_mesh_summaries = MeshAnalysisSummary[]
        if !isempty(all_indications)
            indication_names = [ind.indication for ind in all_indications]
            max_conf = maximum([ind.confidence for ind in all_indications])
            
            summary = MeshAnalysisSummary(
                "$(length(mesh_batches)) MeSH descriptors analyzed",
                total_selected,
                indication_names,
                max_conf
            )
            push!(all_mesh_summaries, summary)
        end
        
        return all_indications, all_mesh_summaries, total_selected, response
        
    catch e
        println("❌ Error processing $drug_name: $e")
        return nothing
    end
end

function main()
    """Main processing function"""
    
    if length(ARGS) < 2
        println("Usage: julia phase2_step4_pubmed_llama_extractor.jl <start_index> <batch_size>")
        println("Example: julia phase2_step4_pubmed_llama_extractor.jl 1 100")
        exit(1)
    end
    
    start_index = parse(Int, ARGS[1])
    batch_size = parse(Int, ARGS[2])
    
    # Test Ollama connection
    if !test_ollama_connection()
        println("❌ Exiting due to Ollama connection failure")
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
    
    # Calculate batch range
    end_index = min(start_index + batch_size - 1, length(all_drugs))
    batch_drugs = all_drugs[start_index:end_index]
    
    println("=== Phase 2 Step 4: MeSH-Guided PubMed Llama Extraction ===")
    println("📊 Total drugs available: $(length(all_drugs))")
    println("🎯 Processing batch: $start_index to $end_index ($(length(batch_drugs)) drugs)")
    println("🤖 Model: $MODEL_NAME")
    println("📁 Output directory: $OUTPUT_DIR")
    println("Start time: $(now())")
    
    start_time = time()
    processed_count = 0
    failed_count = 0
    
    for (drug_idx, drug_name) in enumerate(batch_drugs)
        println("\\n[$drug_idx/$(length(batch_drugs))] Processing: $drug_name")
        
        # Check if already processed
        output_file = joinpath(OUTPUT_DIR, "$(sanitize_filename(drug_name))_pubmed_llama_indications.json")
        if isfile(output_file)
            println("  ⏭️  Already processed, skipping")
            continue
        end
        
        drug_start_time = time()
        result = process_drug_mesh_guided(drug_name, prompt_template)
        
        if result !== nothing
            indications, mesh_summaries, total_pubs_analyzed, raw_response = result
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
                    "approach" => "mesh_guided_pubmed_llama",
                    "confidence_threshold" => CONFIDENCE_THRESHOLD
                ),
                "raw_llama_response" => raw_response,
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
    
    println("\\n=== BATCH PROCESSING COMPLETE ===")
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