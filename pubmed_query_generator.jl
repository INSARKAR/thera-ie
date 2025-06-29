#!/usr/bin/env julia

"""
PubMed Search Query Generator

This program reads the approved drugs dictionary and generates PubMed search queries
for each drug. It creates various types of queries including basic drug searches,
drug-indication combinations, clinical trial searches, and mechanism of action queries.

Usage:
    julia pubmed_query_generator.jl

Output files:
    - pubmed_queries.txt (formatted search queries)
    - pubmed_queries.json (structured JSON format)
    - pubmed_urls.txt (direct PubMed URLs)
"""

using JSON
using Dates
using URIs

# Try to include the approved drugs dictionary
const DICT_FILES = [
    "approved_drugs_dict.jl",
    "direct_test.jl",
    "test_approved_drugs.jl",
    "filtered_approved_drugs.jl"
]

"""
    load_approved_drugs_dict() -> Dict{String, String}

Load the approved drugs dictionary from available files.
"""
function load_approved_drugs_dict()
    for dict_file in DICT_FILES
        if isfile(dict_file)
            println("Loading approved drugs dictionary from: $dict_file")
            try
                include(dict_file)
                if @isdefined(APPROVED_DRUGS_DICT)
                    return APPROVED_DRUGS_DICT
                end
            catch e
                println("Warning: Could not load $dict_file: $e")
                continue
            end
        end
    end
    
    error("No approved drugs dictionary file found. Please run approved_drugs_extractor.jl first.")
end

"""
    clean_drug_name(name::String) -> String

Clean drug name for search queries by removing special characters and formatting.
"""
function clean_drug_name(name::String)
    # For complex chemical names, be more conservative with cleaning
    # Only remove extra whitespace, don't remove parentheses as they're often part of chemical names
    cleaned = replace(name, r"\s+" => " ")
    # Trim whitespace
    return strip(cleaned)
end

"""
    extract_keywords_from_indication(indication::String) -> Vector{String}

Extract key medical terms from the indication text.
"""
function extract_keywords_from_indication(indication::String)
    # Remove common non-medical words
    stopwords = Set([
        "for", "the", "treatment", "of", "in", "and", "or", "with", "as", "to", "a", "an",
        "is", "are", "was", "were", "been", "being", "have", "has", "had", "do", "does",
        "did", "will", "would", "could", "should", "may", "might", "can", "associated"
    ])
    
    # Extract words, convert to lowercase, and filter
    words = [lowercase(word) for word in split(indication, r"[^\w-]+") if length(word) > 2]
    keywords = [word for word in words if !(word in stopwords)]
    
    # Return unique keywords, limited to most relevant ones
    return unique(keywords)[1:min(5, length(unique(keywords)))]
end

"""
    create_basic_drug_query(drug_name::String) -> String

Create a basic PubMed search query for a drug.
"""
function create_basic_drug_query(drug_name::String)
    clean_name = clean_drug_name(drug_name)
    return "\"$clean_name\"[TIAB] OR \"$clean_name\"[MeSH Terms]"
end

"""
    create_drug_indication_query(drug_name::String, indication::String) -> String

Create a PubMed search query combining drug name and indication.
"""
function create_drug_indication_query(drug_name::String, indication::String)
    clean_name = clean_drug_name(drug_name)
    keywords = extract_keywords_from_indication(indication)
    
    drug_part = "$clean_name[TIAB] OR $clean_name[MeSH Terms]"
    
    if isempty(keywords)
        return drug_part
    end
    
    # Create indication part with key terms
    indication_terms = join(["\"$keyword\"[All Fields]" for keyword in keywords[1:min(3, length(keywords))]], " OR ")
    
    return "($drug_part) AND ($indication_terms)"
end

