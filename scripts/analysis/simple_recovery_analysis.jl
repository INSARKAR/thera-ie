#!/usr/bin/env julia

"""
Simple Recovery Analysis using existing extraction results
Skip UMLS mapping for now - just compare extracted conditions directly
"""

using JSON3
using CSV
using DataFrames

function extract_conditions_from_file(file_path::String, data_type::String)
    """Extract condition names from extraction files"""
    
    if !isfile(file_path)
        return Set{String}()
    end
    
    try
        data = JSON3.read(read(file_path, String))
        conditions = Set{String}()
        
        if data_type == "drugbank"
            if haskey(data, "indications")
                confirmed_indications = filter(ind -> get(ind, "confirmed", false), data["indications"])
                for indication in confirmed_indications
                    condition = get(indication, "condition", "")
                    if !isempty(condition)
                        push!(conditions, lowercase(strip(condition)))
                    end
                end
            end
        elseif data_type == "naive"
            if haskey(data, "indications")
                confirmed_indications = filter(ind -> get(ind, "confirmed", false), data["indications"])
                for indication in confirmed_indications
                    condition = get(indication, "condition", "")
                    if !isempty(condition)
                        push!(conditions, lowercase(strip(condition)))
                    end
                end
            end
        elseif data_type == "pubmed"
            if haskey(data, "disease_pairs")
                confirmed_pairs = filter(pair -> get(pair, "confirmed", false), data["disease_pairs"])
                for pair in confirmed_pairs
                    disease = get(pair, "disease", "")
                    if !isempty(disease)
                        push!(conditions, lowercase(strip(disease)))
                    end
                end
            end
        elseif data_type == "mesh"
            # Load T047 disease headings
            if !@isdefined(MESH_T047_HEADINGS)
                include("../../mesh_t047_headings.jl")
            end
            
            pubs = if haskey(data, :result) && haskey(data.result, :publications_analyzed)
                data.result.publications_analyzed
            elseif haskey(data, :publications_analyzed)
                data.publications_analyzed
            else
                []
            end
            
            for pub in pubs
                if haskey(pub, "mesh_descriptors") && !isempty(pub["mesh_descriptors"])
                    for mesh_obj in pub["mesh_descriptors"]
                        descriptor_name = String(mesh_obj["descriptor"])
                        if descriptor_name in MESH_T047_HEADINGS
                            push!(conditions, lowercase(strip(descriptor_name)))
                        end
                    end
                end
            end
        end
        
        return conditions
        
    catch e
        println("Warning: Error processing $file_path: $e")
        return Set{String}()
    end
end

function calculate_condition_overlap(method_conditions, drugbank_conditions)
    """Calculate overlap between extracted conditions (text-based)"""
    
    if isempty(drugbank_conditions)
        return 0.0
    end
    
    # Direct exact matches
    exact_overlap = intersect(method_conditions, drugbank_conditions)
    exact_recovery = length(exact_overlap) / length(drugbank_conditions) * 100
    
    # Fuzzy matches (partial string matching)
    fuzzy_matches = 0
    for db_condition in drugbank_conditions
        for method_condition in method_conditions
            # Check if either contains the other (partial match)
            if occursin(db_condition, method_condition) || occursin(method_condition, db_condition)
                fuzzy_matches += 1
                break
            end
        end
    end
    
    fuzzy_recovery = fuzzy_matches / length(drugbank_conditions) * 100
    
    return exact_recovery, fuzzy_recovery
end

