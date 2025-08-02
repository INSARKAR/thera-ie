#!/usr/bin/env julia

"""
Analyze PubMed Corpus Statistics for Methods Section

Extract comprehensive statistics from Phase 1 PubMed data to fill in 
the missing values in the methods paragraph.
"""

using JSON3, Dates, Statistics

function analyze_pubmed_corpus()
    println("📊 Analyzing PubMed Corpus Statistics")
    println("=" ^ 50)
    
    # Load Phase 1 PubMed data
    phase1_dir = "phase1_step2_pubmed_extraction"
    
    if !isdir(phase1_dir)
        println("❌ Phase 1 directory not found: $phase1_dir")
        return
    end
    
    total_publications_found = 0
    total_publications_retrieved = 0
    drug_publication_counts = []
    all_mesh_descriptors = Set{String}()
    publication_years = []
    
    drugs_analyzed = []
    
    for file in readdir(phase1_dir)
        if endswith(file, "_pubmed.json")
            drug_name = replace(file, "_pubmed.json" => "")
            push!(drugs_analyzed, drug_name)
            file_path = joinpath(phase1_dir, file)
            
            try
                data = JSON3.read(read(file_path, String))
                
                # Extract publication statistics
                if haskey(data, "result")
                    result = data["result"]
                    found = get(result, "total_publications_found", 0)
                    retrieved = get(result, "publications_retrieved", 0)
                    
                    total_publications_found += found
                    total_publications_retrieved += retrieved
                    push!(drug_publication_counts, retrieved)
                    
                    println("📚 $drug_name: $found found, $retrieved retrieved")
                    
                    # Analyze publications
                    if haskey(result, "publications")
                        for pub in result["publications"]
                            # Extract publication year
                            pub_date = get(pub, "publication_date", "")
                            if !isempty(pub_date)
                                # Try to extract year (handle various formats)
                                year_match = match(r"(\d{4})", pub_date)
                                if year_match !== nothing
                                    year = parse(Int, year_match.captures[1])
                                    push!(publication_years, year)
                                end
                            end
                            
                            # Extract MeSH descriptors
                            mesh_descriptors = get(pub, "mesh_descriptors", [])
                            for mesh_desc in mesh_descriptors
                                mesh_name = get(mesh_desc, "name", "")
                                if !isempty(mesh_name)
                                    push!(all_mesh_descriptors, mesh_name)
                                end
                            end
                        end
                    end
                end
                
            catch e
                println("⚠️ Error processing $file: $e")
            end
        end
    end
    
    # Calculate statistics
    retention_rate = total_publications_found > 0 ? (total_publications_retrieved / total_publications_found) * 100 : 0.0
    
    min_pubs = minimum(drug_publication_counts)
    max_pubs = maximum(drug_publication_counts)
    mean_pubs = mean(drug_publication_counts)
    std_pubs = std(drug_publication_counts)
    
    total_mesh_categories = length(all_mesh_descriptors)
    
    # Analyze temporal distribution (last 10 years)
    current_year = 2025
    recent_years = filter(y -> y >= (current_year - 10), publication_years)
    recent_percentage = length(publication_years) > 0 ? (length(recent_years) / length(publication_years)) * 100 : 0.0
    
    # Print results
    println("\n📊 CORPUS STATISTICS:")
    println("=" ^ 50)
    println("Total publications found: $(format_number(total_publications_found))")
    println("Total publications retrieved: $(format_number(total_publications_retrieved))")
    println("Retention rate: $(round(retention_rate, digits=1))%")
    println("Drugs analyzed: $(length(drugs_analyzed))")
    println("")
    
    println("📈 PER-DRUG STATISTICS:")
    println("Minimum publications: $(format_number(min_pubs))")
    println("Maximum publications: $(format_number(max_pubs))")
    println("Mean publications: $(round(mean_pubs, digits=0)) ± $(round(std_pubs, digits=0))")
    println("")
    
    println("🏷️ MESH DESCRIPTORS:")
    println("Total unique MeSH descriptors: $(format_number(total_mesh_categories))")
    println("")
    
    println("📅 TEMPORAL DISTRIBUTION:")
    println("Total publications with dates: $(length(publication_years))")
    println("Publications from last 10 years: $(length(recent_years))")
    println("Recent publications percentage: $(round(recent_percentage, digits=1))%")
    
    # Generate filled paragraph
    println("\n📝 FILLED PARAGRAPH:")
    println("=" ^ 80)
    
    filled_paragraph = """
The systematic search strategy across $(length(drugs_analyzed)) target drugs yielded a substantial corpus of biomedical literature for analysis. PubMed queries based on drug name and MeSH term co-occurrence identified a total of $(format_number(total_publications_found)) publications. After applying filtering criteria requiring disease/condition MeSH descriptors with therapeutic use qualifiers, $(format_number(total_publications_retrieved)) publications were retained for processing, representing $(round(retention_rate, digits=1))% of the initial retrieval set. The filtered corpus provided comprehensive coverage across diverse therapeutic areas, with individual drug datasets ranging from $(format_number(min_pubs)) to $(format_number(max_pubs)) publications per drug (mean: $(round(mean_pubs, digits=0)) ± $(round(std_pubs, digits=0))). Publications were distributed across $(format_number(total_mesh_categories)) distinct disease/condition MeSH descriptor categories, enabling systematic evaluation of therapeutic relationships across multiple medical specialties. The temporal distribution of retrieved articles showed $(round(recent_percentage, digits=1))% published within the last 10 years, ensuring contemporary clinical relevance while maintaining historical therapeutic knowledge coverage. This literature corpus served as the foundation for both the traditional MeSH-based analysis and the novel LLM-based indication extraction approaches, providing a robust dataset for comparative evaluation of therapeutic knowledge discovery methodologies.
"""
    
    println(filled_paragraph)
    
    # Save results
    results = Dict(
        "analysis_date" => string(now()),
        "total_publications_found" => total_publications_found,
        "total_publications_retrieved" => total_publications_retrieved,
        "retention_rate_percent" => retention_rate,
        "drugs_analyzed" => length(drugs_analyzed),
        "drug_names" => drugs_analyzed,
        "per_drug_statistics" => Dict(
            "minimum_publications" => min_pubs,
            "maximum_publications" => max_pubs,
            "mean_publications" => mean_pubs,
            "std_publications" => std_pubs,
            "individual_counts" => drug_publication_counts
        ),
        "mesh_statistics" => Dict(
            "total_unique_descriptors" => total_mesh_categories
        ),
        "temporal_statistics" => Dict(
            "total_with_dates" => length(publication_years),
            "recent_publications" => length(recent_years),
            "recent_percentage" => recent_percentage
        ),
        "filled_paragraph" => filled_paragraph
    )
    
    open("pubmed_corpus_analysis.json", "w") do f
        JSON3.pretty(f, results)
    end
    
    println("\n✅ Analysis saved to: pubmed_corpus_analysis.json")
end

function format_number(n::Number)
    """Format number with commas for readability"""
    return replace(string(round(Int, n)), r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => ",")
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    analyze_pubmed_corpus()
end