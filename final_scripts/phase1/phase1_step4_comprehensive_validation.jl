#!/usr/bin/env julia

# Comprehensive validation of final Phase 1 PubMed dataset
# Checks for publications and MeSH descriptors where available

using JSON3

function validate_file_comprehensive(file_path::String)
    """
    Comprehensive validation of a JSON file
    Returns: (status, details) where status is one of: valid, empty_results, no_mesh, corrupted, missing_data
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
            return ("corrupted", "missing_result_key", drug_name, 0, 0, 0)
        end
        
        result = data.result
        
        if !haskey(result, "total_publications_found") || !haskey(result, "publications_analyzed")
            return ("corrupted", "missing_required_fields", drug_name, 0, 0, 0)
        end
        
        total_found = result.total_publications_found
        pubs_analyzed = result.publications_analyzed
        
        # Get the count regardless of array type
        analyzed_count = length(pubs_analyzed)
        
        # Check for empty results (publications found but none analyzed)
        if total_found > 0 && analyzed_count == 0
            return ("empty_results", "publications_found_but_none_analyzed", drug_name, total_found, analyzed_count, 0)
        end
        
        # If no publications found, that's valid (some drugs genuinely have no publications)
        if total_found == 0 && analyzed_count == 0
            return ("valid", "no_publications_found", drug_name, total_found, analyzed_count, 0)
        end
        
        # For files with publications, validate structure and count MeSH descriptors
        mesh_count = 0
        publications_with_mesh = 0
        
        if analyzed_count > 0
            sample_pub = pubs_analyzed[1]
            
            # Check required fields in publications
            required_fields = ["pmid", "title", "abstract", "mesh_descriptors"]
            for field in required_fields
                if !haskey(sample_pub, field)
                    return ("corrupted", "missing_$field", drug_name, total_found, analyzed_count, 0)
                end
            end
            
            # Count total MeSH descriptors across all publications
            for pub in pubs_analyzed
                if haskey(pub, "mesh_descriptors")
                    mesh_descriptors = pub.mesh_descriptors
                    mesh_count += length(mesh_descriptors)
                    if length(mesh_descriptors) > 0
                        publications_with_mesh += 1
                    end
                end
            end
        end
        
        # Classify based on MeSH availability
        if analyzed_count > 0 && mesh_count == 0
            return ("no_mesh", "no_mesh_descriptors_found", drug_name, total_found, analyzed_count, mesh_count)
        else
            return ("valid", "complete_with_data", drug_name, total_found, analyzed_count, mesh_count)
        end
        
    catch e
        filename = basename(file_path)
        drug_name = replace(split(filename, ".")[1], "_" => " ")
        return ("corrupted", "json_parse_error: $e", drug_name, 0, 0, 0)
    end
end

function main()
    println("🔍 Starting comprehensive validation of final Phase 1 PubMed dataset...")
    
    json_dir = "phase1_drug_pubmed_refs"
    if !isdir(json_dir)
        println("❌ Error: Directory $json_dir not found")
        exit(1)
    end
    
    json_files = [f for f in readdir(json_dir) if endswith(f, ".json")]
    println("📁 Found $(length(json_files)) JSON files to validate")
    
    # Results tracking
    valid_files = String[]
    empty_results = String[]
    no_mesh_files = String[]
    corrupted_files = String[]
    
    validation_details = Dict{String, Dict}()
    
    total_publications = 0
    total_mesh_descriptors = 0
    
    for (i, filename) in enumerate(json_files)
        file_path = joinpath(json_dir, filename)
        
        status, reason, drug_name, total_found, analyzed_count, mesh_count = validate_file_comprehensive(file_path)
        
        validation_details[drug_name] = Dict(
            "status" => status,
            "reason" => reason,
            "total_found" => total_found,
            "analyzed_count" => analyzed_count,
            "mesh_count" => mesh_count
        )
        
        if status == "valid"
            push!(valid_files, drug_name)
            total_publications += analyzed_count
            total_mesh_descriptors += mesh_count
        elseif status == "empty_results"
            push!(empty_results, drug_name)
        elseif status == "no_mesh"
            push!(no_mesh_files, drug_name)
            total_publications += analyzed_count
        elseif status == "corrupted"
            push!(corrupted_files, drug_name)
        end
        
        if i % 500 == 0
            println("  ✅ Validated $i / $(length(json_files)) files...")
        end
    end
    
    println("\n📊 Final Dataset Validation Summary:")
    println("✅ Valid files with data and MeSH: $(length(valid_files))")
    println("📄 Valid files with publications but no MeSH: $(length(no_mesh_files))")
    println("❌ Files with empty results: $(length(empty_results))")
    println("💥 Corrupted files: $(length(corrupted_files))")
    println("📋 Total files: $(length(json_files))")
    
    println("\n📈 Dataset Statistics:")
    println("📚 Total publications retrieved: $total_publications")
    println("🏷️  Total MeSH descriptors: $total_mesh_descriptors")
    println("📊 Average publications per drug: $(round(total_publications / length(valid_files + no_mesh_files), digits=1))")
    println("🏷️  Average MeSH per publication: $(total_publications > 0 ? round(total_mesh_descriptors / total_publications, digits=1) : 0)")
    
    if length(empty_results) > 0
        println("\n❌ Remaining empty results (first 10):")
        for drug in empty_results[1:min(10, length(empty_results))]
            details = validation_details[drug]
            println("  • $drug: $(details["total_found"]) publications found, $(details["analyzed_count"]) analyzed")
        end
        if length(empty_results) > 10
            println("  ... and $(length(empty_results) - 10) more")
        end
    end
    
    if length(corrupted_files) > 0
        println("\n💥 Corrupted files (first 10):")
        for drug in corrupted_files[1:min(10, length(corrupted_files))]
            details = validation_details[drug]
            println("  • $drug: $(details["reason"])")
        end
        if length(corrupted_files) > 10
            println("  ... and $(length(corrupted_files) - 10) more")
        end
    end
    
    # Calculate completion rate
    complete_rate = (length(valid_files) + length(no_mesh_files)) / length(json_files) * 100
    println("\n🎯 Dataset Completion Rate: $(round(complete_rate, digits=1))%")
    
    println("\n🎉 Comprehensive validation complete!")
    return (length(empty_results), length(corrupted_files))
end

# Run the comprehensive validation
empty_count, corrupted_count = main()
println("Exit code: $(empty_count + corrupted_count) problematic files found")