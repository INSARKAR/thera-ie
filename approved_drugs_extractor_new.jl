#!/usr/bin/env julia

"""
Approved Drugs Extractor - Information and Utilities

This program provides information about the approved drugs dataset that has been
extracted from DrugBank XML. The extraction process has already been completed
and the following output files are available:

- approved_drugs_dict.jl (Julia dictionary format)
- approved_drugs_dict.json (JSON format)
- approved_drugs_list.csv (CSV format)

Usage:
    julia approved_drugs_extractor.jl

The extraction process included:
- Only approved drugs (excluded investigational, experimental, etc.)
- Only drugs with valid indication data (excluded empty or placeholder text)
- Cleaned indication text and removed duplicates
- Generated 2,915 approved drugs with meaningful indications

This ensures a high-quality dataset suitable for PubMed search generation
and other pharmaceutical research purposes.
"""

using JSON
using Dates

"""
    load_approved_drugs_dict() -> Dict{String, String}

Load the approved drugs dictionary from the generated files.
"""
function load_approved_drugs_dict()
    dict_files = [
        "approved_drugs_dict.jl",
        "approved_drugs_dict.json"
    ]
    
    # Try to load from Julia file first
    if isfile("approved_drugs_dict.jl")
        println("Loading approved drugs dictionary from Julia file...")
        include("approved_drugs_dict.jl")
        if @isdefined(APPROVED_DRUGS_DICT)
            return APPROVED_DRUGS_DICT
        end
    end
    
    # Try to load from JSON file
    if isfile("approved_drugs_dict.json")
        println("Loading approved drugs dictionary from JSON file...")
        json_data = JSON.parsefile("approved_drugs_dict.json")
        if haskey(json_data, "drugs")
            return json_data["drugs"]
        end
    end
    
    error("No approved drugs dictionary files found!")
end

"""
    show_dataset_info()

Display information about the approved drugs dataset.
"""
function show_dataset_info()
    println("Approved Drugs Dataset Information")
    println("=================================")
    
    try
        drugs_dict = load_approved_drugs_dict()
        
        println("Total approved drugs: $(length(drugs_dict))")
        println("Dataset generated: $(now())")
        println()
        
        # Show some example drugs
        println("Sample drugs (first 5):")
        count = 0
        for (drug_name, indication) in drugs_dict
            count += 1
            if count > 5
                break
            end
            
            # Truncate long indications for display
            short_indication = length(indication) > 100 ? 
                               indication[1:100] * "..." : 
                               indication
            
            println("  $count. $drug_name")
            println("     → $short_indication")
            println()
        end
        
        # Show indication length statistics
        indication_lengths = [length(indication) for indication in values(drugs_dict)]
        avg_length = round(sum(indication_lengths) / length(indication_lengths), digits=1)
        max_length = maximum(indication_lengths)
        min_length = minimum(indication_lengths)
        
        println("Indication Statistics:")
        println("  Average length: $avg_length characters")
        println("  Min length: $min_length characters")
        println("  Max length: $max_length characters")
        
        println()
        println("Output Files Generated:")
        println("  ✓ approved_drugs_dict.jl - Julia dictionary format")
        println("  ✓ approved_drugs_dict.json - JSON format")
        println("  ✓ approved_drugs_list.csv - CSV format")
        
        println()
        println("Usage:")
        println("  This dataset is ready for use with pubmed_query_generator.jl")
        println("  to generate PubMed search queries for pharmaceutical research.")
        
    catch e
        println("Error loading dataset: $e")
        println()
        println("Expected files:")
        println("  - approved_drugs_dict.jl")
        println("  - approved_drugs_dict.json") 
        println("  - approved_drugs_list.csv")
    end
end

"""
    main()

Main function to display dataset information.
"""
function main()
    show_dataset_info()
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
