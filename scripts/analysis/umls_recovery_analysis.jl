#!/usr/bin/env julia

"""
UMLS-based ICD-10 Recovery Analysis

Comprehensive analysis using proper UMLS hierarchical mapping to evaluate:
- MeSH extraction vs DrugBank
- Naive LLM extraction vs DrugBank  
- PubMed LLM extraction vs DrugBank

Evaluates recovery at both:
- Specific ICD-10 code level
- ICD-10 chapter level
"""

using JSON3
using CSV
using DataFrames

# Include the UMLS hierarchical mapper
include("umls_icd10_hierarchical_mapper.jl")

function extract_icd10_chapter(code::String)
    """Extract ICD-10 chapter from specific code"""
    if isempty(code)
        return ""
    end
    
    # ICD-10 chapters are typically first 3 characters, or 2 for some ranges
    if length(code) >= 3
        return code[1:3]
    elseif length(code) >= 2
        return code[1:2]
    else
        return code
    end
end

function map_drugbank_to_icd10(indication_text::String)
    """Map DrugBank indication text to ICD-10 codes using UMLS"""
    
    # Split indication into component terms
    terms = []
    
    # Split by common separators
    raw_terms = split(indication_text, r"[;,\.\(\)]")
    
    for term in raw_terms
        cleaned = strip(term)
        if !isempty(cleaned) && length(cleaned) > 3
            push!(terms, cleaned)
        end
    end
    
    # Also try the full indication text
    push!(terms, indication_text)
    
    all_codes = Set{String}()
    all_chapters = Set{String}()
    
    for term in terms
        mappings = map_to_icd10_hierarchical(String(term))
        
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

function load_mesh_icd10_mappings(drug_name::String)
    """Load MeSH mappings and convert to ICD-10 using UMLS"""
    mesh_file = "../../drug_pubmed_refs/$(drug_name).json"
    
    if !isfile(mesh_file)
        return Set{String}(), Set{String}()
    end
    
    try
        # Load T047 disease headings
        if !@isdefined(MESH_T047_HEADINGS)
            include("../../mesh_t047_headings.jl")
        end
        
        data = JSON3.read(read(mesh_file, String))
        
        # Handle different file structures
        pubs = if haskey(data, :result) && haskey(data.result, :publications_analyzed)
            data.result.publications_analyzed
        elseif haskey(data, :publications_analyzed)
            data.publications_analyzed
        else
            []
        end
        
        # Extract disease MeSH descriptors
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
        
        # Map each descriptor to ICD-10 using UMLS
        all_codes = Set{String}()
        all_chapters = Set{String}()
        
        for descriptor in disease_descriptors
            mappings = map_to_icd10_hierarchical(String(descriptor))
            
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

function load_naive_llm_icd10_mappings(drug_name::String)
    """Load Naive LLM mappings and convert to ICD-10 using UMLS"""
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
                    mappings = map_to_icd10_hierarchical(String(condition))
                    
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

function load_pubmed_llm_icd10_mappings(drug_name::String)
    """Load PubMed LLM mappings and convert to ICD-10 using UMLS"""
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
                    mappings = map_to_icd10_hierarchical(String(disease))
                    
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
    
    # Code-level recovery
    code_overlap = intersect(extracted_codes, drugbank_codes)
    code_recovery = length(code_overlap) / length(drugbank_codes) * 100
    
    # Chapter-level recovery
    chapter_overlap = intersect(extracted_chapters, drugbank_chapters)
    chapter_recovery = length(chapter_overlap) / length(drugbank_chapters) * 100
    
    return code_recovery, chapter_recovery
end

function main()
    println("🔬 UMLS-based ICD-10 Recovery Analysis")
    println("=" ^ 70)
    println("Using UMLS 2025AA hierarchical mapping")
    
    # Load UMLS data
    println("📚 Loading UMLS data...")
    load_umls_data()
    
    # Load approved drugs
    include("../../approved_drugs_dict.jl")
    
    results = []
    processed_count = 0
    successful_mappings = 0
    
    println("\n🔍 Processing drugs...")
    
    for (drug_name, indication) in APPROVED_DRUGS_DICT
        processed_count += 1
        
        if processed_count % 50 == 0
            println("  Processed $processed_count drugs...")
        end
        
        # Map DrugBank indication to ICD-10 using UMLS
        drugbank_codes, drugbank_chapters = map_drugbank_to_icd10(indication)
        
        # Skip drugs with no identifiable conditions
        if isempty(drugbank_codes) || isempty(drugbank_chapters)
            continue
        end
        
        successful_mappings += 1
        
        # Load extraction results and map to ICD-10
        mesh_codes, mesh_chapters = load_mesh_icd10_mappings(drug_name)
        naive_codes, naive_chapters = load_naive_llm_icd10_mappings(drug_name)
        pubmed_codes, pubmed_chapters = load_pubmed_llm_icd10_mappings(drug_name)
        
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
    
    # Add percentage signs for display
    for col in [:mesh_icd10_code, :naive_icd10_code, :pubmed_icd10_code, 
                :mesh_icd10_chapter, :naive_icd10_chapter, :pubmed_icd10_chapter]
        display_df[!, col] = string.(display_df[!, col]) .* "%"
    end
    
    # Save results
    output_file = "../../umls_icd10_recovery_analysis.csv"
    CSV.write(output_file, display_df)
    
    println("\n✅ UMLS Recovery Analysis Complete!")
    println("📊 Processed $processed_count total drugs")
    println("🎯 Successfully mapped $successful_mappings drugs with identifiable conditions")
    println("💾 Results saved to: $output_file")
    
    # Calculate summary statistics
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
    
    # Show top performers
    println("\n🏆 Top 10 Drugs by Chapter-level Recovery:")
    sorted_by_chapter = sort(results, by = r -> r["naive_icd10_chapter"] + r["pubmed_icd10_chapter"], rev=true)
    for (i, result) in enumerate(sorted_by_chapter[1:min(10, length(sorted_by_chapter))])
        println("  $i. $(result["drug_name"]):")
        println("     MeSH=$(result["mesh_icd10_chapter"])%, Naive=$(result["naive_icd10_chapter"])%, PubMed=$(result["pubmed_icd10_chapter"])%")
    end
    
    # Show sample results
    println("\n📋 Sample Results (first 10 drugs):")
    println(first(display_df, 10))
    
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end