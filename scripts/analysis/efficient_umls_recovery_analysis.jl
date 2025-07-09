#!/usr/bin/env julia

"""
Efficient UMLS-based ICD-10 Recovery Analysis

Uses UMLS API for term search, then local files for hierarchy navigation.
Much faster than loading entire UMLS database into memory.
"""

using JSON3
using CSV
using DataFrames
using HTTP

# UMLS API Configuration
function load_umls_config()
    config_file = "../../config/umls_config.json"
    if isfile(config_file)
        config = JSON3.read(read(config_file, String))
        return config.umls_api_key, config.umls_api_base
    else
        return "", "https://uts-ws.nlm.nih.gov/rest"
    end
end

const UMLS_API_KEY, UMLS_API_BASE = load_umls_config()

# Local UMLS files for hierarchy
const UMLS_META_DIR = "/oscar/data/ursa/umls/2025AA/META"
const MRCONSO_FILE = joinpath(UMLS_META_DIR, "MRCONSO.RRF")
const MRREL_FILE = joinpath(UMLS_META_DIR, "MRREL.RRF")

# ICD-10 vocabularies
const ICD10_SOURCES = ["ICD10", "ICD10CM", "ICD10AM", "ICD10AMAE"]

# Caches for performance
CUI_TO_ICD10_CACHE = Dict{String, Dict{String, String}}()
HIERARCHY_CACHE = Dict{String, Set{String}}()
LOADED_HIERARCHY = false

struct ICD10Mapping
    original_term::String
    cui::String
    preferred_name::String
    icd10_code::String
    icd10_source::String
    mapping_method::String
    confidence::Float64
    hierarchy_level::Int
end

function extract_icd10_chapter(code::String)
    """Extract ICD-10 chapter from specific code"""
    if isempty(code)
        return ""
    end
    
    if length(code) >= 3
        return code[1:3]
    elseif length(code) >= 2
        return code[1:2]
    else
        return code
    end
end

function get_umls_ticket()
    """Get authentication ticket for UMLS API"""
    if isempty(UMLS_API_KEY)
        return ""
    end
    
    try
        response = HTTP.post("$UMLS_API_BASE/authentication",
            body = "username=$UMLS_API_KEY",
            headers = ["Content-Type" => "application/x-www-form-urlencoded"]
        )
        
        if response.status == 201
            return String(response.body)
        end
    catch e
        println("Warning: Could not get UMLS API ticket: $e")
    end
    
    return ""
end

function search_umls_api(term::String, ticket::String)
    """Search for term using UMLS API"""
    if isempty(ticket)
        return []
    end
    
    try
        encoded_term = HTTP.URIs.escapeuri(term)
        url = "$UMLS_API_BASE/search/current?string=$encoded_term&ticket=$ticket"
        
        response = HTTP.get(url)
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            
            results = []
            if haskey(data, "result") && haskey(data.result, "results")
                for result in data.result.results
                    push!(results, (
                        cui = result.ui,
                        name = result.name,
                        score = get(result, "score", "1.0")
                    ))
                end
            end
            
            return results[1:min(5, length(results))]
        end
    catch e
        println("Warning: UMLS API search failed for '$term': $e")
    end
    
    return []
end

function load_cui_icd10_mappings()
    """Load CUI to ICD-10 mappings from local MRCONSO file"""
    global CUI_TO_ICD10_CACHE
    
    if !isempty(CUI_TO_ICD10_CACHE)
        return
    end
    
    println("  Loading CUI to ICD-10 mappings...")
    
    if !isfile(MRCONSO_FILE)
        println("⚠️  MRCONSO file not found, using fallback approach")
        return
    end
    
    open(MRCONSO_FILE, "r") do file
        for (i, line) in enumerate(eachline(file))
            if i % 1000000 == 0
                println("    Processed $i lines...")
            end
            
            fields = split(line, '|')
            if length(fields) >= 15
                cui = fields[1]
                source = fields[12]
                code = fields[14]
                suppress = fields[17]
                
                # Only process ICD-10 codes that are not suppressed
                if source in ICD10_SOURCES && suppress != "Y"
                    if !haskey(CUI_TO_ICD10_CACHE, cui)
                        CUI_TO_ICD10_CACHE[cui] = Dict{String, String}()
                    end
                    CUI_TO_ICD10_CACHE[cui][source] = code
                end
            end
        end
    end
    
    println("    Loaded ICD-10 mappings for $(length(CUI_TO_ICD10_CACHE)) CUIs")
end

