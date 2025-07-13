#!/usr/bin/env julia

"""
Analyze Phase1 Results for Unique Naive Indications

This script processes all phase1_results files to identify indications that are:
1. Found in naive LLM extraction
2. NOT found in PubMed LLM extraction
3. Creates a JSON file with drug-indication pairings for further analysis

Usage: julia analyze_unique_naive_indications.jl
"""

using JSON3
using Dates

function analyze_phase1_files()
    results_dir = "phase1_results"
    output_file = "unique_naive_indications.json"
    
    println("🔍 Analyzing Phase1 results for unique naive indications...")
    println("📁 Results directory: $results_dir")
    
    if !isdir(results_dir)
        error("Results directory not found: $results_dir")
    end
    
    # Get all JSON files
    files = filter(f -> endswith(f, ".json"), readdir(results_dir))
    total_files = length(files)
    
    println("📊 Found $total_files result files")
    
    # Collect unique naive indications
    unique_naive_pairs = Dict{String, Dict}()  # drug_indication_key => metadata
    drugs_processed = 0
    total_naive_indications = 0
    unique_naive_count = 0
    
    for (i, filename) in enumerate(files)
        filepath = joinpath(results_dir, filename)
        
        try
            # Read and parse JSON
            content = JSON3.read(read(filepath, String))
            
            # Extract drug name from metadata
            metadata = get(content, "metadata", Dict())
            drug_name = get(metadata, "drug_name", "unknown")
            if drug_name == "unknown"
                continue
            end
            
            drugs_processed += 1
            
            # Get naive and pubmed indications
            naive_indications = get(content, "naive_indications", [])
            pubmed_indications = get(content, "pubmed_llm_indications", [])
            
            # Extract indication text from each approach
            naive_indication_texts = Set{String}()
            for indication in naive_indications
                if haskey(indication, "original_condition")
                    push!(naive_indication_texts, lowercase(strip(indication["original_condition"])))
                end
            end
            
            pubmed_indication_texts = Set{String}()
            for indication in pubmed_indications
                if haskey(indication, "indication")
                    push!(pubmed_indication_texts, lowercase(strip(indication["indication"])))
                elseif haskey(indication, "original_condition")
                    push!(pubmed_indication_texts, lowercase(strip(indication["original_condition"])))
                end
            end
            
            total_naive_indications += length(naive_indication_texts)
            
            # Find naive indications that are NOT in pubmed results
            unique_naive_for_drug = setdiff(naive_indication_texts, pubmed_indication_texts)
            
            # Store unique naive indications
            for indication_text in unique_naive_for_drug
                key = "$(drug_name)||$(indication_text)"
                
                # Find the original indication object for metadata
                original_indication = nothing
                for indication in naive_indications
                    if haskey(indication, "original_condition") && 
                       lowercase(strip(indication["original_condition"])) == indication_text
                        original_indication = indication
                        break
                    end
                end
                
                unique_naive_pairs[key] = Dict(
                    "drug_name" => drug_name,
                    "indication" => indication_text,
                    "original_indication_data" => original_indication,
                    "found_in_naive" => true,
                    "found_in_pubmed" => false,
                    "source_file" => filename
                )
                
                unique_naive_count += 1
            end
            
            # Progress indicator
            if i % 100 == 0 || i == total_files
                println("  ✓ Processed $i/$total_files files")
            end
            
        catch e
            println("  ⚠️  Error processing $filename: $e")
        end
    end
    
    println("\n📊 Analysis Results:")
    println("  • Drugs processed: $drugs_processed")
    println("  • Total naive indications: $total_naive_indications")
    println("  • Unique naive indications (not in PubMed): $unique_naive_count")
    println("  • Unique drug-indication pairs: $(length(unique_naive_pairs))")
    
    if length(unique_naive_pairs) == 0
        println("⚠️  No unique naive indications found!")
        return
    end
    
    # Organize data for output
    organized_data = Dict(
        "metadata" => Dict(
            "generated_on" => string(now()),
            "description" => "Drug-indication pairs found in naive LLM extraction but NOT in PubMed LLM extraction",
            "total_unique_pairs" => length(unique_naive_pairs),
            "analysis_source" => "phase1_results directory",
            "total_files_processed" => drugs_processed,
            "total_naive_indications" => total_naive_indications
        ),
        "unique_naive_indications" => unique_naive_pairs
    )
    
    # Add summary statistics
    drug_counts = Dict{String, Int}()
    indication_counts = Dict{String, Int}()
    
    for (key, data) in unique_naive_pairs
        drug = data["drug_name"]
        indication = data["indication"]
        
        drug_counts[drug] = get(drug_counts, drug, 0) + 1
        indication_counts[indication] = get(indication_counts, indication, 0) + 1
    end
    
    organized_data["summary_statistics"] = Dict(
        "unique_drugs_with_naive_only_indications" => length(drug_counts),
        "top_drugs_by_unique_indications" => sort(collect(drug_counts), by=x->x[2], rev=true)[1:min(10, length(drug_counts))],
        "most_common_unique_indications" => sort(collect(indication_counts), by=x->x[2], rev=true)[1:min(20, length(indication_counts))]
    )
    
    # Save to JSON file
    open(output_file, "w") do f
        write(f, JSON3.write(organized_data, indent=2))
    end
    
    println("\n✅ Analysis complete!")
    println("📄 Saved results to: $output_file")
    println("\n🔍 Top drugs with unique naive indications:")
    for (i, (drug, count)) in enumerate(organized_data["summary_statistics"]["top_drugs_by_unique_indications"])
        println("  $i. $drug: $count unique indications")
        if i >= 5 break end
    end
    
    println("\n🔍 Most common unique naive indications:")
    for (i, (indication, count)) in enumerate(organized_data["summary_statistics"]["most_common_unique_indications"])
        println("  $i. $indication (found in $count drugs)")
        if i >= 10 break end
    end
    
    return output_file
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    analyze_phase1_files()
end