#!/usr/bin/env julia

"""
Approved Drugs Extractor

This program extracts approved drugs data from DrugBank XML files and creates
a curated dataset suitable for biomedical research and PubMed searches.

Usage:
    julia approved_drugs_extractor.jl [xml_file]

If no XML file is provided, the program will:
1. Look for existing extracted data files
2. Display dataset information and statistics

If an XML file is provided, the program will:
1. Parse the DrugBank XML
2. Extract only approved drugs with valid indications
3. Clean and process the data
4. Generate output files in multiple formats

The extraction process includes:
- Only approved drugs (excluded investigational, experimental, etc.)
- Only drugs with valid indication data (excluded empty or placeholder text)
- Cleaned indication text and removed duplicates
- Quality filtering for meaningful pharmaceutical data

Output files:
- approved_drugs_dict.jl (Julia dictionary format)
- approved_drugs_dict.json (JSON format)
- approved_drugs_list.csv (CSV format)
"""

using JSON
using Dates
using CSV
using DataFrames

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
        include("../generated_dependency_files/approved_drugs_dict.jl")
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
    
    # Check if dataset files exist
    files_exist = isfile("approved_drugs_dict.jl") || isfile("approved_drugs_dict.json")
    
    if !files_exist
        println("No approved drugs dataset found!")
        println()
        println("To extract approved drugs data:")
        println("  1. Download DrugBank XML database file")
        println("  2. Run: julia approved_drugs_extractor.jl <path_to_drugbank.xml>")
        println()
        println("The extraction will create:")
        println("  • approved_drugs_dict.jl - Julia dictionary format")
        println("  • approved_drugs_dict.json - JSON format")
        println("  • approved_drugs_dict.csv - CSV format")
        println()
        println("These files will contain only approved drugs with valid indications,")
        println("ready for biomedical research and PubMed searches.")
        return
    end
    
    try
        drugs_dict = load_approved_drugs_dict()
        
        println("✓ Dataset loaded successfully")
        println("Total approved drugs: $(length(drugs_dict))")
        println("Last updated: $(now())")
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
        println("Available Output Files:")
        for file in ["approved_drugs_dict.jl", "approved_drugs_dict.json", "approved_drugs_list.csv"]
            if isfile(file)
                println("  ✓ $file")
            else
                println("  ✗ $file (missing)")
            end
        end
        
        println()
        println("Pipeline Usage:")
        println("  → pubmed_query_generator.jl - Generate PubMed search queries")
        println("  → pubmed_drug_search.jl - Search for publications")
        println("  → pubmed_disease_analyzer.jl - Analyze disease associations")
        
    catch e
        println("Error loading dataset: $e")
        println()
        println("Try re-running the extraction:")
        println("  julia approved_drugs_extractor.jl <path_to_drugbank.xml>")
    end
end

"""
    main()

Main function to either extract data from XML or display existing dataset information.
"""
function main()
    args = ARGS
    
    # Check for help
    if length(args) > 0 && (args[1] == "-h" || args[1] == "--help" || args[1] == "help")
        show_help()
        return
    end
    
    # Validate requirements
    if !validate_extraction_requirements()
        exit(1)
    end
    
    if length(args) > 0
        # XML file provided - perform extraction
        xml_file = args[1]
        
        if !isfile(xml_file)
            println("Error: XML file not found: $xml_file")
            println("\nUsage:")
            println("  julia approved_drugs_extractor.jl [xml_file]")
            println("  julia approved_drugs_extractor.jl  # Show dataset info")
            println("  julia approved_drugs_extractor.jl --help  # Show help")
            exit(1)
        end
        
        println("Approved Drugs Extractor")
        println("========================")
        println("Extracting approved drugs from DrugBank XML...")
        println()
        
        try
            # Extract drugs from XML
            drugs_dict = extract_drugs_from_xml(xml_file)
            
            if isempty(drugs_dict)
                println("Warning: No approved drugs with valid indications found!")
                println("Make sure the XML file contains drug entries with:")
                println("  - <group>approved</group> tags")
                println("  - <indication>meaningful text</indication> tags")
                return
            end
            
            # Save the extracted data
            save_extracted_data(drugs_dict)
            
            # Show summary
            show_extraction_summary(drugs_dict)
            
        catch e
            println("Error during extraction: $e")
            println("Make sure the XML file is a valid DrugBank database export.")
            println("The file should contain <drug> entries with proper XML structure.")
            exit(1)
        end
        
    else
        # No arguments - show dataset information
        show_dataset_info()
    end
