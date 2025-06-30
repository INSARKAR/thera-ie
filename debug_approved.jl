#!/usr/bin/env julia

include("drugbank_parser.jl")

println("=== Debug Approved Drugs Extraction ===")

# Parse drugs
drugs = parse_drugbank_xml("sample_drugbank.xml")
println("Total drugs parsed: ", length(drugs))

# Check each drug
for (i, drug) in enumerate(drugs)
    println("\nDrug $i:")
    println("  Name: '", drug.name, "'")
    println("  DrugBank ID: '", drug.drugbank_id, "'")
    println("  Groups: ", drug.groups)
    println("  Indication: '", drug.indication[1:min(80, length(drug.indication))], "...'")
    println("  Is approved: ", "approved" in drug.groups)
end

# Filter approved drugs
approved_drugs = filter(drug -> "approved" in drug.groups, drugs)
println("\n=== Approved Drugs ===")
println("Found $(length(approved_drugs)) approved drugs")

# Create dictionary
drug_dict = Dict{String, String}()
for drug in approved_drugs
    clean_indication = replace(strip(drug.indication), r"\s+" => " ")
    if !isempty(drug.name) && !isempty(clean_indication)
        drug_dict[drug.name] = clean_indication
        println("Added: $(drug.name) -> $(clean_indication[1:min(60, length(clean_indication))])...")
    end
end

println("\nFinal dictionary:")
for (name, indication) in drug_dict
    println("  '$name' => '$(indication[1:min(80, length(indication))])...'")
end