function load_hierarchy_cache()
    """Load parent-child relationships for hierarchy traversal"""
    global HIERARCHY_CACHE, LOADED_HIERARCHY
    
    if LOADED_HIERARCHY
        return
    end
    
    println("  Loading UMLS hierarchy...")
    
    if !isfile(MRREL_FILE)
        println("⚠️  MRREL file not found, skipping hierarchy")
        LOADED_HIERARCHY = true
        return
    end
    
    open(MRREL_FILE, "r") do file
        for (i, line) in enumerate(eachline(file))
            if i % 500000 == 0
                println("    Processed $i relationship lines...")
            end
            
            fields = split(line, '|')
            if length(fields) >= 15
                cui1 = fields[1]
                rel = fields[4]
                cui2 = fields[5]
                suppress = fields[15]
                
                # Only process parent relationships that are not suppressed
                if rel == "PAR" && suppress != "Y"
                    # cui2 is parent of cui1
                    if !haskey(HIERARCHY_CACHE, cui1)
                        HIERARCHY_CACHE[cui1] = Set{String}()
                    end
                    push!(HIERARCHY_CACHE[cui1], cui2)
                end
            end
        end
    end
    
    println("    Loaded hierarchy for $(length(HIERARCHY_CACHE)) concepts")
    LOADED_HIERARCHY = true
end

function find_icd10_in_hierarchy(cui::String, max_depth::Int=3)
    """Find ICD-10 codes by traversing up the hierarchy"""
    
    # Check direct mapping first
    if haskey(CUI_TO_ICD10_CACHE, cui)
        return CUI_TO_ICD10_CACHE[cui], 0
    end
    
    # Traverse hierarchy
    visited = Set{String}()
    queue = [(cui, 0)]
    
    while !isempty(queue)
        current_cui, depth = popfirst!(queue)
        
        if current_cui in visited || depth >= max_depth
            continue
        end
        
        push!(visited, current_cui)
        
        # Check if current CUI has ICD-10 mapping
        if haskey(CUI_TO_ICD10_CACHE, current_cui)
            return CUI_TO_ICD10_CACHE[current_cui], depth
        end
        
        # Add parents to queue
        if haskey(HIERARCHY_CACHE, current_cui)
            for parent_cui in HIERARCHY_CACHE[current_cui]
                if parent_cui ∉ visited
                    push!(queue, (parent_cui, depth + 1))
                end
            end
        end
    end
    
    return Dict{String, String}(), -1
end

function map_to_icd10_efficient(indication::String, ticket::String)
    """Map indication to ICD-10 using efficient API + local approach"""
    
    # Search using UMLS API
    search_results = search_umls_api(indication, ticket)
    
    if isempty(search_results)
        return ICD10Mapping[]
    end
    
    mappings = ICD10Mapping[]
    
    for result in search_results
        cui = result.cui
        name = result.name
        confidence = parse(Float64, result.score)
        
        # Find ICD-10 codes in hierarchy
        icd10_codes, hierarchy_level = find_icd10_in_hierarchy(cui)
        
        if !isempty(icd10_codes)
            method = hierarchy_level == 0 ? "direct" : "parent_L$hierarchy_level"
            
            for (source, code) in icd10_codes
                push!(mappings, ICD10Mapping(
                    indication,
                    cui,
                    name,
                    code,
                    source,
                    method,
                    confidence,
                    hierarchy_level
                ))
            end
            
            # Use first successful mapping
            break
        end
    end
    
    return mappings
end

function map_drugbank_to_icd10_efficient(indication_text::String, ticket::String)
    """Map DrugBank indication text to ICD-10 codes efficiently"""
    
    # Split indication into terms
    terms = []
    raw_terms = split(indication_text, r"[;,\.\(\)]")
    
    for term in raw_terms
        cleaned = strip(term)
        if !isempty(cleaned) && length(cleaned) > 3
            push!(terms, cleaned)
        end
    end
    
    # Also try full indication
    push!(terms, indication_text)
    
    all_codes = Set{String}()
    all_chapters = Set{String}()
    
    for term in terms
        mappings = map_to_icd10_efficient(String(term), ticket)
        
        for mapping in mappings
            if !isempty(mapping.icd10_code)
                push!(all_codes, mapping.icd10_code)
                chapter = extract_icd10_chapter(mapping.icd10_code)
                if !isempty(chapter)
                    push!(all_chapters, chapter)
                end
            end
        end
    end
    
    return all_codes, all_chapters
end

