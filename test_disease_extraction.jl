#!/usr/bin/env julia

"""
Simple test program to extract disease publications from the drug file
Focus: Just retrieve PMID, title, abstract for each disease
"""

using JSON3

function extract_disease_publications(drug_name::String)
    """
    Extract publications for each disease from the drug file
    Returns a dictionary mapping disease names to their publication data
    """
    println("🔍 Extracting disease publications for $drug_name...")
    
    # Load the drug data file
    drug_file = "/oscar/home/isarkar/sarkarcode/thera/drug_pubmed_refs/$drug_name.json"
    
    if !isfile(drug_file)
        println("❌ Drug file not found: $drug_file")
        return Dict()
    end
    
    # Parse the drug data
    println("📖 Loading drug data...")
    data = JSON3.read(read(drug_file, String))
    
    # Create a lookup for publications by PMID to get abstracts
    publications_by_pmid = Dict{String, Any}()
    if haskey(data.result, "publications_analyzed")
        for pub in data.result.publications_analyzed
            pmid = get(pub, "pmid", "")
            if !isempty(pmid)
                publications_by_pmid[String(pmid)] = pub
            end
        end
        println("📚 Loaded $(length(publications_by_pmid)) publications with abstracts")
    end
    
    # Extract disease publications
    disease_publications = Dict{String, Vector{Dict{String, Any}}}()
    
    if haskey(data.result, "disease_analysis") && haskey(data.result.disease_analysis, "disease_associations")
        disease_associations = data.result.disease_analysis.disease_associations
        
        println("📊 Found $(length(disease_associations)) MeSH disease associations")
        
        # Extract publications for each disease
        total_publications = 0
        for (disease, disease_info) in pairs(disease_associations)
            disease_name = String(disease)
            publications = Vector{Dict{String, Any}}()
            
            # Extract each publication entry
            for entry in disease_info
                pub_data = Dict{String, Any}()
                
                if haskey(entry, "pmid")
                    pmid = String(entry["pmid"])
                    pub_data["pmid"] = pmid
                    
                    # Try to get abstract from main publications
                    if haskey(publications_by_pmid, pmid)
                        main_pub = publications_by_pmid[pmid]
                        if haskey(main_pub, "abstract")
                            pub_data["abstract"] = String(main_pub["abstract"])
                        end
                    end
                end
                
                if haskey(entry, "title")
                    pub_data["title"] = String(entry["title"])
                end
                
                if haskey(entry, "qualifiers")
                    pub_data["qualifiers"] = [String(q) for q in entry["qualifiers"]]
                end
                
                push!(publications, pub_data)
                total_publications += 1
            end
            
            disease_publications[disease_name] = publications
        end
        
        println("✅ Extracted $(total_publications) publications across $(length(disease_publications)) diseases")
        return disease_publications
        
    else
        println("❌ No disease_associations found in data structure")
        return Dict()
    end
end

function display_sample_data(disease_publications::Dict, max_diseases::Int=5, max_pubs_per_disease::Int=2)
    """
    Display a sample of the extracted disease publication data
    """
    println("\n📋 Sample of extracted data:")
    
    count = 0
    for (disease_name, publications) in disease_publications
        println("\n🔍 Disease: $disease_name")
        println("  📚 Total publications: $(length(publications))")
        
        # Show sample publications
        for (i, pub) in enumerate(publications)
            if i > max_pubs_per_disease
                break
            end
            
            println("    Publication $i:")
            println("      PMID: $(get(pub, "pmid", "N/A"))")
            println("      Title: $(get(pub, "title", "N/A"))")
            if haskey(pub, "abstract")
                abstract_text = get(pub, "abstract", "")
                if !isempty(abstract_text)
                    # Truncate abstract if too long for display
                    display_abstract = length(abstract_text) > 200 ? abstract_text[1:200] * "..." : abstract_text
                    println("      Abstract: $display_abstract")
                else
                    println("      Abstract: [No abstract available]")
                end
            else
                println("      Abstract: [No abstract available]")
            end
            println("      Qualifiers: $(get(pub, "qualifiers", []))")
            println("      ---")
        end
        
        count += 1
        if count >= max_diseases
            println("\n... (showing first $max_diseases diseases)")
            break
        end
    end
end

function generate_summary(disease_publications::Dict)
    """
    Generate a summary of the extracted data
    """
    println("\n📊 EXTRACTION SUMMARY:")
    println("=" ^ 50)
    
    total_diseases = length(disease_publications)
    total_publications = sum(length(pubs) for pubs in values(disease_publications))
    
    println("🎯 Total diseases with publications: $total_diseases")
    println("📚 Total publications extracted: $total_publications")
    
    if total_diseases > 0
        avg_pubs_per_disease = round(total_publications / total_diseases, digits=1)
        println("📈 Average publications per disease: $avg_pubs_per_disease")
        
        # Find diseases with most/least publications
        pub_counts = [(disease, length(pubs)) for (disease, pubs) in disease_publications]
        sort!(pub_counts, by=x->x[2], rev=true)
        
        println("\n🏆 Top 5 diseases by publication count:")
        for (i, (disease, count)) in enumerate(pub_counts[1:min(5, length(pub_counts))])
            println("  $i. $disease: $count publications")
        end
    end
    
    return disease_publications
end

function display_first_publications(disease_publications::Dict, max_diseases::Int=10)
    """
    Display the first publication (title and abstract) for each disease
    """
    println("\n📋 FIRST PUBLICATION FOR EACH DISEASE:")
    println("=" ^ 60)
    
    count = 0
    for (disease_name, publications) in disease_publications
        if isempty(publications)
            continue
        end
        
        first_pub = publications[1]
        
        println("\n🔍 Disease: $disease_name")
        println("   PMID: $(get(first_pub, "pmid", "N/A"))")
        println("   Title: $(get(first_pub, "title", "N/A"))")
        
        if haskey(first_pub, "abstract")
            abstract_text = get(first_pub, "abstract", "")
            if !isempty(abstract_text)
                println("   Abstract: $abstract_text")
            else
                println("   Abstract: [No abstract available]")
            end
        else
            println("   Abstract: [No abstract available]")
        end
        
        println("   Qualifiers: $(get(first_pub, "qualifiers", []))")
        println("   " * "-" ^ 50)
        
        count += 1
        if count >= max_diseases
            println("\n... (showing first $max_diseases diseases)")
            break
        end
    end
end

# Run the extraction
if length(ARGS) > 0
    drug_name = ARGS[1]
else
    drug_name = "Levothyroxine"
end

# Extract the data
disease_publications = extract_disease_publications(drug_name)

# Display sample and summary
if !isempty(disease_publications)
    display_sample_data(disease_publications)
    generate_summary(disease_publications)
    display_first_publications(disease_publications)
else
    println("❌ No publications extracted")
end