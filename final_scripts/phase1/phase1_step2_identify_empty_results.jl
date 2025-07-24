#!/usr/bin/env julia

# Identify result files with empty publications_analyzed arrays despite having publications found
# This script only looks for the specific issue where total_publications_found > 0 but publications_analyzed is empty

using JSON3

function check_empty_results(file_path::String)
    """
    Check if a file has empty results despite finding publications
    Returns: (is_empty::Bool, total_found::Int, analyzed_count::Int, drug_name::String)
    """
    
    try
        # Extract drug name from filename
        filename = basename(file_path)
        drug_name = replace(split(filename, ".")[1], "_" => " ")
        
        # Read and parse JSON
        content = read(file_path, String)
        data = JSON3.read(content)
        
        # Check basic structure
        if !haskey(data, "result")
            return (false, 0, 0, drug_name)
        end
        
        result = data.result
        
        if !haskey(result, "total_publications_found") || !haskey(result, "publications_analyzed")
            return (false, 0, 0, drug_name)
        end
        
        total_found = result.total_publications_found
        pubs_analyzed = result.publications_analyzed
        
        # Get the count regardless of array type (Vector or JSON3.Array)
        analyzed_count = length(pubs_analyzed)
        
        # Check for empty results: has publications found but empty analysis
        if total_found > 0 && analyzed_count == 0
            return (true, total_found, analyzed_count, drug_name)
        end
        
        return (false, total_found, analyzed_count, drug_name)
        
    catch e
        filename = basename(file_path)
        drug_name = replace(split(filename, ".")[1], "_" => " ")
        return (false, 0, 0, drug_name)
    end
end

function main()
    println("🔍 Identifying files with empty publications_analyzed arrays...")
    
    json_dir = "phase1_drug_pubmed_refs"
    if !isdir(json_dir)
        println("❌ Error: Directory $json_dir not found")
        exit(1)
    end
    
    json_files = [f for f in readdir(json_dir) if endswith(f, ".json")]
    println("📁 Found $(length(json_files)) JSON files to check")
    
    # Results tracking
    empty_results = String[]
    valid_results = String[]
    empty_details = Dict{String, Tuple{Int, Int}}()  # drug -> (total_found, analyzed)
    
    for (i, filename) in enumerate(json_files)
        file_path = joinpath(json_dir, filename)
        
        is_empty, total_found, analyzed_count, drug_name = check_empty_results(file_path)
        
        if is_empty
            push!(empty_results, drug_name)
            empty_details[drug_name] = (total_found, analyzed_count)
        else
            push!(valid_results, drug_name)
        end
        
        if i % 500 == 0
            println("  ✅ Checked $i / $(length(json_files)) files...")
        end
    end
    
    println("\n📊 Empty Results Summary:")
    println("❌ Files with empty publications_analyzed: $(length(empty_results))")
    println("✅ Files with valid data: $(length(valid_results))")
    
    if length(empty_results) > 0
        println("\n🔍 Empty results details (first 20):")
        for (i, drug) in enumerate(empty_results[1:min(20, length(empty_results))])
            total_found, analyzed = empty_details[drug]
            println("  • $drug: $total_found publications found, $analyzed analyzed")
        end
        
        if length(empty_results) > 20
            println("  ... and $(length(empty_results) - 20) more")
        end
        
        # Write empty results to file
        println("\n📝 Writing drugs with empty results to file...")
        open("empty_results_drugs.txt", "w") do f
            for drug in empty_results
                println(f, drug)
            end
        end
        
        println("✅ Written $(length(empty_results)) drug names with empty results to empty_results_drugs.txt")
        
        # Show statistics
        total_pubs_missed = sum(empty_details[drug][1] for drug in empty_results)
        println("📊 Total publications that need to be retrieved: $total_pubs_missed")
    else
        println("\n🎉 No files with empty results found!")
    end
    
    return length(empty_results)
end

# Run the check
empty_count = main()
println("\nExit code: $empty_count files with empty results found")