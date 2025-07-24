#!/usr/bin/env julia

# Phase 1 Step 5: MeSH Filtering and Reorganization Worker
# Filters publications by semantic relevance and frequency, then organizes by MeSH descriptor
# Usage: julia phase1_step5_mesh_filtering_worker.jl <start_index> <batch_size>

using JSON3, Dates

# Get the job parameters
if length(ARGS) != 2
    println("Usage: julia phase1_step5_mesh_filtering_worker.jl <start_index> <batch_size>")
    exit(1)
end

start_index = parse(Int, ARGS[1])
batch_size = parse(Int, ARGS[2])

println("Starting MeSH filtering worker:")
println("  Start index: $start_index")
println("  Batch size: $batch_size")

# Load semantic MeSH headings
include("mesh_semantic_headings.jl")
approved_mesh_descriptors = Set(get_mesh_semantic_headings())
println("📋 Loaded $(length(approved_mesh_descriptors)) approved MeSH descriptors")

# Get all JSON files to process
input_dir = "phase1_drug_pubmed_refs"
if !isdir(input_dir)
    println("❌ Error: Input directory $input_dir not found")
    exit(1)
end

json_files = [f for f in readdir(input_dir) if endswith(f, ".json")]
println("📁 Found $(length(json_files)) total drug files")

# Calculate the subset to process for this worker
end_index = min(start_index + batch_size - 1, length(json_files))
if start_index > length(json_files)
    println("Start index $start_index exceeds total files ($(length(json_files))). Nothing to process.")
    exit(0)
end

files_to_process = json_files[start_index:end_index]
println("Processing $(length(files_to_process)) files (indices $start_index to $end_index)")

# Create output directory
output_dir = "phase1_drug_pubmed_mesh"
mkpath(output_dir)

