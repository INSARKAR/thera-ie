#!/usr/bin/env julia

"""
Generate PubMed MeSH Descriptor Analysis Table

This script analyzes Phase 2 Step 3 PubMed results to generate comprehensive tables showing:
1. Volume of publications per MeSH descriptor per drug
2. Disease/condition distribution across drugs
3. MeSH descriptor frequency analysis
4. Per-drug breakdown of literature evidence

Output formats:
- CSV tables for analysis
- JSON summary for detailed inspection
- Text report for human reading
"""

using JSON3, CSV, DataFrames, Dates

function load_phase1_mesh_data()
    """Load Phase 1 MeSH extraction results to get publication volumes"""
    
    mesh_data = Dict{String, Dict{String, Int}}()  # drug -> mesh_descriptor -> count
    
    # Check if Phase 1 PubMed results exist
    phase1_dir = "phase1_step2_pubmed_extraction"
    
    if !isdir(phase1_dir)
        println("⚠️ Phase 1 PubMed directory not found: $phase1_dir")
        return mesh_data
    end
    
    # Load PubMed data for each drug
    for file in readdir(phase1_dir)
        if endswith(file, "_pubmed.json")
            drug_name = replace(file, "_pubmed.json" => "")
            file_path = joinpath(phase1_dir, file)
            
            try
                data = JSON3.read(read(file_path, String))
                
                drug_mesh = Dict{String, Int}()
                
                # Extract MeSH descriptors from publications
                if haskey(data, "result") && haskey(data["result"], "publications")
                    for publication in data["result"]["publications"]
                        mesh_descriptors = get(publication, "mesh_descriptors", [])
                        
                        for mesh_desc in mesh_descriptors
                            mesh_name = get(mesh_desc, "name", "")
                            if !isempty(mesh_name)
                                drug_mesh[mesh_name] = get(drug_mesh, mesh_name, 0) + 1
                            end
                        end
                    end
                end
                
                mesh_data[drug_name] = drug_mesh
                println("📖 Loaded MeSH data for $drug_name: $(length(drug_mesh)) descriptors")
                
            catch e
                println("⚠️ Error loading $file: $e")
            end
        end
    end
    
    return mesh_data
end

function load_phase2_pubmed_results()
    """Load Phase 2 Step 3 PubMed SNOMED results"""
    
    pubmed_results = Dict{String, Any}()
    
    phase2_dir = "phase2_step3_pubmed_snomed"
    
    if !isdir(phase2_dir)
        println("⚠️ Phase 2 PubMed directory not found: $phase2_dir")
        return pubmed_results
    end
    
    for file in readdir(phase2_dir)
        if endswith(file, "_pubmed_snomed.json")
            drug_name = replace(file, "_pubmed_snomed.json" => "")
            file_path = joinpath(phase2_dir, file)
            
            try
                data = JSON3.read(read(file_path, String))
                pubmed_results[drug_name] = data
                
                indication_count = length(get(data, "snomed_indications", []))
                println("📚 Loaded PubMed results for $drug_name: $indication_count SNOMED indications")
                
            catch e
                println("⚠️ Error loading $file: $e")
            end
        end
    end
    
    return pubmed_results
end

function create_mesh_volume_table(mesh_data::Dict, pubmed_results::Dict)
    """Create comprehensive MeSH descriptor volume table"""
    
    # Collect all unique MeSH descriptors
    all_mesh_descriptors = Set{String}()
    for (drug, mesh_dict) in mesh_data
        for mesh_term in keys(mesh_dict)
            push!(all_mesh_descriptors, mesh_term)
        end
    end
    
    # Get all drugs
    all_drugs = sort(collect(keys(mesh_data)))
    
    println("📊 Creating table for $(length(all_drugs)) drugs and $(length(all_mesh_descriptors)) MeSH descriptors")
    
    # Create DataFrame for volume table
    volume_data = []
    
    for mesh_descriptor in sort(collect(all_mesh_descriptors))
        row = Dict("mesh_descriptor" => mesh_descriptor)
        
        total_publications = 0
        drugs_with_descriptor = 0
        
        for drug in all_drugs
            volume = get(get(mesh_data, drug, Dict()), mesh_descriptor, 0)
            row[drug] = string(volume)  # Convert to string for DataFrame
            
            if volume > 0
                total_publications += volume
                drugs_with_descriptor += 1
            end
        end
        
        row["total_publications"] = string(total_publications)
        row["drugs_with_descriptor"] = string(drugs_with_descriptor)
        row["avg_publications_per_drug"] = string(drugs_with_descriptor > 0 ? round(total_publications / drugs_with_descriptor, digits=1) : 0.0)
        
        push!(volume_data, row)
    end
    
    # Convert to DataFrame
    df_volume = DataFrame(volume_data)
    
    # Sort by total publications (descending)
    sort!(df_volume, :total_publications, rev=true)
    
    return df_volume, all_drugs
end

