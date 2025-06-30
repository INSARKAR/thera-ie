#!/usr/bin/env julia

# Test the simplified approved drugs extractor
println("Testing Simplified Approved Drugs Extractor")
println("===========================================")

# Temporarily modify the main function to use sample data
include("approved_drugs_extractor.jl")

# Override the file paths to use sample data
xml_file_path = "sample_drugbank.xml"
julia_output_file = "test_simple_approved_drugs.jl"
json_output_file = "test_simple_approved_drugs.json"
csv_output_file = "test_simple_approved_drugs.csv"

println("Approved Drugs Extractor")
println("========================")
println("XML file: $xml_file_path")
println("Output files:")
println("  - Julia: $julia_output_file")
println("  - JSON: $json_output_file")
println("  - CSV: $csv_output_file")
println()

try
    # Extract approved drugs with indications
    drug_dict = extract_approved_drugs_with_indications(xml_file_path)
    
    if isempty(drug_dict)
        println("No approved drugs found!")
        exit(1)
    end
    
    # Save in multiple formats
    save_dict_as_julia_file(drug_dict, julia_output_file)
    save_dict_as_json(drug_dict, json_output_file)
    save_dict_as_csv(drug_dict, csv_output_file)
    
    println("\nExtraction completed successfully!")
    println("Generated files:")
    println("  - Julia: $julia_output_file")
    println("  - JSON: $json_output_file")
    println("  - CSV: $csv_output_file")
    println()
    println("Summary:")
    println("  - Total approved drugs with valid indications: $(length(drug_dict))")
    println("  - All output files contain only drugs with meaningful indication data")
    
catch e
    println("Error during execution: $e")
    exit(1)
end