function main()
    println("📊 Simple Recovery Analysis (Text-based Condition Matching)")
    println("=" ^ 70)
    
    # Load approved drugs
    include("../../approved_drugs_dict.jl")
    
    results = []
    processed_count = 0
    successful_mappings = 0
    
    println("\n🔍 Processing extraction files...")
    
    for (drug_name, indication) in APPROVED_DRUGS_DICT
        processed_count += 1
        
        if processed_count > 50  # Limit for testing
            break
        end
        
        if processed_count % 10 == 0
            println("  Processed $processed_count drugs...")
        end
        
        # Load DrugBank LLM extractions (ground truth)
        drugbank_file = "llama_drugbank_extracted_indications/$(replace(drug_name, " " => "_"))_drugbank_extracted_indications.json"
        drugbank_conditions = extract_conditions_from_file(drugbank_file, "drugbank")
        
        # Skip drugs with no drugbank extractions
        if isempty(drugbank_conditions)
            continue
        end
        
        successful_mappings += 1
        
        # Load other method extractions
        mesh_file = "phase1_drug_pubmed_refs/$(drug_name).json"
        mesh_conditions = extract_conditions_from_file(mesh_file, "mesh")
        
        naive_file = "llama_naive_extracted_indications/$(replace(drug_name, " " => "_"))_naive_extracted_indications.json"
        naive_conditions = extract_conditions_from_file(naive_file, "naive")
        
        pubmed_file = "llama_pubmed_extracted_indications/$(replace(drug_name, " " => "_"))_llama_extracted_indications.json"
        pubmed_conditions = extract_conditions_from_file(pubmed_file, "pubmed")
        
        # Calculate overlaps
        mesh_exact, mesh_fuzzy = calculate_condition_overlap(mesh_conditions, drugbank_conditions)
        naive_exact, naive_fuzzy = calculate_condition_overlap(naive_conditions, drugbank_conditions)
        pubmed_exact, pubmed_fuzzy = calculate_condition_overlap(pubmed_conditions, drugbank_conditions)
        
        # Store results
        push!(results, Dict(
            "drug_name" => drug_name,
            "drugbank_conditions" => length(drugbank_conditions),
            "mesh_exact" => round(mesh_exact, digits=1),
            "mesh_fuzzy" => round(mesh_fuzzy, digits=1),
            "naive_exact" => round(naive_exact, digits=1),
            "naive_fuzzy" => round(naive_fuzzy, digits=1),
            "pubmed_exact" => round(pubmed_exact, digits=1),
            "pubmed_fuzzy" => round(pubmed_fuzzy, digits=1),
            "mesh_conditions" => length(mesh_conditions),
            "naive_conditions" => length(naive_conditions),
            "pubmed_conditions" => length(pubmed_conditions)
        ))
        
        # Show progress for first few drugs
        if processed_count <= 5
            println("  ✓ $drug_name: DB=$(length(drugbank_conditions)), MeSH=$mesh_exact%/$mesh_fuzzy%, Naive=$naive_exact%/$naive_fuzzy%, PubMed=$pubmed_exact%/$pubmed_fuzzy%")
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
        :drugbank_conditions,
        :mesh_exact, :mesh_fuzzy,
        :naive_exact, :naive_fuzzy,
        :pubmed_exact, :pubmed_fuzzy
    ])
    
    # Add percentage signs
    for col in [:mesh_exact, :mesh_fuzzy, :naive_exact, :naive_fuzzy, :pubmed_exact, :pubmed_fuzzy]
        display_df[!, col] = string.(display_df[!, col]) .* "%"
    end
    
    # Save results
    output_file = "simple_condition_recovery_analysis.csv"
    CSV.write(output_file, display_df)
    
    println("\n✅ Simple Recovery Analysis Complete!")
    println("📊 Processed $processed_count total drugs")
    println("🎯 Successfully analyzed $successful_mappings drugs with DrugBank extractions")
    println("💾 Results saved to: $output_file")
    
    # Summary statistics
    if !isempty(results)
        println("\n📈 Summary Statistics (Exact/Fuzzy Recovery):")
        
        for method in ["mesh", "naive", "pubmed"]
            exact_col = Symbol("$(method)_exact")
            fuzzy_col = Symbol("$(method)_fuzzy")
            
            exact_values = [r[string(exact_col)] for r in results]
            fuzzy_values = [r[string(fuzzy_col)] for r in results]
            
            exact_mean = round(sum(exact_values) / length(exact_values), digits=1)
            fuzzy_mean = round(sum(fuzzy_values) / length(fuzzy_values), digits=1)
            
            exact_nonzero = count(v -> v > 0, exact_values)
            fuzzy_nonzero = count(v -> v > 0, fuzzy_values)
            
            println("  $(uppercase(method)): Exact=$(exact_mean)% ($(exact_nonzero)/$successful_mappings), Fuzzy=$(fuzzy_mean)% ($(fuzzy_nonzero)/$successful_mappings)")
        end
        
        # Show sample results
        println("\n📋 Sample Results:")
        println(first(display_df, min(10, size(display_df, 1))))
    end
    
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end