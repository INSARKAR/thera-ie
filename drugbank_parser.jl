#!/usr/bin/env julia

"""
DrugBank XML Parser

This script parses drug information from DrugBank XML files using the XML.jl package.
It extracts key drug properties and exports them to various formats.

Usage:
    julia drugbank_parser.jl

Requirements:
    - XML.jl package
    - DataFrames.jl package (for data manipulation)
    - CSV.jl package (for CSV export)
"""

using EzXML
using DataFrames
using CSV

# Structure to hold drug information
struct Drug
    drugbank_id::String
    name::String
    description::String
    cas_number::String
    unii::String
    state::String
    groups::Vector{String}
    categories::Vector{String}
    indication::String
    pharmacodynamics::String
    mechanism_of_action::String
    toxicity::String
    metabolism::String
    absorption::String
    half_life::String
    protein_binding::String
    route_of_elimination::String
    volume_of_distribution::String
    clearance::String
end

# Default constructor for Drug with empty values
function Drug()
    return Drug("", "", "", "", "", "", String[], String[], "", "", "", "", "", "", "", "", "", "", "")
end

"""
    parse_drugbank_xml(xml_file_path::String) -> Vector{Drug}

Parse the DrugBank XML file and extract drug information.

# Arguments
- `xml_file_path::String`: Path to the DrugBank XML file

# Returns
- `Vector{Drug}`: Array of Drug structures containing parsed information
"""
function parse_drugbank_xml(xml_file_path::String)
    println("Starting to parse DrugBank XML file: $xml_file_path")
    
    # Check if file exists
    if !isfile(xml_file_path)
        error("XML file not found: $xml_file_path")
    end
    
    # Parse the XML document
    doc = readxml(xml_file_path)
    root = doc.root
    
    drugs = Drug[]
    
    # Find all drug elements
    # Handle namespace by using local name matching
    drug_nodes = []
    for child in eachelement(root)
        if occursin("drug", nodename(child))
            push!(drug_nodes, child)
        end
    end
    println("Found $(length(drug_nodes)) drugs in the XML file")
    
    for (i, drug_node) in enumerate(drug_nodes)
        if i % 100 == 0
            println("Processing drug $i of $(length(drug_nodes))")
        end
        
        try
            drug = parse_drug_node(drug_node)
            push!(drugs, drug)
        catch e
            println("Error parsing drug $i: $e")
            continue
        end
    end
    
    println("Successfully parsed $(length(drugs)) drugs")
    return drugs
end

"""
    parse_drug_node(drug_node) -> Drug

Parse a single drug node from the XML and extract relevant information.

# Arguments
- `drug_node`: XML node representing a single drug

# Returns
- `Drug`: Drug structure with extracted information
"""
function parse_drug_node(drug_node)
    # Helper function to safely extract text content by element name
    function safe_text_by_name(element_name, default="")
        for child in eachelement(drug_node)
            if occursin(element_name, nodename(child))
                return strip(nodecontent(child))
            end
        end
        return default
    end
    
    # Helper function to find element by name and attribute
    function find_element_by_name_and_attr(element_name, attr_name="", attr_value="")
        for child in eachelement(drug_node)
            if occursin(element_name, nodename(child))
                if isempty(attr_name) || (haskey(child, attr_name) && child[attr_name] == attr_value)
                    return strip(nodecontent(child))
                end
            end
        end
        return ""
    end
    
    # Helper function to extract multiple values by element name
    function extract_multiple_by_name(parent_name, child_name)
        result = String[]
        for child in eachelement(drug_node)
            if occursin(parent_name, nodename(child))
                for grandchild in eachelement(child)
                    if occursin(child_name, nodename(grandchild))
                        push!(result, strip(nodecontent(grandchild)))
                    end
                end
            end
        end
        return result
    end
    
    # Extract basic drug information
    drugbank_id = find_element_by_name_and_attr("drugbank-id", "primary", "true")
    name = safe_text_by_name("name")
    description = safe_text_by_name("description")
    cas_number = safe_text_by_name("cas-number")
    unii = safe_text_by_name("unii")
    state = safe_text_by_name("state")
    
    # Extract groups
    groups = extract_multiple_by_name("groups", "group")
    
    # Extract categories - look for nested category elements
    categories = String[]
    for child in eachelement(drug_node)
        if occursin("categories", nodename(child))
            for category_node in eachelement(child)
                if occursin("category", nodename(category_node))
                    for cat_child in eachelement(category_node)
                        if occursin("category", nodename(cat_child))
                            push!(categories, strip(nodecontent(cat_child)))
                        end
                    end
                end
            end
        end
    end
    
    # Extract pharmacological information
    indication = safe_text_by_name("indication")
    pharmacodynamics = safe_text_by_name("pharmacodynamics")
    mechanism_of_action = safe_text_by_name("mechanism-of-action")
    toxicity = safe_text_by_name("toxicity")
    metabolism = safe_text_by_name("metabolism")
    absorption = safe_text_by_name("absorption")
    half_life = safe_text_by_name("half-life")
    protein_binding = safe_text_by_name("protein-binding")
    route_of_elimination = safe_text_by_name("route-of-elimination")
    volume_of_distribution = safe_text_by_name("volume-of-distribution")
    clearance = safe_text_by_name("clearance")
    
    return Drug(
        drugbank_id,
        name,
        description,
        cas_number,
        unii,
        state,
        groups,
        categories,
        indication,
        pharmacodynamics,
        mechanism_of_action,
        toxicity,
        metabolism,
        absorption,
        half_life,
        protein_binding,
        route_of_elimination,
        volume_of_distribution,
        clearance
    )
