#!/usr/bin/env julia

include("approved_drugs_extractor.jl")

println("Testing Approved Drugs Extractor")
println("================================")

# Use sample file for testing
xml_file = "sample_drugbank.xml"
println("Using sample XML file: $xml_file")

# Extract approved drugs
drug_dict = extract_approved_drugs_with_indications(xml_file)

# Display results
println("\nExtracted drug-indication pairs:")
for (drug, indication) in sort(collect(drug_dict))
    short_indication = length(indication) > 100 ? indication[1:100] * "..." : indication
    println("  $drug: $short_indication")
end

# Save in different formats
save_dict_as_julia_file(drug_dict, "test_approved_drugs.jl")
save_dict_as_json(drug_dict, "test_approved_drugs.json")
save_dict_as_csv(drug_dict, "test_approved_drugs.csv")

println("\nTest completed successfully!")
println("Generated files:")
println("  - test_approved_drugs.jl")
println("  - test_approved_drugs.json") 
println("  - test_approved_drugs.csv")