function load_mesh_icd10_mappings_efficient(drug_name::String, ticket::String)
    """Load MeSH mappings and convert to ICD-10 efficiently"""
    mesh_file = "../../drug_pubmed_refs/$(drug_name).json"
    
    if !isfile(mesh_file)
        return Set{String}(), Set{String}()
    end
    
    try
        if !@isdefined(MESH_T047_HEADINGS)
            include("../../mesh_t047_headings.jl")
        end
        
        data = JSON3.read(read(mesh_file, String))
        
        pubs = if haskey(data, :result) && haskey(data.result, :publications_analyzed)
            data.result.publications_analyzed
        elseif haskey(data, :publications_analyzed)
            data.publications_analyzed
        else
            []
        end
        
        disease_descriptors = Set{String}()
        for pub in pubs
            if haskey(pub, "mesh_descriptors") && !isempty(pub["mesh_descriptors"])
                for mesh_obj in pub["mesh_descriptors"]
                    descriptor_name = String(mesh_obj["descriptor"])
                    if descriptor_name in MESH_T047_HEADINGS
                        push!(disease_descriptors, descriptor_name)
                    end
                end
            end
        end
        
        all_codes = Set{String}()
        all_chapters = Set{String}()
        
        for descriptor in disease_descriptors
            mappings = map_to_icd10_efficient(String(descriptor), ticket)
            
            for mapping in mappings
                if !isempty(mapping.icd10_code)
                    push!(all_codes, mapping.icd10_code)
                    chapter = extract_icd10_chapter(mapping.icd10_code)
                    if !isempty(chapter)
                        push!(all_chapters, chapter)
                    end
                end
            end
        end
        
        return all_codes, all_chapters
        
    catch e
        println("Warning: Error processing MeSH data for $drug_name: $e")
        return Set{String}(), Set{String}()
    end
end

function load_naive_llm_icd10_mappings_efficient(drug_name::String, ticket::String)
    """Load Naive LLM mappings and convert to ICD-10 efficiently"""
    naive_file = "../../llama_naive_extracted_indications/$(replace(drug_name, " " => "_"))_enhanced_naive_extracted_indications.json"
    
    if !isfile(naive_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(naive_file, String))
        
        if haskey(data, "indications")
            confirmed_indications = filter(ind -> get(ind, "confirmed", false), data["indications"])
            
            all_codes = Set{String}()
            all_chapters = Set{String}()
            
            for indication in confirmed_indications
                condition = get(indication, "condition", "")
                if !isempty(condition)
                    mappings = map_to_icd10_efficient(String(condition), ticket)
                    
                    for mapping in mappings
                        if !isempty(mapping.icd10_code)
                            push!(all_codes, mapping.icd10_code)
                            chapter = extract_icd10_chapter(mapping.icd10_code)
                            if !isempty(chapter)
                                push!(all_chapters, chapter)
                            end
                        end
                    end
                end
            end
            
            return all_codes, all_chapters
        end
    catch e
        println("Warning: Error processing naive LLM data for $drug_name: $e")
    end
    
    return Set{String}(), Set{String}()
end

function load_pubmed_llm_icd10_mappings_efficient(drug_name::String, ticket::String)
    """Load PubMed LLM mappings and convert to ICD-10 efficiently"""
    pubmed_file = "../../llama_pubmed_extracted_indications/$(replace(drug_name, " " => "_"))_llama_extracted_indications.json"
    
    if !isfile(pubmed_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(pubmed_file, String))
        
        if haskey(data, "disease_pairs")
            confirmed_pairs = filter(pair -> get(pair, "confirmed", false), data["disease_pairs"])
            
            all_codes = Set{String}()
            all_chapters = Set{String}()
            
            for pair in confirmed_pairs
                disease = get(pair, "disease", "")
                if !isempty(disease)
                    mappings = map_to_icd10_efficient(String(disease), ticket)
                    
                    for mapping in mappings
                        if !isempty(mapping.icd10_code)
                            push!(all_codes, mapping.icd10_code)
                            chapter = extract_icd10_chapter(mapping.icd10_code)
                            if !isempty(chapter)
                                push!(all_chapters, chapter)
                            end
                        end
                    end
                end
            end
            
            return all_codes, all_chapters
        end
    catch e
        println("Warning: Error processing PubMed LLM data for $drug_name: $e")
    end
    
    return Set{String}(), Set{String}()
end

function calculate_recovery_rates(extracted_codes, extracted_chapters, drugbank_codes, drugbank_chapters)
    """Calculate recovery rates at both code and chapter levels"""
    
    if isempty(drugbank_codes) || isempty(drugbank_chapters)
        return 0.0, 0.0
    end
    
    code_overlap = intersect(extracted_codes, drugbank_codes)
    code_recovery = length(code_overlap) / length(drugbank_codes) * 100
    
    chapter_overlap = intersect(extracted_chapters, drugbank_chapters)
    chapter_recovery = length(chapter_overlap) / length(drugbank_chapters) * 100
    
    return code_recovery, chapter_recovery
end

