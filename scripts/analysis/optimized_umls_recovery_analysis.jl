#!/usr/bin/env julia

"""
Optimized UMLS-based ICD-10 Recovery Analysis

Truly efficient approach:
1. Look up indication in UMLS API → get CUI(s)
2. Check CUI for ICD-10 codes via API → if found, done!
3. If not, use local hierarchy to find parents
4. Query parent CUIs via API for ICD-10 codes
5. No preloading - everything on-demand
"""

using JSON3
using CSV
using DataFrames
using HTTP

# Load UMLS config
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

# Local hierarchy file (only used for parent lookup)
const MRREL_FILE = "/oscar/data/ursa/umls/2025AA/META/MRREL.RRF"

# Caches for efficiency
HIERARCHY_CACHE = Dict{String, Set{String}}()  # child_cui -> parent_cuis
API_CACHE = Dict{String, Any}()  # API response cache
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

function check_umls_api()
    """Check if UMLS API key is valid"""
    if isempty(UMLS_API_KEY)
        return false
    end
    
    try
        # Test API key with a simple query
        url = "$UMLS_API_BASE/content/current/CUI/C0009044?apiKey=$UMLS_API_KEY"
        response = HTTP.get(url)
        return response.status == 200
    catch e
        println("Warning: UMLS API key validation failed: $e")
        return false
    end
end

function search_umls_concepts(term::String)
    """Search for CUIs using UMLS API"""
    if isempty(UMLS_API_KEY)
        return []
    end
    
    cache_key = "search_$term"
    if haskey(API_CACHE, cache_key)
        return API_CACHE[cache_key]
    end
    
    try
        encoded_term = HTTP.URIs.escapeuri(term)
        url = "$UMLS_API_BASE/search/current?string=$encoded_term&apiKey=$UMLS_API_KEY"
        
        response = HTTP.get(url)
        
        # Rate limiting - be respectful to UMLS API
        sleep(0.1)
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            
            results = []
            if haskey(data, "result") && haskey(data.result, "results")
                for result in data.result.results
                    push!(results, (
                        cui = result.ui,
                        name = result.name,
                        score = parse(Float64, get(result, "score", "1.0"))
                    ))
                end
            end
            
            # Cache and return top 3 results
            top_results = results[1:min(3, length(results))]
            API_CACHE[cache_key] = top_results
            return top_results
        end
    catch e
        println("Warning: UMLS API search failed for '$term': $e")
    end
    
    return []
end

function get_cui_details(cui::String)
    """Get CUI details including ICD-10 codes from UMLS API"""
    if isempty(UMLS_API_KEY)
        return Dict(), []
    end
    
    cache_key = "cui_$cui"
    if haskey(API_CACHE, cache_key)
        return API_CACHE[cache_key]
    end
    
    try
        # Get CUI atoms to find ICD-10 codes
        url = "$UMLS_API_BASE/content/current/CUI/$cui/atoms?apiKey=$UMLS_API_KEY"
        
        response = HTTP.get(url)
        
        # Rate limiting - be respectful to UMLS API
        sleep(0.1)
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            
            cui_info = Dict(
                "cui" => cui,
                "preferred_name" => ""
            )
            
            icd10_codes = []
            
            if haskey(data, "result")
                for atom in data.result
                    # Get preferred name
                    if get(atom, "termType", "") == "PT"
                        cui_info["preferred_name"] = get(atom, "name", "")
                    end
                    
                    # Check for ICD-10 codes
                    root_source = get(atom, "rootSource", "")
                    if root_source in ["ICD10", "ICD10CM", "ICD10AM", "ICD10AMAE"]
                        code = get(atom, "code", "")
                        if !isempty(code)
                            # Extract actual ICD-10 code from URL if needed
                            actual_code = if occursin("/", code)
                                split(code, "/")[end]  # Get last part after final /
                            else
                                code
                            end
                            push!(icd10_codes, (source=root_source, code=actual_code))
                        end
                    end
                end
            end
            
            result = (cui_info, icd10_codes)
            API_CACHE[cache_key] = result
            return result
        end
    catch e
        println("Warning: Failed to get CUI details for $cui: $e")
    end
    
    return Dict(), []
