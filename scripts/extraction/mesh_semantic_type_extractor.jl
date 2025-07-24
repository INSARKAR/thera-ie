#!/usr/bin/env julia

"""
MeSH Semantic Type Extractor

This program parses the MeSH d2025.bin file and extracts MeSH headings (MH tags)
that have specified semantic types. Configurable to extract multiple semantic types
including T047 (Disease or Syndrome) and T191 (Neoplastic Process).

Usage:
    julia mesh_semantic_type_extractor.jl

Input:
    - ../_data/mesh/d2025.bin (MeSH descriptor file)

Output:
    - mesh_semantic_headings.jl (Julia Set containing MeSH headings)
    - mesh_semantic_headings.txt (Plain text list)

The program reads through the MeSH binary file, identifies records with the
specified semantic types, and stores the corresponding MeSH headings in a set 
for easy lookup and research applications.

Semantic Types:
    - T047: Disease or Syndrome
    - T191: Neoplastic Process
    - (configurable list)
"""

using Dates

# Configuration: Semantic types to extract
const TARGET_SEMANTIC_TYPES = Set{String}([
    "T047",  # Disease or Syndrome
    "T191",  # Neoplastic Process
    "T048",  # Mental or Behavioral Dysfunction
    "T184",  # Sign or Symptom
    "T046",  # Pathologic Function
    "T049",  # Cell or Molecular Dysfunction
    "T020",  # Acquired Abnormality
    "T037",  # Injury or Poisoning
    "T019",  # Congenital Abnormality
    "T033",  # Finding
    "T201",  # Clinical Attribute
    "T042",  # Organ or Tissue Function
    "T190",  # Anatomical Abnormality
    "T043",  # Cell Function
    "T040"   # Organism Function
])

"""
    parse_mesh_file(file_path::String, semantic_types::Set{String}=TARGET_SEMANTIC_TYPES) -> Set{String}

Parse the MeSH file and extract MH (MeSH headings) for records with specified semantic types.

# Arguments
- `file_path::String`: Path to the MeSH d2025.bin file
- `semantic_types::Set{String}`: Set of semantic types to extract (default: T047, T191)

# Returns
- `Set{String}`: Set of MeSH headings with the specified semantic types
"""
function parse_mesh_file(file_path::String, semantic_types::Set{String}=TARGET_SEMANTIC_TYPES)
    println("Parsing MeSH file: $file_path")
    println("Target semantic types: $(join(sort(collect(semantic_types)), ", "))")
    
    if !isfile(file_path)
        error("MeSH file not found: $file_path")
    end
    
    mesh_headings = Set{String}()
    
    # Current record state
    current_mh = ""
    current_record_has_target_type = false
    current_semantic_types = Set{String}()
    records_processed = 0
    
    open(file_path, "r") do file
        for line in eachline(file)
            line = strip(line)
            
            # New record marker
            if line == "*NEWRECORD"
                # Process previous record if it had any target semantic type
                if current_record_has_target_type && !isempty(current_mh)
                    push!(mesh_headings, current_mh)
                end
                
                # Reset for next record
                current_mh = ""
                current_record_has_target_type = false
                empty!(current_semantic_types)
                records_processed += 1
                
                if records_processed % 1000 == 0
                    println("Processed $records_processed records, found $(length(mesh_headings)) target headings so far...")
                end
                
                continue
            end
            
            # Extract MeSH heading
            if startswith(line, "MH = ")
                current_mh = strip(line[6:end])  # Remove "MH = " prefix
            end
            
            # Check for any target semantic types
            if startswith(line, "ST = ")
                st_value = strip(line[6:end])  # Remove "ST = " prefix
                push!(current_semantic_types, st_value)
                if st_value in semantic_types
                    current_record_has_target_type = true
                end
            end
        end
        
        # Handle the last record
        if current_record_has_target_type && !isempty(current_mh)
            push!(mesh_headings, current_mh)
        end
    end
    
    println("Parsing complete!")
    println("Total records processed: $records_processed")
    println("MeSH headings with target semantic types: $(length(mesh_headings))")
    
    # Show breakdown by semantic type
    println("Semantic types found:")
    for st in sort(collect(semantic_types))
        println("  - $st: Included in extraction")
    end
    
    return mesh_headings
end

"""
    save_mesh_headings_as_julia_set(headings::Set{String}, output_file::String, semantic_types::Set{String}=TARGET_SEMANTIC_TYPES)

Save the MeSH headings as a Julia Set in a .jl file.
"""
function save_mesh_headings_as_julia_set(headings::Set{String}, output_file::String, semantic_types::Set{String}=TARGET_SEMANTIC_TYPES)
    semantic_types_str = join(sort(collect(semantic_types)), ", ")
    open(output_file, "w") do file
        write(file, "# MeSH Headings with Medical Semantic Types\n")
        write(file, "# T047: Disease or Syndrome\n")
        write(file, "# T191: Neoplastic Process\n") 
        write(file, "# T048: Mental or Behavioral Dysfunction\n")
        write(file, "# T184: Sign or Symptom\n")
        write(file, "# T046: Pathologic Function\n")
        write(file, "# T049: Cell or Molecular Dysfunction\n")
        write(file, "# T020: Acquired Abnormality\n")
        write(file, "# T037: Injury or Poisoning\n")
        write(file, "# T019: Congenital Abnormality\n")
        write(file, "# T033: Finding\n")
        write(file, "# T201: Clinical Attribute\n")
        write(file, "# T042: Organ or Tissue Function\n")
        write(file, "# T190: Anatomical Abnormality\n")
        write(file, "# T043: Cell Function\n")
        write(file, "# T040: Organism Function\n")
        write(file, "# Generated on: $(now())\n")
        write(file, "# Total headings: $(length(headings))\n")
        write(file, "\n")
        write(file, "const MESH_SEMANTIC_HEADINGS = Set{String}([\n")
        
        # Sort headings for consistent output
        sorted_headings = sort(collect(headings))
        
        for (i, heading) in enumerate(sorted_headings)
            # Escape quotes in the heading
            escaped_heading = replace(heading, "\"" => "\\\"")
            if i < length(sorted_headings)
                write(file, "    \"$escaped_heading\",\n")
            else
                write(file, "    \"$escaped_heading\"\n")
            end
        end
        
        write(file, "])\n")
    end
    
    println("Saved Julia Set to: $output_file")
