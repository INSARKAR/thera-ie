#!/usr/bin/env julia

"""
MeSH T047 Extractor

This program parses the MeSH d2025.bin file and extracts MeSH headings (MH tags)
that have semantic type T047. Semantic type T047 typically represents "Disease 
or Syndrome" in the UMLS semantic network.

Usage:
    julia mesh_t047_extractor.jl

Input:
    - ../_data/mesh/d2025.bin (MeSH descriptor file)

Output:
    - mesh_t047_headings.jl (Julia Set containing MeSH headings)
    - mesh_t047_headings.txt (Plain text list)

The program reads through the MeSH binary file, identifies records with semantic
type T047, and stores the corresponding MeSH headings in a set for easy lookup
and research applications.
"""

using Dates

"""
    parse_mesh_file(file_path::String) -> Set{String}

Parse the MeSH file and extract MH (MeSH headings) for records with ST = T047.

# Arguments
- `file_path::String`: Path to the MeSH d2025.bin file

# Returns
- `Set{String}`: Set of MeSH headings with semantic type T047
"""
function parse_mesh_file(file_path::String)
    println("Parsing MeSH file: $file_path")
    
    if !isfile(file_path)
        error("MeSH file not found: $file_path")
    end
    
    mesh_headings_t047 = Set{String}()
    
    # Current record state
    current_mh = ""
    current_record_has_t047 = false
    records_processed = 0
    
    open(file_path, "r") do file
        for line in eachline(file)
            line = strip(line)
            
            # New record marker
            if line == "*NEWRECORD"
                # Process previous record if it had T047
                if current_record_has_t047 && !isempty(current_mh)
                    push!(mesh_headings_t047, current_mh)
                end
                
                # Reset for next record
                current_mh = ""
                current_record_has_t047 = false
                records_processed += 1
                
                if records_processed % 1000 == 0
                    println("Processed $records_processed records, found $(length(mesh_headings_t047)) T047 headings so far...")
                end
                
                continue
            end
            
            # Extract MeSH heading
            if startswith(line, "MH = ")
                current_mh = strip(line[6:end])  # Remove "MH = " prefix
            end
            
            # Check for semantic type T047
            if line == "ST = T047"
                current_record_has_t047 = true
            end
        end
        
        # Handle the last record
        if current_record_has_t047 && !isempty(current_mh)
            push!(mesh_headings_t047, current_mh)
        end
    end
    
    println("Parsing complete!")
    println("Total records processed: $records_processed")
    println("MeSH headings with semantic type T047: $(length(mesh_headings_t047))")
    
    return mesh_headings_t047
end

"""
    save_mesh_headings_as_julia_set(headings::Set{String}, output_file::String)

Save the MeSH headings as a Julia Set in a .jl file.
"""
function save_mesh_headings_as_julia_set(headings::Set{String}, output_file::String)
    open(output_file, "w") do file
        write(file, "# MeSH Headings with Semantic Type T047 (Disease or Syndrome)\n")
        write(file, "# Generated on: $(now())\n")
        write(file, "# Total headings: $(length(headings))\n")
        write(file, "\n")
        write(file, "const MESH_T047_HEADINGS = Set{String}([\n")
        
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
    save_mesh_headings_as_text(headings::Set{String}, output_file::String)

Save the MeSH headings as a plain text list.
"""
function save_mesh_headings_as_text(headings::Set{String}, output_file::String)
    open(output_file, "w") do file
        write(file, "MeSH Headings with Semantic Type T047 (Disease or Syndrome)\n")
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
    output_julia_file = "mesh_t047_headings.jl"
    output_text_file = "mesh_t047_headings.txt"
    
    println("MeSH T047 Semantic Type Extractor")
    println("=================================")
    println("Input file: $mesh_file_path")
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