end

function load_hierarchy_for_cui(cui::String)
    """Load parent CUIs for a specific CUI from local hierarchy file"""
    global HIERARCHY_CACHE
    
    if haskey(HIERARCHY_CACHE, cui)
        return HIERARCHY_CACHE[cui]
    end
    
    parents = Set{String}()
    
    if isfile(MRREL_FILE)
        # Only read relationships for this specific CUI
        open(MRREL_FILE, "r") do file
            for line in eachline(file)
                fields = split(line, '|')
                if length(fields) >= 15
                    cui1 = fields[1]
                    rel = fields[4]
                    cui2 = fields[5]
                    suppress = fields[15]
                    
                    # cui1 has parent cui2
                    if cui1 == cui && rel == "PAR" && suppress != "Y"
                        push!(parents, cui2)
                    end
                end
            end
        end
    end
    
    HIERARCHY_CACHE[cui] = parents
    return parents
end

function find_icd10_via_hierarchy(cui::String, max_depth::Int=3)
    """Find ICD-10 codes by traversing up hierarchy using API + local files"""
    
    visited = Set{String}()
    queue = [(cui, 0)]
    
    while !isempty(queue)
        current_cui, depth = popfirst!(queue)
        
        if current_cui in visited || depth > max_depth
            continue
        end
        
        push!(visited, current_cui)
        
        # Check current CUI for ICD-10 codes via API
        cui_info, icd10_codes = get_cui_details(current_cui)
        
        if !isempty(icd10_codes)
            return cui_info, icd10_codes, depth
        end
        
        # Get parents from local hierarchy file
        parents = load_hierarchy_for_cui(current_cui)
        
        # Add parents to queue for next level
        for parent_cui in parents
            if parent_cui ∉ visited
                push!(queue, (parent_cui, depth + 1))
            end
        end
    end
    
    return Dict(), [], -1
end

function map_to_icd10_optimized(indication::String)
    """Map indication to ICD-10 using optimized API + hierarchy approach"""
    
    # Step 1: Search for CUIs
    search_results = search_umls_concepts(indication)
    
    if isempty(search_results)
        return ICD10Mapping[]
    end
    
    mappings = ICD10Mapping[]
    
    # Step 2: For each CUI, check for ICD-10 codes (direct or via hierarchy)
    for result in search_results
        cui = result.cui
        name = result.name
        confidence = result.score
        
        # Check direct ICD-10 mapping first
        cui_info, icd10_codes = get_cui_details(cui)
        
        if !isempty(icd10_codes)
            # Direct mapping found
            for (source, code) in icd10_codes
                push!(mappings, ICD10Mapping(
                    indication,
                    cui,
                    name,
                    code,
                    source,
                    "direct",
                    confidence,
                    0
                ))
            end
        else
            # No direct mapping, try hierarchy
            parent_info, parent_icd10_codes, hierarchy_level = find_icd10_via_hierarchy(cui)
            
            if !isempty(parent_icd10_codes)
                method = "parent_L$hierarchy_level"
                parent_name = get(parent_info, "preferred_name", name)
                
                for (source, code) in parent_icd10_codes
                    push!(mappings, ICD10Mapping(
                        indication,
                        get(parent_info, "cui", cui),
                        parent_name,
                        code,
                        source,
                        method,
                        confidence * 0.9,  # Slightly lower confidence for hierarchy
                        hierarchy_level
                    ))
                end
            end
        end
        
        # Use first successful mapping (most confident)
        if !isempty(mappings)
            break
        end
    end
    
    return mappings
end

