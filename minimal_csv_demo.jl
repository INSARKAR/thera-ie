#!/usr/bin/env julia

using CSV
using DataFrames

function create_demo_csv()
    println("📊 Creating Demo CSV with Levothyroxine Recovery Results")
    println("=" ^ 55)
    
    # Create sample result (this would come from real analysis)
    # Based on the patterns we saw in the earlier tests
    result = DataFrame(
        drug = ["Levothyroxine"],
        mesh_icd10 = [45.2],
        naive_icd10 = [0.0], 
        pubmed_icd10 = [38.7],
        mesh_chapter = [66.7],
        naive_chapter = [0.0],
        pubmed_chapter = [55.6]
    )
    
    println("CSV Format:")
    println("- Column 1: drug name")
    println("- Column 2: mesh_icd10 (MeSH ICD-10 recovery %)")
    println("- Column 3: naive_icd10 (Naive LLM ICD-10 recovery %)")
    println("- Column 4: pubmed_icd10 (PubMed LLM ICD-10 recovery %)")
    println("- Column 5: mesh_chapter (MeSH chapter recovery %)")
    println("- Column 6: naive_chapter (Naive LLM chapter recovery %)")
    println("- Column 7: pubmed_chapter (PubMed LLM chapter recovery %)")
    
    println("\n📊 Sample Results:")
    println(result)
    
    # Save to CSV
    output_file = "/oscar/home/isarkar/sarkarcode/thera/recovery_analysis_format.csv"
    CSV.write(output_file, result)
    
    println("\n💾 Saved to: $output_file")
    
    # Show CSV content
    println("\n📄 CSV File Content:")
    csv_content = read(output_file, String)
    println(csv_content)
    
    println("✅ This is the exact format for the full drug analysis!")
end

create_demo_csv()