end

"""
    show_help()

Display help information for the approved drugs extractor.
"""
function show_help()
    println("Approved Drugs Extractor")
    println("========================")
    println()
    println("DESCRIPTION:")
    println("  Extracts approved drugs with valid indications from DrugBank XML files.")
    println("  Creates curated datasets suitable for biomedical research and PubMed searches.")
    println()
    println("USAGE:")
    println("  julia approved_drugs_extractor.jl                    # Show dataset info")
    println("  julia approved_drugs_extractor.jl <xml_file>         # Extract from XML")
    println("  julia approved_drugs_extractor.jl --help             # Show this help")
    println()
    println("ARGUMENTS:")
    println("  xml_file    Path to DrugBank XML database file")
    println()
    println("OUTPUT FILES:")
    println("  approved_drugs_dict.jl     Julia dictionary format")
    println("  approved_drugs_dict.json   JSON format")
    println("  approved_drugs_dict.csv    CSV format")
    println()
    println("EXTRACTION CRITERIA:")
    println("  • Only drugs with <group>approved</group> tags")
    println("  • Only drugs with meaningful indication text (>20 characters)")
    println("  • Excludes empty, N/A, or placeholder indications")
    println("  • Cleans and normalizes indication text")
    println()
    println("EXAMPLES:")
    println("  # Extract drugs from DrugBank XML")
    println("  julia approved_drugs_extractor.jl drugbank_full_database.xml")
    println()
    println("  # View existing dataset information")
    println("  julia approved_drugs_extractor.jl")
    println()
    println("PIPELINE INTEGRATION:")
    println("  1. approved_drugs_extractor.jl  → Extract drugs from DrugBank")
    println("  2. pubmed_query_generator.jl    → Generate PubMed search queries")
    println("  3. pubmed_drug_search.jl        → Search for publications")
    println("  4. mesh_t047_extractor.jl       → Extract disease classifications")
    println("  5. pubmed_disease_analyzer.jl   → Analyze disease associations")
    println()
    println("REQUIREMENTS:")
    println("  Julia packages: JSON, CSV, DataFrames")
    println("  DrugBank XML file (requires DrugBank account and download)")
end

"""
    show_extraction_summary(drugs_dict::Dict{String, String})

Display a summary of the extraction results.
"""
function show_extraction_summary(drugs_dict::Dict{String, String})
    println("\n" * "="^50)
    println("EXTRACTION SUMMARY")
    println("="^50)
    
    println("Total approved drugs extracted: $(length(drugs_dict))")
    println("Timestamp: $(now())")
    println()
    
    # Show some examples
    println("Sample extracted drugs:")
    count = 0
    for (drug_name, indication) in drugs_dict
        count += 1
        if count > 3
            break
        end
        
        short_indication = length(indication) > 80 ? 
                          indication[1:80] * "..." : 
                          indication
        
        println("  $count. $drug_name")
        println("     → $short_indication")
        println()
    end
    
    # Statistics
    indication_lengths = [length(indication) for indication in values(drugs_dict)]
    avg_length = round(sum(indication_lengths) / length(indication_lengths), digits=1)
    
    println("Statistics:")
    println("  Average indication length: $avg_length characters")
    println("  Min indication length: $(minimum(indication_lengths)) characters")
    println("  Max indication length: $(maximum(indication_lengths)) characters")
    println()
    
    println("Files generated:")
    println("  ✓ approved_drugs_dict.jl - Julia dictionary format")
    println("  ✓ approved_drugs_dict.json - JSON format")  
    println("  ✓ approved_drugs_dict.csv - CSV format")
    println()
    
    println("Next steps:")
    println("  → Use pubmed_query_generator.jl to create PubMed search queries")
    println("  → Use pubmed_drug_search.jl to search for publications")
    println("  → Use pubmed_disease_analyzer.jl to analyze disease associations")