function create_drug_summary_table(mesh_data::Dict, pubmed_results::Dict)
    """Create per-drug summary table"""
    
    drug_summary = []
    
    for drug in sort(collect(keys(mesh_data)))
        drug_mesh = get(mesh_data, drug, Dict())
        pubmed_data = get(pubmed_results, drug, Dict())
        
        # Calculate statistics
        total_mesh_descriptors = length(drug_mesh)
        total_publications = sum(values(drug_mesh))
        snomed_indications = length(get(pubmed_data, "snomed_indications", []))
        
        # Top MeSH descriptors for this drug
        sorted_mesh = sort(collect(drug_mesh), by=x->x[2], rev=true)
        top_3_mesh = [mesh_term for (mesh_term, count) in sorted_mesh[1:min(3, length(sorted_mesh))]]
        
        # Average publications per MeSH descriptor
        avg_pubs_per_mesh = total_mesh_descriptors > 0 ? round(total_publications / total_mesh_descriptors, digits=1) : 0.0
        
        push!(drug_summary, Dict(
            "drug_name" => drug,
            "total_mesh_descriptors" => total_mesh_descriptors,
            "total_publications" => total_publications,
            "snomed_indications_extracted" => snomed_indications,
            "avg_publications_per_mesh" => avg_pubs_per_mesh,
            "top_mesh_descriptor_1" => length(top_3_mesh) >= 1 ? top_3_mesh[1] : "",
            "top_mesh_descriptor_2" => length(top_3_mesh) >= 2 ? top_3_mesh[2] : "",
            "top_mesh_descriptor_3" => length(top_3_mesh) >= 3 ? top_3_mesh[3] : "",
            "extraction_efficiency" => total_publications > 0 ? round(snomed_indications / total_publications * 100, digits=1) : 0.0
        ))
    end
    
    df_drug_summary = DataFrame(drug_summary)
    sort!(df_drug_summary, :total_publications, rev=true)
    
    return df_drug_summary
end

function create_mesh_category_analysis(mesh_data::Dict)
    """Analyze MeSH descriptors by medical categories"""
    
    # Common medical condition patterns
    categories = Dict(
        "Cardiovascular" => ["hypertension", "heart", "cardiac", "coronary", "vascular", "atherosclerosis", "myocardial", "arrhythmia"],
        "Endocrine/Metabolic" => ["diabetes", "thyroid", "hormone", "metabolic", "insulin", "glucose", "cholesterol", "lipid"],
        "Neurological" => ["alzheimer", "dementia", "seizure", "epilepsy", "migraine", "neuralgia", "neuropathy", "brain"],
        "Respiratory" => ["asthma", "copd", "broncho", "pulmonary", "respiratory", "lung"],
        "Gastrointestinal" => ["gastro", "peptic", "ulcer", "reflux", "hepatic", "liver", "digestive"],
        "Psychiatric" => ["depression", "anxiety", "bipolar", "schizo", "psychiatric", "mental"],
        "Infectious" => ["infection", "bacterial", "viral", "fungal", "sepsis", "pneumonia"],
        "Cancer/Oncology" => ["cancer", "tumor", "carcinoma", "neoplasm", "malignant", "oncology"],
        "Other" => []
    )
    
    category_counts = Dict{String, Dict{String, Int}}()
    
    for (drug, mesh_dict) in mesh_data
        drug_categories = Dict{String, Int}()
        
        for (mesh_term, count) in mesh_dict
            mesh_lower = lowercase(mesh_term)
            categorized = false
            
            for (category, keywords) in categories
                if category == "Other"
                    continue
                end
                
                for keyword in keywords
                    if contains(mesh_lower, keyword)
                        drug_categories[category] = get(drug_categories, category, 0) + count
                        categorized = true
                        break
                    end
                end
                
                if categorized
                    break
                end
            end
            
            if !categorized
                drug_categories["Other"] = get(drug_categories, "Other", 0) + count
            end
        end
        
        category_counts[drug] = drug_categories
    end
    
    # Create category summary table
    category_data = []
    all_categories = collect(keys(categories))
    
    for category in all_categories
        row = Dict("category" => category)
        
        total_publications = 0
        drugs_with_category = 0
        
        for drug in sort(collect(keys(category_counts)))
            count = get(get(category_counts, drug, Dict()), category, 0)
            row[drug] = count
            
            if count > 0
                total_publications += count
                drugs_with_category += 1
            end
        end
        
        row["total_publications"] = total_publications
        row["drugs_with_category"] = drugs_with_category
        
        push!(category_data, row)
    end
    
    df_categories = DataFrame(category_data)
    sort!(df_categories, :total_publications, rev=true)
    
    return df_categories
end