function main()
    println("🚀 Efficient UMLS-based ICD-10 Recovery Analysis")
    println("=" ^ 70)
    println("Using UMLS API + local hierarchy approach")
    
    # Get UMLS API ticket
    println("🔑 Getting UMLS API authentication...")
    ticket = get_umls_ticket()
    
    if isempty(ticket)
        println("⚠️  No UMLS API access - will use fallback approach")
    else
        println("✅ UMLS API authenticated")
    end
    
    # Load local UMLS data for hierarchy and ICD mappings
    println("📚 Loading local UMLS data...")
    load_cui_icd10_mappings()
    load_hierarchy_cache()
    
    # Load approved drugs
    include("../../approved_drugs_dict.jl")
    
    results = []
    processed_count = 0
    successful_mappings = 0
    
    println("\n🔍 Processing drugs...")
    
    for (drug_name, indication) in APPROVED_DRUGS_DICT
        processed_count += 1
        
        if processed_count % 10 == 0
            println("  Processed $processed_count drugs...")
        end
        
        # Map DrugBank indication to ICD-10
        drugbank_codes, drugbank_chapters = map_drugbank_to_icd10_efficient(indication, ticket)
        
        # Skip drugs with no identifiable conditions
        if isempty(drugbank_codes) || isempty(drugbank_chapters)
            continue
        end
        
        successful_mappings += 1
        
        # Load extraction results and map to ICD-10
        mesh_codes, mesh_chapters = load_mesh_icd10_mappings_efficient(drug_name, ticket)
        naive_codes, naive_chapters = load_naive_llm_icd10_mappings_efficient(drug_name, ticket)
        pubmed_codes, pubmed_chapters = load_pubmed_llm_icd10_mappings_efficient(drug_name, ticket)
        
        # Calculate recovery rates
        mesh_code_recovery, mesh_chapter_recovery = calculate_recovery_rates(
            mesh_codes, mesh_chapters, drugbank_codes, drugbank_chapters
        )
        
        naive_code_recovery, naive_chapter_recovery = calculate_recovery_rates(
            naive_codes, naive_chapters, drugbank_codes, drugbank_chapters
        )
        
        pubmed_code_recovery, pubmed_chapter_recovery = calculate_recovery_rates(
            pubmed_codes, pubmed_chapters, drugbank_codes, drugbank_chapters
        )
        
        # Store results
        push!(results, Dict(
            "drug_name" => drug_name,
            "mesh_icd10_code" => round(mesh_code_recovery, digits=1),
            "naive_icd10_code" => round(naive_code_recovery, digits=1),
            "pubmed_icd10_code" => round(pubmed_code_recovery, digits=1),
            "mesh_icd10_chapter" => round(mesh_chapter_recovery, digits=1),
            "naive_icd10_chapter" => round(naive_chapter_recovery, digits=1),
            "pubmed_icd10_chapter" => round(pubmed_chapter_recovery, digits=1),
            "drugbank_codes_count" => length(drugbank_codes),
            "drugbank_chapters_count" => length(drugbank_chapters)
        ))
    end
    
    # Create results DataFrame
    df = DataFrame(results)
    
    # Format for display
    display_df = select(df, [
        :drug_name,
        :mesh_icd10_code,
        :naive_icd10_code,
        :pubmed_icd10_code,
        :mesh_icd10_chapter,
        :naive_icd10_chapter,
        :pubmed_icd10_chapter
    ])
    
    # Add percentage signs
    for col in [:mesh_icd10_code, :naive_icd10_code, :pubmed_icd10_code, 
                :mesh_icd10_chapter, :naive_icd10_chapter, :pubmed_icd10_chapter]
        display_df[!, col] = string.(display_df[!, col]) .* "%"
    end
    
    # Save results
    output_file = "../../efficient_umls_icd10_recovery_analysis.csv"
    CSV.write(output_file, display_df)
    
    println("\n✅ Efficient UMLS Recovery Analysis Complete!")
    println("📊 Processed $processed_count total drugs")
    println("🎯 Successfully mapped $successful_mappings drugs with identifiable conditions")
    println("💾 Results saved to: $output_file")
    
    # Summary statistics
    if !isempty(results)
        numeric_cols = [:mesh_icd10_code, :naive_icd10_code, :pubmed_icd10_code, 
                       :mesh_icd10_chapter, :naive_icd10_chapter, :pubmed_icd10_chapter]
        
        println("\n📈 Summary Statistics:")
        for col in numeric_cols
            values = [r[string(col)] for r in results]
            mean_val = round(sum(values) / length(values), digits=1)
            median_val = round(sort(values)[div(length(values), 2)], digits=1)
            max_val = round(maximum(values), digits=1)
            nonzero_count = count(v -> v > 0, values)
            nonzero_percent = round(nonzero_count / length(values) * 100, digits=1)
            
            println("  $col:")
            println("    Mean = $mean_val%, Median = $median_val%, Max = $max_val%")
            println("    Non-zero recovery: $nonzero_count/$successful_mappings ($nonzero_percent%)")
        end
        
        # Show sample results
        println("\n📋 Sample Results (first 10 drugs):")
        println(first(display_df, min(10, size(display_df, 1))))
    end
    
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end