end

"""
    save_mesh_headings_as_text(headings::Set{String}, output_file::String, semantic_types::Set{String}=TARGET_SEMANTIC_TYPES)

Save the MeSH headings as a plain text list.
"""
function save_mesh_headings_as_text(headings::Set{String}, output_file::String, semantic_types::Set{String}=TARGET_SEMANTIC_TYPES)
    semantic_types_str = join(sort(collect(semantic_types)), ", ")
    open(output_file, "w") do file
        write(file, "MeSH Headings with Medical Semantic Types\n")
        write(file, "T047: Disease or Syndrome\n")
        write(file, "T191: Neoplastic Process\n") 
        write(file, "T048: Mental or Behavioral Dysfunction\n")
        write(file, "T184: Sign or Symptom\n")
        write(file, "T046: Pathologic Function\n")
        write(file, "T049: Cell or Molecular Dysfunction\n")
        write(file, "T020: Acquired Abnormality\n")
        write(file, "T037: Injury or Poisoning\n")
        write(file, "T019: Congenital Abnormality\n")
        write(file, "T033: Finding\n")
        write(file, "T201: Clinical Attribute\n")
        write(file, "T042: Organ or Tissue Function\n")
        write(file, "T190: Anatomical Abnormality\n")
        write(file, "T043: Cell Function\n")
        write(file, "T040: Organism Function\n")
        write(file, "Generated on: $(now())\n")
        write(file, "Total headings: $(length(headings))\n")
        write(file, "\n")
        
        # Sort headings for consistent output
        sorted_headings = sort(collect(headings))
        
        for heading in sorted_headings
            write(file, "$heading\n")
        end
    end
    
    println("Saved text list to: $output_file")
end

"""
    show_sample_headings(headings::Set{String}, count::Int=10)

Display a sample of the extracted MeSH headings.
"""
function show_sample_headings(headings::Set{String}, count::Int=10)
    println("\n=== Sample MeSH Headings with Semantic Type T047 ===")
    
    sorted_headings = sort(collect(headings))
    sample_count = min(count, length(sorted_headings))
    
    for i in 1:sample_count
        println("  $i. $(sorted_headings[i])")
    end
    
    if length(sorted_headings) > count
        println("  ... and $(length(sorted_headings) - count) more")
    end
    println()
end

"""
    main()

Main function to extract MeSH headings with semantic type T047.
"""
function main()
    # Configuration
    mesh_file_path = "../_data/mesh/d2025.bin"
    output_julia_file = "mesh_semantic_headings.jl"
    output_text_file = "mesh_semantic_headings.txt"
    
    println("MeSH Medical Semantic Type Extractor")
    println("====================================")
    println("Input file: $mesh_file_path")
    println("Target semantic types ($(length(TARGET_SEMANTIC_TYPES))):")
    for st in sort(collect(TARGET_SEMANTIC_TYPES))
        st_name = Dict(
            "T047" => "Disease or Syndrome",
            "T191" => "Neoplastic Process",
            "T048" => "Mental or Behavioral Dysfunction",
            "T184" => "Sign or Symptom",
            "T046" => "Pathologic Function",
            "T049" => "Cell or Molecular Dysfunction",
            "T020" => "Acquired Abnormality",
            "T037" => "Injury or Poisoning",
            "T019" => "Congenital Abnormality",
            "T033" => "Finding",
            "T201" => "Clinical Attribute",
            "T042" => "Organ or Tissue Function",
            "T190" => "Anatomical Abnormality",
            "T043" => "Cell Function",
            "T040" => "Organism Function"
        )[st]
        println("  - $st: $st_name")
    end
    println("Output files:")
    println("  - Julia Set: $output_julia_file")
    println("  - Text list: $output_text_file")
    println()
    
    try
        # Parse the MeSH file
        mesh_headings = parse_mesh_file(mesh_file_path)
        
        if isempty(mesh_headings)
            println("No MeSH headings with semantic type T047 found!")
            return
        end
        
        # Save in multiple formats
        save_mesh_headings_as_julia_set(mesh_headings, output_julia_file)
        save_mesh_headings_as_text(mesh_headings, output_text_file)
        
        # Show sample results
        show_sample_headings(mesh_headings, 15)
        
        println("Extraction completed successfully!")
        println("Generated files:")
        println("  ✓ $output_julia_file - Julia Set format")
        println("  ✓ $output_text_file - Plain text list")
        
    catch e
        println("Error during extraction: $e")
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
