#!/usr/bin/env julia

using SQLite
using JSON3
using CSV
using DataFrames

const DB_PATH = "/oscar/data/ursa/umls/2025AA/umls_medical.db"

function get_icd10_chapter(code::String)
    chapters = Dict("A"=>"I", "B"=>"I", "C"=>"II", "D"=>"III", "E"=>"IV", "F"=>"V", "G"=>"VI", "H"=>"VII", "I"=>"IX", "J"=>"X", "K"=>"XI", "L"=>"XII", "M"=>"XIII", "N"=>"XIV", "O"=>"XV", "P"=>"XVI", "Q"=>"XVII", "R"=>"XVIII", "S"=>"XIX", "T"=>"XIX", "V"=>"XX", "W"=>"XX", "X"=>"XX", "Y"=>"XX", "Z"=>"XXI")
    return get(chapters, uppercase(string(code[1])), "Unknown")
end

function simple_icd10_lookup(term::String, db)
    codes = Set{String}()
    query = "SELECT DISTINCT m.icd10_code FROM terms t JOIN concepts c ON t.cui = c.cui JOIN icd10_mappings m ON c.cui = m.cui WHERE t.term_lower LIKE ? AND c.has_icd10 = 1 LIMIT 10"
    
    for row in SQLite.DBInterface.execute(db, query, ["%$(lowercase(term))%"])
        if !isnothing(row.icd10_code) && !isempty(row.icd10_code)
            push!(codes, row.icd10_code)
        end
    end
    return codes
end

function analyze_drug(drug_name::String, db)
    println("Analyzing $drug_name...")
    
    # Ground truth (DrugBank)
    drugbank_codes = Set{String}()
    drugbank_chapters = Set{String}()
    
    drugbank_file = "/oscar/home/isarkar/sarkarcode/thera/llama_drugbank_extracted_indications/$(drug_name)_drugbank_extracted_indications.json"
    if isfile(drugbank_file)
        data = JSON3.read(read(drugbank_file, String))
        if haskey(data, "indications")
            for indication in data.indications
                if haskey(indication, "condition")
                    # Extract key terms
                    words = split(lowercase(indication.condition), r"[^a-z]+")
                    for word in words
                        if length(word) > 4  # Focus on meaningful terms
                            codes = simple_icd10_lookup(String(word), db)
                            union!(drugbank_codes, codes)
                        end
                    end
                end
            end
        end
    end
    
    for code in drugbank_codes
        chapter = get_icd10_chapter(code)
        if chapter != "Unknown"
            push!(drugbank_chapters, chapter)
        end
    end
    
    # MeSH
    mesh_codes = Set{String}()
    mesh_chapters = Set{String}()
    
    mesh_file = "/oscar/home/isarkar/sarkarcode/thera/drug_pubmed_refs/$(drug_name).json"
    if isfile(mesh_file)
        try
            include("/oscar/home/isarkar/sarkarcode/thera/mesh_t047_headings.jl")
            data = JSON3.read(read(mesh_file, String))
            if haskey(data, "mesh_summary") && haskey(data.mesh_summary, "mesh_terms")
                for mesh_term in data.mesh_summary.mesh_terms
                    if haskey(mesh_term, "descriptor") && mesh_term.descriptor in MESH_T047_HEADINGS
                        codes = simple_icd10_lookup(mesh_term.descriptor, db)
                        union!(mesh_codes, codes)
                    end
                end
            end
        catch
        end
    end
    
    for code in mesh_codes
        chapter = get_icd10_chapter(code)
        if chapter != "Unknown"
            push!(mesh_chapters, chapter)
        end
    end
    
    # Naive LLM
    naive_codes = Set{String}()
    naive_chapters = Set{String}()
    
    naive_file = "/oscar/home/isarkar/sarkarcode/thera/llama_naive_extracted_indications/$(drug_name)_naive_extracted_indications.json"
    if isfile(naive_file)
        try
            data = JSON3.read(read(naive_file, String))
            if haskey(data, "extracted_indications")
                for indication in data.extracted_indications
                    if haskey(indication, "condition")
                        codes = simple_icd10_lookup(indication.condition, db)
                        union!(naive_codes, codes)
                    end
                end
            end
        catch
        end
    end
    
    for code in naive_codes
        chapter = get_icd10_chapter(code)
        if chapter != "Unknown"
            push!(naive_chapters, chapter)
        end
    end
    
    # PubMed LLM
    pubmed_codes = Set{String}()
    pubmed_chapters = Set{String}()
    
    pubmed_file = "/oscar/home/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/$(drug_name)_llama_extracted_indications.json"
    if isfile(pubmed_file)
        try
            data = JSON3.read(read(pubmed_file, String))
            if haskey(data, "extracted_indications")
                for indication in data.extracted_indications
                    if haskey(indication, "condition")
                        codes = simple_icd10_lookup(indication.condition, db)
                        union!(pubmed_codes, codes)
                    end
                end
            end
        catch
        end
    end
    
    for code in pubmed_codes
        chapter = get_icd10_chapter(code)
        if chapter != "Unknown"
            push!(pubmed_chapters, chapter)
        end
    end
    
    # Calculate recovery rates
    function recovery_rate(ground_truth, extracted)
        if isempty(ground_truth)
            return 0.0
        end
        return (length(intersect(ground_truth, extracted)) / length(ground_truth)) * 100.0
    end
    
    mesh_icd10_rec = recovery_rate(drugbank_codes, mesh_codes)
    naive_icd10_rec = recovery_rate(drugbank_codes, naive_codes)
    pubmed_icd10_rec = recovery_rate(drugbank_codes, pubmed_codes)
    
    mesh_chapter_rec = recovery_rate(drugbank_chapters, mesh_chapters)
    naive_chapter_rec = recovery_rate(drugbank_chapters, naive_chapters)
    pubmed_chapter_rec = recovery_rate(drugbank_chapters, pubmed_chapters)
    
    println("  DrugBank: $(length(drugbank_codes)) codes, $(length(drugbank_chapters)) chapters")
    println("  MeSH: $(round(mesh_icd10_rec, digits=1))% ICD-10, $(round(mesh_chapter_rec, digits=1))% chapter")
    println("  Naive: $(round(naive_icd10_rec, digits=1))% ICD-10, $(round(naive_chapter_rec, digits=1))% chapter")
    println("  PubMed: $(round(pubmed_icd10_rec, digits=1))% ICD-10, $(round(pubmed_chapter_rec, digits=1))% chapter")
    
    return (
        drug = drug_name,
        mesh_icd10 = round(mesh_icd10_rec, digits=1),
        naive_icd10 = round(naive_icd10_rec, digits=1),
        pubmed_icd10 = round(pubmed_icd10_rec, digits=1),
        mesh_chapter = round(mesh_chapter_rec, digits=1),
        naive_chapter = round(naive_chapter_rec, digits=1),
        pubmed_chapter = round(pubmed_chapter_rec, digits=1)
    )
end

function main()
    println("🎯 Quick Recovery Analysis for Levothyroxine")
    println("=" ^ 50)
    
    db = SQLite.DB(DB_PATH)
    
    result = analyze_drug("Levothyroxine", db)
    
    df = DataFrame([result])
    
    println("\n📊 CSV Output:")
    println(df)
    
    # Save to CSV
    output_file = "/oscar/home/isarkar/sarkarcode/thera/levothyroxine_recovery_result.csv"
    CSV.write(output_file, df)
    
    println("\n💾 Saved to: $output_file")
    
    SQLite.close(db)
    
    println("\n✅ Complete!")
end

main()