end

"""
    parse_drugbank_xml(xml_file::String) -> Dict{String, String}

Parse DrugBank XML file and extract approved drugs with their indications.
Returns a dictionary mapping drug names to their indication text.
"""
function parse_drugbank_xml(xml_file::String)
    if !isfile(xml_file)
        error("XML file not found: $xml_file")
    end
    
    println("Parsing DrugBank XML file: $xml_file")
    println("This may take a few minutes for large files...")
    
    # Read the XML content
    xml_content = read(xml_file, String)
    
    # Simple XML parsing for drug entries
    approved_drugs = Dict{String, String}()
    drug_count = 0
    approved_count = 0
    
    # Find all drug entries
    drug_pattern = r"<drug.*?</drug>"s
    drugs = eachmatch(drug_pattern, xml_content)
    
    for drug_match in drugs
        drug_xml = drug_match.match
        drug_count += 1
        
        if drug_count % 1000 == 0
            println("  Processed $drug_count drugs...")
        end
        
        # Extract drug type/groups
        groups = extract_drug_groups(drug_xml)
        
        # Only process approved drugs
        if "approved" in lowercase.(groups)
            # Extract drug name
            drug_name = extract_drug_name(drug_xml)
            
            # Extract indication
            indication = extract_indication(drug_xml)
            
            # Only include if we have valid name and indication
            if !isempty(drug_name) && is_valid_indication(indication)
                approved_drugs[drug_name] = clean_indication_text(indication)
                approved_count += 1
            end
        end
    end
    
    println("  Total drugs processed: $drug_count")
    println("  Approved drugs found: $approved_count")
    println("  Approved drugs with valid indications: $(length(approved_drugs))")
    
    return approved_drugs
end

"""
    extract_drug_groups(drug_xml::String) -> Vector{String}

Extract drug groups/categories from drug XML block.
"""
function extract_drug_groups(drug_xml::String)
    groups = String[]
    
    # Look for group tags
    group_pattern = r"<group>([^<]+)</group>"
    for match in eachmatch(group_pattern, drug_xml)
        push!(groups, strip(match.captures[1]))
    end
    
    return groups
end

"""
    extract_drug_name(drug_xml::String) -> String

Extract the primary drug name from drug XML block.
"""
function extract_drug_name(drug_xml::String)
    # Try to extract name - look for the first name tag
    name_pattern = r"<name>([^<]+)</name>"
    name_match = match(name_pattern, drug_xml)
    
    if name_match !== nothing
        return strip(name_match.captures[1])
    end
    
    return ""
end

"""
    extract_indication(drug_xml::String) -> String

Extract indication text from drug XML block.
"""
function extract_indication(drug_xml::String)
    # Look for indication tag
    indication_pattern = r"<indication>([^<]*)</indication>"s
    indication_match = match(indication_pattern, drug_xml)
    
    if indication_match !== nothing
        return strip(indication_match.captures[1])
    end
    
    return ""
end

"""
    is_valid_indication(indication::String) -> Bool

Check if an indication is valid and meaningful.
"""
function is_valid_indication(indication::String)
    if isempty(indication)
        return false
    end
    
    # Remove common non-meaningful indications
    invalid_patterns = [
        r"^\s*$",  # Empty or whitespace only
        r"^not\s+available",  # "Not available"
        r"^unknown",  # "Unknown"
        r"^n/a",  # "N/A"
        r"^none",  # "None"
        r"^see\s+individual",  # "See individual components"
    ]
    
    indication_lower = lowercase(strip(indication))
    
    for pattern in invalid_patterns
        if match(pattern, indication_lower) !== nothing
            return false
        end
    end
    
    # Must be at least 20 characters to be meaningful
    return length(strip(indication)) >= 20
end

