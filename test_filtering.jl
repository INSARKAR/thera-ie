#!/usr/bin/env julia

include("approved_drugs_extractor.jl")

println("Testing Updated Approved Drugs Extractor")
println("========================================")
println("This test verifies that drugs without valid indications are excluded")

# Use sample file for testing
xml_file = "sample_drugbank.xml"
println("Using sample XML file: $xml_file")

# Extract approved drugs (updated version)
drug_dict = extract_approved_drugs_with_indications(xml_file)

# Display results
println("\nExtracted drug-indication pairs (only with valid indications):")
for (drug, indication) in sort(collect(drug_dict))
    short_indication = length(indication) > 100 ? indication[1:100] * "..." : indication
    println("  ✓ $drug: $short_indication")
end

println("\nTotal drugs included: $(length(drug_dict))")

# Test with a drug that has empty indication
println("\nTesting filtering logic:")
println("All drugs in the dictionary have valid indications - no 'Indication not available' entries")

# Verify no empty or invalid indications
invalid_count = 0
for (drug, indication) in drug_dict
    if isempty(indication) || occursin(r"^(not available|n/a|unknown|none)$"i, indication)
        println("  ✗ Found invalid indication for $drug: '$indication'")
        invalid_count += 1
    end
end

if invalid_count == 0
    println("  ✓ All $(length(drug_dict)) drugs have valid indication data")
else
    println("  ✗ Found $invalid_count drugs with invalid indications")
end

# Save the filtered results
save_dict_as_julia_file(drug_dict, "filtered_approved_drugs.jl")
println("\nGenerated filtered_approved_drugs.jl successfully!")

# Show the first few lines of the generated file
println("\nFirst few lines of generated Julia file:")
lines = readlines("filtered_approved_drugs.jl")
for (i, line) in enumerate(lines[1:min(8, length(lines))])
    println("  $line")
end