end

"""
    drugs_to_dataframe(drugs::Vector{Drug}) -> DataFrame

Convert a vector of Drug structures to a DataFrame for easier analysis.

# Arguments
- `drugs::Vector{Drug}`: Array of Drug structures

# Returns
- `DataFrame`: DataFrame with drug information
"""
function drugs_to_dataframe(drugs::Vector{Drug})
    return DataFrame(
        drugbank_id = [drug.drugbank_id for drug in drugs],
        name = [drug.name for drug in drugs],
        description = [drug.description for drug in drugs],
        cas_number = [drug.cas_number for drug in drugs],
        unii = [drug.unii for drug in drugs],
        state = [drug.state for drug in drugs],
        groups = [join(drug.groups, "; ") for drug in drugs],
        categories = [join(drug.categories, "; ") for drug in drugs],
        indication = [drug.indication for drug in drugs],
        pharmacodynamics = [drug.pharmacodynamics for drug in drugs],
        mechanism_of_action = [drug.mechanism_of_action for drug in drugs],
        toxicity = [drug.toxicity for drug in drugs],
        metabolism = [drug.metabolism for drug in drugs],
        absorption = [drug.absorption for drug in drugs],
        half_life = [drug.half_life for drug in drugs],
        protein_binding = [drug.protein_binding for drug in drugs],
        route_of_elimination = [drug.route_of_elimination for drug in drugs],
        volume_of_distribution = [drug.volume_of_distribution for drug in drugs],
        clearance = [drug.clearance for drug in drugs]
    )
end

"""
    export_to_csv(drugs::Vector{Drug}, output_path::String)

Export drug data to a CSV file.

# Arguments
- `drugs::Vector{Drug}`: Array of Drug structures
- `output_path::String`: Path for the output CSV file
"""
function export_to_csv(drugs::Vector{Drug}, output_path::String)
    df = drugs_to_dataframe(drugs)
    CSV.write(output_path, df)
    println("Exported $(length(drugs)) drugs to $output_path")
end

"""
    analyze_drugs(drugs::Vector{Drug})

Perform basic analysis on the parsed drug data.

# Arguments
- `drugs::Vector{Drug}`: Array of Drug structures
"""
function analyze_drugs(drugs::Vector{Drug})
    println("\n=== DrugBank Analysis ===")
    println("Total number of drugs: $(length(drugs))")
    
    # Analyze drug states
    states = [drug.state for drug in drugs if !isempty(drug.state)]
    state_counts = Dict{String, Int}()
    for state in states
        state_counts[state] = get(state_counts, state, 0) + 1
    end
    
    println("\nDrug states:")
    for (state, count) in sort(collect(state_counts), by=x->x[2], rev=true)
        println("  $state: $count")
    end
    
    # Analyze groups
    all_groups = String[]
    for drug in drugs
        append!(all_groups, drug.groups)
    end
    group_counts = Dict{String, Int}()
    for group in all_groups
        group_counts[group] = get(group_counts, group, 0) + 1
    end
    
    println("\nTop drug groups:")
    sorted_groups = sort(collect(group_counts), by=x->x[2], rev=true)
    for (group, count) in sorted_groups[1:min(10, length(sorted_groups))]
        println("  $group: $count")
    end
    
    # Count drugs with complete information
    complete_drugs = 0
    for drug in drugs
        if !isempty(drug.drugbank_id) && !isempty(drug.name) && !isempty(drug.description)
            complete_drugs += 1
        end
    end
    println("\nDrugs with complete basic information: $complete_drugs ($(round(complete_drugs/length(drugs)*100, digits=1))%)")
end

"""
    main()

Main function to execute the DrugBank XML parsing.
"""
function main()
    # Configuration
    xml_file_path = "../_data/drugbank/drugbank-20250628.xml"
    xsd_file_path = "../_data/drugbank/drugbank.xsd"
    output_csv_path = "drugbank_drugs.csv"
    
    println("DrugBank XML Parser")
    println("==================")
    println("XML file: $xml_file_path")
    println("XSD file: $xsd_file_path")
    println("Output CSV: $output_csv_path")
    println()
    
    # Check if XSD file exists (for reference)
    if isfile(xsd_file_path)
        println("XSD schema file found: $xsd_file_path")
    else
        println("Warning: XSD schema file not found: $xsd_file_path")
    end
    
    try
        # Parse the XML file
        drugs = parse_drugbank_xml(xml_file_path)
        
        # Perform analysis
        analyze_drugs(drugs)
        
        # Export to CSV
        export_to_csv(drugs, output_csv_path)
        
        # Display sample data
        if !isempty(drugs)
            println("\n=== Sample Drug Information ===")
            sample_drug = first(drugs)
            println("DrugBank ID: $(sample_drug.drugbank_id)")
            println("Name: $(sample_drug.name)")
            println("State: $(sample_drug.state)")
            println("Groups: $(join(sample_drug.groups, ", "))")
            println("Description: $(length(sample_drug.description) > 100 ? sample_drug.description[1:100] * "..." : sample_drug.description)")
        end
        
        println("\nParsing completed successfully!")
        
    catch e
        println("Error during execution: $e")
        println("Stack trace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
        exit(1)
    end
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
