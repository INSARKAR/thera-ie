#!/usr/bin/env julia

"""
Example usage of the DrugBank XML Parser

This script demonstrates how to use the drugbank_parser.jl module
to parse DrugBank XML data and perform basic analysis.
"""

include("drugbank_parser.jl")

"""
    create_sample_xml()

Create a small sample XML file for testing purposes.
"""
function create_sample_xml()
    sample_xml = """<?xml version="1.0" encoding="UTF-8"?>
<drugbank xmlns="http://www.drugbank.ca" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.drugbank.ca http://www.drugbank.ca/docs/drugbank.xsd" version="5.1.8" exported-on="2021-01-03">
  <drug type="biotech" created="2005-06-13" updated="2020-12-30">
    <drugbank-id primary="true">DB00001</drugbank-id>
    <drugbank-id>BTD00024</drugbank-id>
    <name>Lepirudin</name>
    <description>Lepirudin is a recombinant hirudin derived from yeast cells.</description>
    <cas-number>138068-37-8</cas-number>
    <unii>Y43GF64R34</unii>
    <state>solid</state>
    <groups>
      <group>approved</group>
      <group>withdrawn</group>
    </groups>
    <general-references>
      <articles>
        <article>
          <pubmed-id>9841303</pubmed-id>
          <citation>Nowak G, Bucha E: Quantitative determination of hirudin in blood and body fluids. Semin Thromb Hemost. 1996;22(2):197-202.</citation>
        </article>
      </articles>
    </general-references>
    <synthesis-reference>Not Available</synthesis-reference>
    <indication>For the treatment of heparin-induced thrombocytopenia</indication>
    <pharmacodynamics>Lepirudin is used to break up clots and to reduce thrombocytopenia.</pharmacodynamics>
    <mechanism-of-action>Lepirudin forms a stable non-covalent complex with alpha-thrombin, thereby abolishing its procoagulant activity.</mechanism-of-action>
    <toxicity>The most frequently observed adverse effect is bleeding.</toxicity>
    <metabolism>Metabolized by release of amino acids via catabolic hydrolysis of the parent compound.</metabolism>
    <absorption>Bioavailability is 100% following intravenous administration.</absorption>
    <half-life>Approximately 1.3 hours</half-life>
    <protein-binding>Not Available</protein-binding>
    <route-of-elimination>About 48% of the administered dose is eliminated in the urine.</route-of-elimination>
    <volume-of-distribution>18.3 ± 15.7 L</volume-of-distribution>
    <clearance>164 ± 78 mL/min</clearance>
    <categories>
      <category>
        <category>Anticoagulants</category>
        <mesh-id>D000925</mesh-id>
      </category>
      <category>
        <category>Antithrombins</category>
        <mesh-id>D000991</mesh-id>
      </category>
    </categories>
  </drug>
  <drug type="small molecule" created="2005-06-13" updated="2020-12-30">
    <drugbank-id primary="true">DB00002</drugbank-id>
    <name>Cetuximab</name>
    <description>Cetuximab is a recombinant, human/mouse chimeric monoclonal antibody.</description>
    <cas-number>205923-56-4</cas-number>
    <unii>PQX0D8J21J</unii>
    <state>liquid</state>
    <groups>
      <group>approved</group>
    </groups>
    <indication>For the treatment of EGFR-expressing, metastatic colorectal carcinoma.</indication>
    <pharmacodynamics>Cetuximab inhibits the growth and survival of tumor cells that overexpress EGFR.</pharmacodynamics>
    <mechanism-of-action>Cetuximab binds specifically to the extracellular domain of the human EGFR.</mechanism-of-action>
    <toxicity>The most serious adverse reactions are infusion reactions and cardiopulmonary arrest.</toxicity>
    <metabolism>Expected to follow the typical pathway of protein catabolism.</metabolism>
    <absorption>Not Available</absorption>
    <half-life>112 hours (range 63-230 hours)</half-life>
    <protein-binding>Not Available</protein-binding>
    <route-of-elimination>Not Available</route-of-elimination>
    <volume-of-distribution>2-3 L/m²</volume-of-distribution>
    <clearance>0.22 L/h/m²</clearance>
    <categories>
      <category>
        <category>Antineoplastic Agents</category>
        <mesh-id>D000970</mesh-id>
      </category>
    </categories>
  </drug>
</drugbank>"""
    
    open("sample_drugbank.xml", "w") do file
        write(file, sample_xml)
    end
    println("Created sample XML file: sample_drugbank.xml")
end

"""
    run_example()

Run the example parsing with sample data.
"""
function run_example()
    println("DrugBank Parser Example")
    println("======================")
    
    # Create sample XML file
    create_sample_xml()
    
    # Parse the sample file
    println("\nParsing sample XML file...")
    drugs = parse_drugbank_xml("sample_drugbank.xml")
    
    # Display results
    println("\nParsed $(length(drugs)) drugs from sample file:")
    for drug in drugs
        println("- $(drug.name) ($(drug.drugbank_id))")
        println("  State: $(drug.state)")
        println("  Groups: $(join(drug.groups, ", "))")
        println("  Description: $(length(drug.description) > 80 ? drug.description[1:80] * "..." : drug.description)")
        println()
    end
    
    # Convert to DataFrame and export
    df = drugs_to_dataframe(drugs)
    println("DataFrame summary:")
    println(df)
    
    # Export to CSV
    CSV.write("sample_drugs.csv", df)
    println("\nExported data to sample_drugs.csv")
    
    # Perform analysis
    analyze_drugs(drugs)
    
    println("\nExample completed successfully!")
end

# Run the example if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_example()
end
