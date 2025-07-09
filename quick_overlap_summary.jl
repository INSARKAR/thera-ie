#!/usr/bin/env julia

# Quick summary of indication overlaps

include("scripts/analysis/indication_overlap_analyzer.jl")

function quick_summary()
    drugs = get_available_drugs()
    println("=== QUICK OVERLAP SUMMARY ===")
    println("Drugs with both extractions: $(length(drugs))")
    
    if length(drugs) == 0
        println("No drugs found with both PubMed and DrugBank extractions")
        return
    end
    
    # Sample 10 drugs for quick analysis
    sample_drugs = drugs[1:min(10, length(drugs))]
    println("Analyzing sample of $(length(sample_drugs)) drugs:")
    
    total_overlap = 0
    total_pubmed = 0
    valid_drugs = 0
    
    for drug in sample_drugs
        analysis = analyze_drug_overlap(drug)
        if analysis !== nothing && analysis.pubmed_count > 0
            overlap_pct = analysis.overlap_percentage
            println("  $drug: $(analysis.overlap_count)/$(analysis.pubmed_count) PubMed indications match DrugBank ($(round(overlap_pct, digits=1))%)")
            total_overlap += analysis.overlap_count
            total_pubmed += analysis.pubmed_count
            valid_drugs += 1
        end
    end
    
    if valid_drugs > 0
        avg_overlap = (total_overlap / total_pubmed) * 100
        println("\nSample average overlap: $(round(avg_overlap, digits=1))%")
    end
end

quick_summary()