"""
    create_clinical_trial_query(drug_name::String) -> String

Create a PubMed search query for clinical trials involving the drug.
"""
function create_clinical_trial_query(drug_name::String)
    clean_name = clean_drug_name(drug_name)
    drug_part = "$clean_name[TIAB] OR $clean_name[MeSH Terms]"
    
    return "($drug_part) AND (\"clinical trial\"[Publication Type] OR \"randomized controlled trial\"[Publication Type] OR \"clinical trials as topic\"[MeSH Terms])"
end

"""
    create_mechanism_query(drug_name::String) -> String

Create a PubMed search query for mechanism of action studies.
"""
function create_mechanism_query(drug_name::String)
    clean_name = clean_drug_name(drug_name)
    drug_part = "$clean_name[TIAB] OR $clean_name[MeSH Terms]"
    
    mechanism_terms = "\"mechanism of action\"[All Fields] OR \"mode of action\"[All Fields] OR \"pharmacology\"[MeSH Subheading] OR \"drug effects\"[MeSH Subheading]"
    
    return "($drug_part) AND ($mechanism_terms)"
end

"""
    create_safety_query(drug_name::String) -> String

Create a PubMed search query for drug safety and adverse effects.
"""
function create_safety_query(drug_name::String)
    clean_name = clean_drug_name(drug_name)
    drug_part = "$clean_name[TIAB] OR $clean_name[MeSH Terms]"
    
    safety_terms = "\"adverse effects\"[MeSH Subheading] OR \"toxicity\"[MeSH Subheading] OR \"side effects\"[All Fields] OR \"drug safety\"[All Fields]"
    
    return "($drug_part) AND ($safety_terms)"
end

"""
    encode_pubmed_url(query::String) -> String

Create a direct PubMed URL for the search query.
"""
function encode_pubmed_url(query::String)
    base_url = "https://pubmed.ncbi.nlm.nih.gov/"
    encoded_query = URIs.escapeuri(query)
    return "$base_url?term=$encoded_query"
end

"""
    generate_queries_for_drug(drug_name::String, indication::String) -> Dict

Generate basic search query for a single drug.
"""
function generate_queries_for_drug(drug_name::String, indication::String)
    basic_query = create_basic_drug_query(drug_name)
    return Dict(
        "drug_name" => drug_name,
        "indication" => indication,
        "query" => basic_query,
        "url" => encode_pubmed_url(basic_query)
    )
end

"""
    save_queries_as_text(queries_data::Vector, output_file::String)

Save search queries as a formatted text file.
"""
function save_queries_as_text(queries_data::Vector, output_file::String)
    open(output_file, "w") do file
        write(file, "PubMed Search Queries for Approved Drugs\n")
        write(file, "========================================\n")
        write(file, "Generated on: $(now())\n")
        write(file, "Total drugs: $(length(queries_data))\n\n")
        
        for (i, drug_data) in enumerate(queries_data)
            drug_name = drug_data["drug_name"]
            indication = drug_data["indication"]
            query = drug_data["query"]
            
            write(file, "Drug $i: $drug_name\n")
            write(file, "$(repeat("=", length("Drug $i: $drug_name")))\n")
            write(file, "Indication: $indication\n\n")
            
            write(file, "PubMed Query:\n")
            write(file, "   $query\n\n")
            
            write(file, "$(repeat("-", 80))\n\n")
        end
    end
    
    println("Saved formatted queries to: $output_file")
end

"""
    save_queries_as_json(queries_data::Vector, output_file::String)

Save search queries as a structured JSON file.
"""
function save_queries_as_json(queries_data::Vector, output_file::String)
    json_data = Dict(
        "metadata" => Dict(
            "generated_on" => string(now()),
            "total_drugs" => length(queries_data),
            "description" => "PubMed search queries for approved drugs",
            "query_type" => "basic"
        ),
        "drugs" => queries_data
    )
    
    open(output_file, "w") do file
        JSON.print(file, json_data, 2)
    end
    
    println("Saved JSON queries to: $output_file")
end