function filter_and_organize_by_mesh(input_file::String)
    """
    Apply semantic and frequency filtering, then organize publications by MeSH descriptor
    """
    
    try
        # Read input file
        input_path = joinpath(input_dir, input_file)
        content = read(input_path, String)
        data = JSON3.read(content)
        
        drug_name = data.drug_name
        println("🔍 Processing $drug_name...")
        
        # Get original publications
        original_publications = data.result.publications_analyzed
        total_found = data.result.total_publications_found
        
        if length(original_publications) == 0
            println("  ⚪ $drug_name: No publications to filter")
            
            # Create output with empty results
            result = Dict(
                "drug_name" => drug_name,
                "timestamp" => string(now()),
                "result" => Dict(
                    "total_publications_found" => total_found,
                    "publications_after_semantic_filter" => 0,
                    "publications_after_frequency_filter" => 0,
                    "mesh_organized_publications" => Dict(),
                    "filtering_note" => "no_publications_to_filter"
                )
            )
            
            return result
        end
        
        # Step 1: Semantic Filtering
        semantically_filtered = []
        for pub in original_publications
            pub_mesh = pub.mesh_descriptors
            # Check if publication has any approved MeSH descriptors
            if any(mesh in approved_mesh_descriptors for mesh in pub_mesh)
                push!(semantically_filtered, pub)
            end
        end
        
        println("  📊 $drug_name: $(length(original_publications)) → $(length(semantically_filtered)) after semantic filtering")
        
        if length(semantically_filtered) == 0
            println("  ❌ $drug_name: No publications with relevant MeSH descriptors")
            
            # Create output noting no relevant MeSH
            result = Dict(
                "drug_name" => drug_name,
                "timestamp" => string(now()),
                "result" => Dict(
                    "total_publications_found" => total_found,
                    "publications_after_semantic_filter" => 0,
                    "publications_after_frequency_filter" => 0,
                    "mesh_organized_publications" => Dict(),
                    "filtering_note" => "no_articles_with_relevant_mesh_descriptors"
                )
            )
            
            return result
        end
        
        # Step 2: Frequency Filtering (only if >5 publications)
        frequency_filtered = semantically_filtered  # Default: keep all
        filtering_note = "semantic_filtered_only"
        
        if length(semantically_filtered) > 5
            println("  📈 $drug_name: Applying frequency filtering (>5 publications)")
            
            # Count MeSH descriptor frequencies
            mesh_counts = Dict{String, Int}()
            for pub in semantically_filtered
                for mesh in pub.mesh_descriptors
                    if mesh in approved_mesh_descriptors
                        mesh_counts[mesh] = get(mesh_counts, mesh, 0) + 1
                    end
                end
            end
            
            # Calculate 1% threshold
            threshold = length(semantically_filtered) * 0.01
            println("  🎯 $drug_name: 1% threshold = $(threshold) ($(length(semantically_filtered)) publications)")
            
            # Find MeSH descriptors that meet frequency threshold
            frequent_mesh = Set([mesh for (mesh, count) in mesh_counts if count > threshold])
            println("  ✅ $drug_name: $(length(frequent_mesh)) MeSH descriptors meet >1% threshold")
            
            # Keep publications that have at least one frequent MeSH descriptor
            frequency_filtered = []
            for pub in semantically_filtered
                if any(mesh in frequent_mesh for mesh in pub.mesh_descriptors if mesh in approved_mesh_descriptors)
                    push!(frequency_filtered, pub)
                end
            end
            
            filtering_note = "semantic_and_frequency_filtered"
            println("  📊 $drug_name: $(length(semantically_filtered)) → $(length(frequency_filtered)) after frequency filtering")
        else
            println("  ⭐ $drug_name: ≤5 publications, keeping all semantically filtered")
        end
        
        # Step 3: Organize by MeSH descriptor
        mesh_organized = Dict{String, Vector}()
        
        for pub in frequency_filtered
            for mesh in pub.mesh_descriptors
                if mesh in approved_mesh_descriptors
                    # Add publication to this MeSH category
                    if !haskey(mesh_organized, mesh)
                        mesh_organized[mesh] = []
                    end
                    push!(mesh_organized[mesh], pub)
                end
            end
        end
        
        println("  🗂️  $drug_name: Publications organized into $(length(keys(mesh_organized))) MeSH categories")
        
        # Create final result
        result = Dict(
            "drug_name" => drug_name,
            "timestamp" => string(now()),
            "result" => Dict(
                "total_publications_found" => total_found,
                "publications_after_semantic_filter" => length(semantically_filtered),
                "publications_after_frequency_filter" => length(frequency_filtered),
                "mesh_organized_publications" => mesh_organized,
                "filtering_note" => filtering_note
            )
        )
        
        return result
        
    catch e
        drug_name = replace(split(input_file, ".")[1], "_" => " ")
        println("❌ Error processing $drug_name: $e")
        return nothing
    end
end

# Process each file in the batch
println("🚀 Starting MeSH filtering and organization...")

global processed_count = 0
global failed_count = 0

for input_file in files_to_process
    global processed_count, failed_count
    try
        result = filter_and_organize_by_mesh(input_file)
        
        if result !== nothing
            # Write filtered result
            output_file = joinpath(output_dir, input_file)
            open(output_file, "w") do f
                JSON3.pretty(f, result)
            end
            
            drug_name = result["drug_name"]
            mesh_categories = length(keys(result["result"]["mesh_organized_publications"]))
            filtered_pubs = result["result"]["publications_after_frequency_filter"]
            
            processed_count += 1
            println("✅ $drug_name: Saved with $filtered_pubs publications in $mesh_categories MeSH categories")
        else
            failed_count += 1
            println("❌ Failed to process $input_file")
        end
        
    catch e
        failed_count += 1
        println("💥 Error processing $input_file: $e")
        continue
    end
end

println("\n🎉 MeSH filtering worker completed!")
println("✅ Successfully processed: $processed_count files")
println("❌ Failed: $failed_count files")
println("📂 Output saved in: $output_dir/")
println("📊 Processing rate: $(round(processed_count/(processed_count+failed_count)*100, digits=1))%")