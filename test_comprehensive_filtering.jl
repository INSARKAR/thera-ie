#!/usr/bin/env julia

include("approved_drugs_extractor.jl")

println("Testing Indication Filtering")
println("============================")

# Create test XML with some drugs having missing/invalid indications
test_xml_with_missing = """<?xml version="1.0" encoding="UTF-8"?>
<drugbank xmlns="http://www.drugbank.ca">
  <drug>
    <drugbank-id primary="true">DB00001</drugbank-id>
    <name>Lepirudin</name>
    <description>A recombinant hirudin</description>
    <state>solid</state>
    <groups>
      <group>approved</group>
    </groups>
    <indication>For the treatment of heparin-induced thrombocytopenia</indication>
  </drug>
  <drug>
    <drugbank-id primary="true">DB00002</drugbank-id>
    <name>EmptyIndicationDrug</name>
    <description>A drug with empty indication</description>
    <state>solid</state>
    <groups>
      <group>approved</group>
    </groups>
    <indication></indication>
  </drug>
  <drug>
    <drugbank-id primary="true">DB00003</drugbank-id>
    <name>NotAvailableDrug</name>
    <description>A drug with not available indication</description>
    <state>solid</state>
    <groups>
      <group>approved</group>
    </groups>
    <indication>Not Available</indication>
  </drug>
  <drug>
    <drugbank-id primary="true">DB00004</drugbank-id>
    <name>ValidIndicationDrug</name>
    <description>A drug with valid indication</description>
    <state>solid</state>
    <groups>
      <group>approved</group>
    </groups>
    <indication>For the treatment of bacterial infections</indication>
  </drug>
  <drug>
    <drugbank-id primary="true">DB00005</drugbank-id>
    <name>ExperimentalDrug</name>
    <description>An experimental drug</description>
    <state>solid</state>
    <groups>
      <group>experimental</group>
    </groups>
    <indication>For research purposes only</indication>
  </drug>
</drugbank>"""

# Save test XML
open("test_filtering_sample.xml", "w") do file
    write(file, test_xml_with_missing)
end

println("Created test XML with various indication scenarios:")
println("- Lepirudin: Valid indication (approved)")
println("- EmptyIndicationDrug: Empty indication (approved)")
println("- NotAvailableDrug: 'Not Available' indication (approved)")
println("- ValidIndicationDrug: Valid indication (approved)")
println("- ExperimentalDrug: Valid indication but experimental (not approved)")

# Test the extraction
println("\nTesting extraction with filtering...")
drug_dict = extract_approved_drugs_with_indications("test_filtering_sample.xml")

println("\nResults:")
println("Expected: 2 drugs (Lepirudin and ValidIndicationDrug)")
println("Actual: $(length(drug_dict)) drugs")

if length(drug_dict) == 2
    println("✓ Filtering worked correctly!")
else
    println("✗ Filtering did not work as expected")
end

println("\nFinal dictionary contents:")
for (drug, indication) in sort(collect(drug_dict))
    println("  ✓ $drug: $indication")
end

# Clean up
rm("test_filtering_sample.xml")
println("\nTest completed!")