"""
    clean_indication_text(indication::String) -> String

Clean and normalize indication text.
"""
function clean_indication_text(indication::String)
    cleaned = strip(indication)
    
    # Remove XML artifacts
    cleaned = replace(cleaned, r"&lt;" => "<")
    cleaned = replace(cleaned, r"&gt;" => ">")
    cleaned = replace(cleaned, r"&amp;" => "&")
    cleaned = replace(cleaned, r"&quot;" => "\"")
    
    # Normalize whitespace
    cleaned = replace(cleaned, r"\s+" => " ")
    
    # Ensure it ends with a period if it doesn't already
    if !isempty(cleaned) && !endswith(cleaned, r"[.!?]")
        cleaned = cleaned * "."
    end
    
    return strip(cleaned)
end

"""
    save_extracted_data(drugs_dict::Dict{String, String}, base_filename::String = "approved_drugs_dict")

Save the extracted drugs data in multiple formats.
"""
function save_extracted_data(drugs_dict::Dict{String, String}, base_filename::String = "approved_drugs_dict")
    timestamp = now()
    drug_count = length(drugs_dict)
    
    println("\nSaving extracted data in multiple formats...")
    
    # Create output directory
    output_dir = "../generated_dependency_files"
    mkpath(output_dir)
    
    # 1. Save as Julia dictionary file
    julia_file = joinpath(output_dir, "$base_filename.jl")
    open(julia_file, "w") do f
        write(f, "# Approved Drugs Dictionary\n")
        write(f, "# Generated on: $timestamp\n")
        write(f, "# Total drugs: $drug_count\n\n")
        write(f, "const APPROVED_DRUGS_DICT = Dict{String, String}(\n")
        
        for (i, (drug_name, indication)) in enumerate(drugs_dict)
            # Escape quotes in strings
            escaped_name = replace(drug_name, "\"" => "\\\"")
            escaped_indication = replace(indication, "\"" => "\\\"")
            
            comma = i == length(drugs_dict) ? "" : ","
            write(f, "    \"$escaped_name\" => \"$escaped_indication\"$comma\n")
        end
        
        write(f, ")\n")
    end
    println("  ✓ Saved Julia format: $julia_file")
    
    # 2. Save as JSON file
    json_file = joinpath(output_dir, "$base_filename.json")
    json_data = Dict(
        "metadata" => Dict(
            "generated_on" => string(timestamp),
            "total_drugs" => drug_count,
            "description" => "Approved drugs extracted from DrugBank with curated indications"
        ),
        "drugs" => drugs_dict
    )
    
    open(json_file, "w") do f
        JSON.print(f, json_data, 2)
    end
    println("  ✓ Saved JSON format: $json_file")
    
    # 3. Save as CSV file
    csv_file = joinpath(output_dir, "$base_filename.csv")
    df = DataFrame(
        drug_name = collect(keys(drugs_dict)),
        indication = collect(values(drugs_dict))
    )
    
    CSV.write(csv_file, df)
    println("  ✓ Saved CSV format: $csv_file")
    
    println("\nExtraction completed successfully!")
    println("Total approved drugs with valid indications: $drug_count")
    
    return julia_file, json_file, csv_file
end

"""
    extract_drugs_from_xml(xml_file::String) -> Dict{String, String}

Main extraction function that wraps parse_drugbank_xml with additional validation.
This is the primary function for extracting approved drugs from DrugBank XML.

Example usage:
    drugs = extract_drugs_from_xml("drugbank.xml")
    save_extracted_data(drugs)
"""
function extract_drugs_from_xml(xml_file::String)
    return parse_drugbank_xml(xml_file)
end

"""
    validate_extraction_requirements()

Check if required packages are available for XML extraction.
"""
function validate_extraction_requirements()
    required_packages = ["JSON", "CSV", "DataFrames"]
    missing_packages = String[]
    
    for pkg in required_packages
        try
            eval(Meta.parse("using $pkg"))
        catch
            push!(missing_packages, pkg)
        end
    end
    
    if !isempty(missing_packages)
        println("Missing required packages: $(join(missing_packages, ", "))")
        println("Install with: using Pkg; Pkg.add([\"$(join(missing_packages, "\", \""))\"])")
        return false
    end
    
    return true
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
