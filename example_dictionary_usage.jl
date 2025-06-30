#!/usr/bin/env julia

"""
Example usage of the approved drugs dictionary

This script demonstrates how to use the generated approved drugs dictionary
in other Julia programs.
"""

# Include the generated dictionary
include("test_approved_drugs.jl")

println("=== Using the Approved Drugs Dictionary ===")
println("Total approved drugs in dictionary: $(length(APPROVED_DRUGS_DICT))")
println()

# Example 1: Look up a specific drug
println("Example 1: Looking up specific drugs")
test_drugs = ["Cetuximab", "Lepirudin", "Aspirin"]  # Aspirin won't be found

for drug_name in test_drugs
    if haskey(APPROVED_DRUGS_DICT, drug_name)
        indication = APPROVED_DRUGS_DICT[drug_name]
        println("✓ $drug_name: $indication")
    else
        println("✗ $drug_name: Not found in approved drugs dictionary")
    end
end

println()

# Example 2: Search for drugs by indication keyword
println("Example 2: Searching for drugs by indication keyword")
function find_drugs_by_keyword(keyword::String)
    matching_drugs = Pair{String, String}[]
    keyword_lower = lowercase(keyword)
    
    for (drug, indication) in APPROVED_DRUGS_DICT
        if occursin(keyword_lower, lowercase(indication))
            push!(matching_drugs, drug => indication)
        end
    end
    
    return matching_drugs
end

# Search for cancer-related drugs
cancer_drugs = find_drugs_by_keyword("cancer")
println("Drugs for cancer treatment:")
for (drug, indication) in cancer_drugs
    println("  $drug: $indication")
end

if isempty(cancer_drugs)
    println("  No cancer-related drugs found in the sample data")
end

# Search for colorectal-related drugs
colorectal_drugs = find_drugs_by_keyword("colorectal")
println("\nDrugs for colorectal conditions:")
for (drug, indication) in colorectal_drugs
    println("  $drug: $indication")
end

println()

# Example 3: List all drugs alphabetically
println("Example 3: All approved drugs (alphabetically)")
sorted_drugs = sort(collect(APPROVED_DRUGS_DICT))
for (i, (drug, indication)) in enumerate(sorted_drugs)
    short_indication = length(indication) > 80 ? indication[1:80] * "..." : indication
    println("  $i. $drug")
    println("     $short_indication")
end

println()
println("=== Dictionary Usage Examples Complete ===")
println("You can use this dictionary in your own programs by including the .jl file")
