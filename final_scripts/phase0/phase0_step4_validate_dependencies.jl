#!/usr/bin/env julia

# Phase 0 Step 4: Dependency File Validation
# Validates all generated dependency files are complete and ready for Phase 1

using Dates

println("🚀 Phase 0 Step 4: Dependency File Validation")
println("📋 Validating generated dependency files for Phase 1 readiness")
println("⏰ Started at: $(now())\n")

validation_passed = true
error_messages = String[]

# Check directory structure
dependency_dir = "generated_dependency_files"
if !isdir(dependency_dir)
    push!(error_messages, "❌ Generated dependency directory not found: $dependency_dir")
    validation_passed = false
else
    println("✅ Dependency directory exists: $dependency_dir")
end

# Validate approved_drugs_dict.jl
drugs_dict_file = joinpath(dependency_dir, "approved_drugs_dict.jl")
if !isfile(drugs_dict_file)
    push!(error_messages, "❌ Approved drugs dictionary not found: $drugs_dict_file")
    validation_passed = false
else
    try
        println("🔍 Validating approved_drugs_dict.jl...")
        include(drugs_dict_file)
        
        if @isdefined(APPROVED_DRUGS_DICT)
            drug_count = length(APPROVED_DRUGS_DICT)
            println("✅ Approved drugs dictionary loaded: $drug_count drugs")
            
            # Check for sample entries
            sample_drugs = collect(keys(APPROVED_DRUGS_DICT))[1:min(3, drug_count)]
            for drug in sample_drugs
                indication_length = length(APPROVED_DRUGS_DICT[drug])
                println("  📋 $drug: $(indication_length) characters of indication text")
            end
            
            if drug_count < 1000
                push!(error_messages, "⚠️  Warning: Only $drug_count drugs found (expected >2000)")
            end
        else
            push!(error_messages, "❌ APPROVED_DRUGS_DICT constant not defined in $drugs_dict_file")
            validation_passed = false
        end
    catch e
        push!(error_messages, "❌ Error loading $drugs_dict_file: $e")
        validation_passed = false
    end
end

# Validate mesh_semantic_headings.jl  
mesh_file = joinpath(dependency_dir, "mesh_semantic_headings.jl")
if !isfile(mesh_file)
    push!(error_messages, "❌ MeSH semantic headings not found: $mesh_file")
    validation_passed = false
else
    try
        println("🔍 Validating mesh_semantic_headings.jl...")
        include(mesh_file)
        
        if @isdefined(get_mesh_semantic_headings)
            mesh_headings = get_mesh_semantic_headings()
            mesh_count = length(mesh_headings)
            println("✅ MeSH semantic headings loaded: $mesh_count headings")
            
            # Check for sample entries
            sample_mesh = collect(mesh_headings)[1:min(3, mesh_count)]
            for mesh in sample_mesh
                println("  📋 $mesh")
            end
            
            if mesh_count < 1000
                push!(error_messages, "⚠️  Warning: Only $mesh_count MeSH headings found (expected >5000)")
            end
        else
            push!(error_messages, "❌ get_mesh_semantic_headings function not defined in $mesh_file")
            validation_passed = false
        end
    catch e
        push!(error_messages, "❌ Error loading $mesh_file: $e")
        validation_passed = false
    end
end

# Check optional JSON and CSV formats
json_file = joinpath(dependency_dir, "approved_drugs_dict.json")
csv_file = joinpath(dependency_dir, "approved_drugs_list.csv") 
txt_file = joinpath(dependency_dir, "mesh_semantic_headings.txt")

for (file, desc) in [(json_file, "JSON drugs"), (csv_file, "CSV drugs"), (txt_file, "TXT MeSH")]
    if isfile(file)
        println("✅ Optional format exists: $desc -> $(basename(file))")
    else
        println("ℹ️  Optional format missing: $desc -> $(basename(file))")
    end
end

# Final validation report
println("\n" * "="^60)
println("📊 PHASE 0 DEPENDENCY VALIDATION REPORT")
println("="^60)

if validation_passed
    println("🎉 ✅ ALL DEPENDENCIES VALIDATED SUCCESSFULLY!")
    println("")
    println("📋 Phase 1 Prerequisites Met:")
    println("  ✅ Approved drugs dictionary available")
    println("  ✅ MeSH semantic headings available") 
    println("  ✅ Generated files are properly formatted")
    println("  ✅ Required functions are defined")
    println("")
    println("🚀 Ready to proceed with Phase 1: PubMed Extraction")
else
    println("❌ VALIDATION FAILED - Issues found:")
    for msg in error_messages
        println("  $msg")
    end
    println("")
    println("🔧 Please fix the above issues before proceeding to Phase 1")
    exit(1)
end

println("")
println("⏰ Completed at: $(now())")
println("="^60)