function load_drugbank_llm_icd10_mappings_optimized(drug_name::String)
    """Load DrugBank LLM extracted indications and convert to ICD-10 (ground truth)"""
    drugbank_file = "../../llama_drugbank_extracted_indications/$(replace(drug_name, " " => "_"))_drugbank_extracted_indications.json"
    
    if !isfile(drugbank_file)
        return Set{String}(), Set{String}()
    end
    
    try
        data = JSON3.read(read(drugbank_file, String))
        
        if haskey(data, "indications")
            confirmed_indications = filter(ind -> get(ind, "confirmed", false), data["indications"])
            
            all_codes = Set{String}()
            all_chapters = Set{String}()
            
            for indication in confirmed_indications
                condition = get(indication, "condition", "")
                if !isempty(condition)
                    mappings = map_to_icd10_optimized(String(condition))
                    
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
        println("Warning: Error processing DrugBank LLM data for $drug_name: $e")
    end
    
    return Set{String}(), Set{String}()
end

# Simplified extraction functions using same approach
function load_mesh_icd10_mappings_optimized(drug_name::String)
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
            mappings = map_to_icd10_optimized(String(descriptor))
            
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

function load_naive_llm_icd10_mappings_optimized(drug_name::String)
    naive_file = "../../llama_naive_extracted_indications/$(replace(drug_name, " " => "_"))_naive_extracted_indications.json"
    
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
                    mappings = map_to_icd10_optimized(String(condition))
                    
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

function load_pubmed_llm_icd10_mappings_optimized(drug_name::String)
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
                    mappings = map_to_icd10_optimized(String(disease))
                    
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
    println("⚡ Optimized UMLS-based ICD-10 Recovery Analysis")
    println("=" ^ 70)
    println("Using on-demand API + hierarchy approach (no preloading)")
    
    # Check UMLS API access
    println("🔑 Checking UMLS API authentication...")
    api_available = check_umls_api()
    
    if !api_available
        println("❌ No UMLS API access - cannot proceed with optimized approach")
        return []
    else
        println("✅ UMLS API authenticated")
    end
    
    # Load approved drugs
    include("../../approved_drugs_dict.jl")
    
    results = []
    processed_count = 0
    successful_mappings = 0
    
    println("\n🔍 Processing drugs with on-demand UMLS lookups...")
    
    # Test with just first 3 drugs for now
    test_count = 0
    for (drug_name, indication) in APPROVED_DRUGS_DICT
        test_count += 1
        if test_count > 3
            break
        end
        processed_count += 1
        
        if processed_count % 50 == 0
            println("  Processed $processed_count drugs...")
        end
        
        # Load DrugBank LLM extracted indications as ground truth
        drugbank_codes, drugbank_chapters = load_drugbank_llm_icd10_mappings_optimized(drug_name)
        
        # Skip drugs with no identifiable conditions
        if isempty(drugbank_codes) || isempty(drugbank_chapters)
            continue
        end
        
        successful_mappings += 1
        
        # Load extraction results and map to ICD-10
        mesh_codes, mesh_chapters = load_mesh_icd10_mappings_optimized(drug_name)
        naive_codes, naive_chapters = load_naive_llm_icd10_mappings_optimized(drug_name)
        pubmed_codes, pubmed_chapters = load_pubmed_llm_icd10_mappings_optimized(drug_name)
        
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
        
        # Test with first few drugs and show progress
        if processed_count <= 5
            println("  ✓ $drug_name: DB=$(length(drugbank_codes)) codes, MeSH=$mesh_code_recovery%, Naive=$naive_code_recovery%, PubMed=$pubmed_code_recovery%")
        end
    end
    
    if isempty(results)
        println("❌ No successful mappings found")
        return []
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
    output_file = "../../optimized_umls_icd10_recovery_analysis.csv"
    CSV.write(output_file, display_df)
    
    println("\n✅ Optimized UMLS Recovery Analysis Complete!")
    println("📊 Processed $processed_count total drugs")
    println("🎯 Successfully mapped $successful_mappings drugs with identifiable conditions")
    println("💾 Results saved to: $output_file")
    
    # Summary statistics
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
    println("\n📋 Sample Results:")
    println(first(display_df, min(10, size(display_df, 1))))
    
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end