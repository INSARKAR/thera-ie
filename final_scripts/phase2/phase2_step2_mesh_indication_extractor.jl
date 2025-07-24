#!/usr/bin/env julia

# Phase 2 Step 2: MeSH-Based Indication Extraction Worker
# Extracts unique MeSH descriptors as indications from Phase 1 filtered publications
# Usage: julia phase2_step2_mesh_indication_extractor.jl <start_index> <batch_size>

using JSON3, Dates

# Get the job parameters
if length(ARGS) != 2
    println("Usage: julia phase2_step2_mesh_indication_extractor.jl <start_index> <batch_size>")
    exit(1)
end

start_index = parse(Int, ARGS[1])
batch_size = parse(Int, ARGS[2])

println("Starting Phase 2 Step 2: MeSH Indication Extraction")
println("  Start index: $start_index")
println("  Batch size: $batch_size")

# Get all JSON files to process from Phase 1 MeSH filtered results
input_dir = "phase1_drug_pubmed_mesh"
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
output_dir = "phase2_indications_mesh"
mkpath(output_dir)

function extract_mesh_indications(input_file::String)
    """
    Extract unique MeSH descriptors as indications from Phase 1 filtered publications
    """
    
    try
        # Read input file
        input_path = joinpath(input_dir, input_file)
        content = read(input_path, String)
        data = JSON3.read(content)
        
        drug_name = data.drug_name
        println("🔍 Processing $drug_name...")
        
        # Get MeSH organized publications
        mesh_organized_publications = data.result.mesh_organized_publications
        
        if isempty(mesh_organized_publications)
            println("  ⚪ $drug_name: No MeSH organized publications")
            
            # Create output with empty results
            result = Dict(
                "drug_name" => drug_name,
                "timestamp" => string(now()),
                "phase1_source" => "phase1_drug_pubmed_mesh/$input_file",
                "result" => Dict(
                    "total_mesh_indications" => 0,
                    "mesh_indications" => []
                )
            )
            
            return result
        end
        
        # Extract unique MeSH descriptors and count supporting publications
        mesh_indications = []
        
        for (mesh_descriptor, publications) in mesh_organized_publications
            # Count publications and collect PMIDs
            publication_count = length(publications)
            supporting_pmids = [pub.pmid for pub in publications]
            
            # Create indication entry
            indication = Dict(
                "mesh_descriptor" => mesh_descriptor,
                "publication_count" => publication_count,
                "supporting_pmids" => supporting_pmids
            )
            
            push!(mesh_indications, indication)
        end
        
        # Sort by publication count (highest first)
        sort!(mesh_indications, by = x -> x["publication_count"], rev = true)
        
        total_indications = length(mesh_indications)
        println("  📊 $drug_name: Extracted $total_indications unique MeSH indications")
        
        # Create final result
        result = Dict(
            "drug_name" => drug_name,
            "timestamp" => string(now()),
            "phase1_source" => "phase1_drug_pubmed_mesh/$input_file",
            "result" => Dict(
                "total_mesh_indications" => total_indications,
                "mesh_indications" => mesh_indications
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
println("🚀 Starting MeSH indication extraction...")

global processed_count = 0
global failed_count = 0

for input_file in files_to_process
    global processed_count, failed_count
    try
        result = extract_mesh_indications(input_file)
        
        if result !== nothing
            # Write extracted indications
            output_file = joinpath(output_dir, input_file)
            open(output_file, "w") do f
                JSON3.pretty(f, result)
            end
            
            drug_name = result["drug_name"]
            indication_count = result["result"]["total_mesh_indications"]
            
            processed_count += 1
            println("✅ $drug_name: Saved $indication_count MeSH indications")
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

println("\n🎉 Phase 2 Step 2 MeSH indication extraction completed!")
println("✅ Successfully processed: $processed_count files")
println("❌ Failed: $failed_count files")
println("📂 Output saved in: $output_dir/")
println("📊 Processing rate: $(round(processed_count/(processed_count+failed_count)*100, digits=1))%")