"""
    save_urls_as_text(queries_data::Vector, output_file::String)

Save direct PubMed URLs as a text file.
"""
function save_urls_as_text(queries_data::Vector, output_file::String)
    open(output_file, "w") do file
        write(file, "Direct PubMed URLs for Approved Drugs\n")
        write(file, "=====================================\n")
        write(file, "Generated on: $(now())\n")
        write(file, "Total drugs: $(length(queries_data))\n\n")
        write(file, "Click these URLs to go directly to PubMed searches:\n\n")
        
        for (i, drug_data) in enumerate(queries_data)
            drug_name = drug_data["drug_name"]
            url = drug_data["url"]
            
            write(file, "Drug $i: $drug_name\n")
            write(file, "$(repeat("-", length("Drug $i: $drug_name")))\n")
            
            write(file, "PubMed Search: $url\n\n")
        end
    end
    
    println("Saved PubMed URLs to: $output_file")
end

"""
    analyze_queries(queries_data::Vector)

Provide analysis of the generated queries.
"""
function analyze_queries(queries_data::Vector)
    println("\n=== Query Generation Analysis ===")
    println("Total drugs processed: $(length(queries_data))")
    println("Queries generated per drug: 1")
    println("Total queries generated: $(length(queries_data))")
    
    # Analyze indication keywords
    all_keywords = String[]
    for drug_data in queries_data
        indication = drug_data["indication"]
        keywords = extract_keywords_from_indication(indication)
        append!(all_keywords, keywords)
    end
    
    # Count keyword frequencies
    keyword_counts = Dict{String, Int}()
    for keyword in all_keywords
        keyword_counts[keyword] = get(keyword_counts, keyword, 0) + 1
    end
    
    println("\nTop indication keywords found:")
    sorted_keywords = sort(collect(keyword_counts), by=x->x[2], rev=true)
    for (i, (keyword, count)) in enumerate(sorted_keywords[1:min(10, length(sorted_keywords))])
        println("  $i. $keyword: $count occurrences")
    end
end

"""
    main()

Main function to generate PubMed search queries.
"""
function main()
    # Configuration
    output_text_file = "pubmed_queries.txt"
    output_json_file = "pubmed_queries.json"
    output_urls_file = "pubmed_urls.txt"
    
    println("PubMed Search Query Generator")
    println("============================")
    println("Output files:")
    println("  - Text: $output_text_file")
    println("  - JSON: $output_json_file")
    println("  - URLs: $output_urls_file")
    println()
    
    try
        # Load the approved drugs dictionary
        drugs_dict = load_approved_drugs_dict()
        
        if isempty(drugs_dict)
            println("No approved drugs found in dictionary!")
            return
        end
        
        println("Loaded $(length(drugs_dict)) approved drugs")
        
        # Generate queries for all drugs
        println("Generating PubMed search queries...")
        queries_data = []
        
        for (i, (drug_name, indication)) in enumerate(sort(collect(drugs_dict)))
            if i % 10 == 0 || i == length(drugs_dict)
                println("Processing drug $i of $(length(drugs_dict)): $drug_name")
            end
            
            drug_queries = generate_queries_for_drug(drug_name, indication)
            push!(queries_data, drug_queries)
        end
        
        # Save in multiple formats
        save_queries_as_text(queries_data, output_text_file)
        save_queries_as_json(queries_data, output_json_file)
        save_urls_as_text(queries_data, output_urls_file)
        
        # Provide analysis
        analyze_queries(queries_data)
        
        println("\nQuery generation completed successfully!")
        println("Generated files:")
        println("  - Formatted queries: $output_text_file")
        println("  - JSON data: $output_json_file")
        println("  - Direct URLs: $output_urls_file")
        
        # Show sample queries
        if !isempty(queries_data)
            println("\n=== Sample Query (First Drug) ===")
            sample = first(queries_data)
            println("Drug: $(sample["drug_name"])")
            println("Basic query: $(sample["query"])")
            println("URL: $(sample["url"])")
        end
        
    catch e
        println("Error during execution: $e")
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