function main()
    println("📊 THERA-IE PubMed MeSH Descriptor Analysis")
    println("📅 Started: $(now())")
    
    # Create output directory
    output_dir = "pubmed_mesh_analysis"
    mkpath(output_dir)
    
    # Load data
    println("\n🔍 Loading Phase 1 MeSH data...")
    mesh_data = load_phase1_mesh_data()
    
    println("\n🔍 Loading Phase 2 PubMed results...")
    pubmed_results = load_phase2_pubmed_results()
    
    if isempty(mesh_data)
        println("❌ No MeSH data found. Cannot generate analysis.")
        return
    end
    
    # Generate tables
    println("\n📊 Creating MeSH descriptor volume table...")
    df_volume, all_drugs = create_mesh_volume_table(mesh_data, pubmed_results)
    
    println("\n📊 Creating drug summary table...")
    df_drug_summary = create_drug_summary_table(mesh_data, pubmed_results)
    
    println("\n📊 Creating MeSH category analysis...")
    df_categories = create_mesh_category_analysis(mesh_data)
    
    # Save tables
    println("\n💾 Saving results...")
    
    # CSV exports
    CSV.write(joinpath(output_dir, "mesh_descriptor_volume_table.csv"), df_volume)
    CSV.write(joinpath(output_dir, "drug_summary_table.csv"), df_drug_summary)
    CSV.write(joinpath(output_dir, "mesh_category_analysis.csv"), df_categories)
    
    # JSON summary
    summary_data = Dict(
        "analysis_date" => string(now()),
        "total_drugs_analyzed" => length(all_drugs),
        "total_unique_mesh_descriptors" => nrow(df_volume),
        "total_publications_analyzed" => sum(df_volume.total_publications),
        "drugs_analyzed" => all_drugs,
        "top_10_mesh_descriptors" => [
            Dict("mesh_descriptor" => row.mesh_descriptor, 
                 "total_publications" => row.total_publications,
                 "drugs_with_descriptor" => row.drugs_with_descriptor)
            for row in eachrow(df_volume[1:min(10, nrow(df_volume)), :])
        ],
        "drug_statistics" => [
            Dict("drug" => row.drug_name,
                 "total_mesh_descriptors" => row.total_mesh_descriptors,
                 "total_publications" => row.total_publications,
                 "snomed_indications" => row.snomed_indications_extracted)
            for row in eachrow(df_drug_summary)
        ]
    )
    
    open(joinpath(output_dir, "pubmed_mesh_analysis_summary.json"), "w") do f
        JSON3.pretty(f, summary_data)
    end
    
    # Text report
    open(joinpath(output_dir, "pubmed_mesh_analysis_report.txt"), "w") do f
        println(f, "THERA-IE PubMed MeSH Descriptor Analysis Report")
        println(f, "=" ^ 60)
        println(f, "Generated: $(now())")
        println(f, "")
        
        println(f, "OVERVIEW:")
        println(f, "- Total drugs analyzed: $(length(all_drugs))")
        println(f, "- Unique MeSH descriptors: $(nrow(df_volume))")
        println(f, "- Total publications: $(sum(df_volume.total_publications))")
        println(f, "")
        
        println(f, "TOP 10 MESH DESCRIPTORS BY PUBLICATION VOLUME:")
        for (i, row) in enumerate(eachrow(df_volume[1:min(10, nrow(df_volume)), :]))
            println(f, "$i. $(row.mesh_descriptor) - $(row.total_publications) publications ($(row.drugs_with_descriptor) drugs)")
        end
        println(f, "")
        
        println(f, "DRUG SUMMARY (by publication volume):")
        for row in eachrow(df_drug_summary)
            println(f, "$(row.drug_name): $(row.total_publications) publications, $(row.total_mesh_descriptors) MeSH descriptors, $(row.snomed_indications_extracted) SNOMED indications")
        end
    end
    
    println("✅ Analysis complete!")
    println("📁 Results saved in: $output_dir/")
    println("  📊 mesh_descriptor_volume_table.csv - Full MeSH descriptor x drug matrix")
    println("  📊 drug_summary_table.csv - Per-drug statistics")
    println("  📊 mesh_category_analysis.csv - Medical category breakdown")
    println("  📄 pubmed_mesh_analysis_report.txt - Human-readable summary")
    println("  📋 pubmed_mesh_analysis_summary.json - Detailed JSON summary")
    
    # Quick statistics
    println("\n🎯 KEY FINDINGS:")
    println("📊 Most prolific MeSH descriptor: $(df_volume[1, :mesh_descriptor]) ($(df_volume[1, :total_publications]) publications)")
    println("📊 Drug with most MeSH descriptors: $(df_drug_summary[1, :drug_name]) ($(df_drug_summary[1, :total_mesh_descriptors]) descriptors)")
    println("📊 Drug with most publications: $(df_drug_summary[1, :drug_name]) ($(df_drug_summary[1, :total_publications]) publications)")
    println("📊 Average MeSH descriptors per drug: $(round(mean(df_drug_summary.total_mesh_descriptors), digits=1))")
    println("📊 Average publications per drug: $(round(mean(df_drug_summary.total_publications), digits=1))")
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main()
end