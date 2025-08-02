#!/usr/bin/env julia

"""
THERA-IE Phase 3: Simple String-Based Cross-Method Evaluation

Fast and reliable evaluation using direct SNOMED term string matching:
- Exact string matches
- Normalized string matches (lowercase, trimmed)
- Partial word overlap matching
- Comprehensive unique indications analysis
- Recovery rate calculations
- Detailed reporting with match evidence

This approach is much faster than QuickUMLS and provides reliable results
for comparing the three extraction methods.
"""

using JSON3, Dates, Statistics

function normalize_term(term::String)
    """Normalize SNOMED term for comparison"""
    return lowercase(strip(term))
end

function calculate_word_overlap(term1::String, term2::String)
    """Calculate word overlap ratio between two terms"""
    words1 = Set(split(normalize_term(term1)))
    words2 = Set(split(normalize_term(term2)))
    
    intersection_size = length(intersect(words1, words2))
    union_size = length(union(words1, words2))
    
    return union_size > 0 ? intersection_size / union_size : 0.0
end

function find_best_string_match(target_term::String, candidate_terms::Vector{String})
    """Find best string match for target term among candidates"""
    
    target_norm = normalize_term(target_term)
    best_match = ""
    best_score = 0.0
    match_type = "none"
    
    for candidate in candidate_terms
        candidate_norm = normalize_term(candidate)
        
        # Exact match (highest priority)
        if target_norm == candidate_norm
            return candidate, 1.0, "exact"
        end
        
        # Contains match
        if contains(target_norm, candidate_norm) || contains(candidate_norm, target_norm)
            contains_score = 0.8
            if contains_score > best_score
                best_match = candidate
                best_score = contains_score
                match_type = "contains"
            end
        end
        
        # Word overlap match
        overlap_score = calculate_word_overlap(target_term, candidate)
        if overlap_score >= 0.6 && overlap_score > best_score
            best_match = candidate
            best_score = overlap_score
            match_type = "word_overlap"
        end
    end
    
    return best_match, best_score, match_type
end

function load_method_data(drug_name::String)
    """Load SNOMED indications from all three methods"""
    
    methods = Dict()
    
    # DrugBank (ground truth)
    drugbank_file = "phase2_step1_drugbank_snomed/$(drug_name)_drugbank_snomed.json"
    if isfile(drugbank_file)
        data = JSON3.read(read(drugbank_file, String))
        # Only use confirmed DrugBank indications
        drugbank_terms = [string(ind.snomed_term) for ind in data.snomed_indications if get(ind, "confirmed", false)]
        methods["drugbank"] = unique(drugbank_terms)
    else
        methods["drugbank"] = String[]
    end
    
    # Knowledge method
    knowledge_file = "phase2_step2_naive_snomed/$(drug_name)_naive_snomed.json"
    if isfile(knowledge_file)
        data = JSON3.read(read(knowledge_file, String))
        knowledge_terms = [string(ind.snomed_term) for ind in data.snomed_indications]
        methods["knowledge"] = unique(knowledge_terms)
    else
        methods["knowledge"] = String[]
    end
    
    # Literature method
    literature_file = "phase2_step3_pubmed_snomed/$(drug_name)_pubmed_snomed.json"
    if isfile(literature_file)
        data = JSON3.read(read(literature_file, String))
        literature_terms = [string(ind.snomed_term) for ind in data.snomed_indications]
        methods["literature"] = unique(literature_terms)
    else
        methods["literature"] = String[]
    end
    
    return methods
end

function analyze_unique_indications(methods::Dict)
    """Analyze unique and overlapping indications across methods using string matching"""
    
    drugbank_set = Set(methods["drugbank"])
    knowledge_set = Set(methods["knowledge"])
    literature_set = Set(methods["literature"])
    
    # Direct string-based analysis
    unique_drugbank = setdiff(drugbank_set, union(knowledge_set, literature_set))
    unique_knowledge = setdiff(knowledge_set, union(drugbank_set, literature_set))
    unique_literature = setdiff(literature_set, union(drugbank_set, knowledge_set))
    
    # Exact overlaps
    drugbank_knowledge = intersect(drugbank_set, knowledge_set)
    drugbank_literature = intersect(drugbank_set, literature_set)
    knowledge_literature = intersect(knowledge_set, literature_set)
    all_three = intersect(drugbank_set, knowledge_set, literature_set)
    
    return Dict(
        "unique_drugbank" => collect(unique_drugbank),
        "unique_knowledge" => collect(unique_knowledge),
        "unique_literature" => collect(unique_literature),
        "drugbank_knowledge_overlap" => collect(drugbank_knowledge),
        "drugbank_literature_overlap" => collect(drugbank_literature),
        "knowledge_literature_overlap" => collect(knowledge_literature),
        "all_three_overlap" => collect(all_three),
        "total_unique_indications" => length(union(drugbank_set, knowledge_set, literature_set))
    )
end

function evaluate_method_against_drugbank(method_terms::Vector{String}, drugbank_terms::Vector{String}, method_name::String)
    """Evaluate a method against DrugBank ground truth using string matching"""
    
    matched_count = 0
    matches = []
    unmatched = []
    
    println("    🔍 Evaluating $(length(method_terms)) $method_name terms against $(length(drugbank_terms)) DrugBank terms")
    
    for method_term in method_terms
        best_match, score, match_type = find_best_string_match(method_term, drugbank_terms)
        
        if score >= 0.6  # Threshold for considering a match
            matched_count += 1
            push!(matches, Dict(
                "method_term" => method_term,
                "drugbank_term" => best_match,
                "confidence" => score,
                "match_type" => match_type
            ))
            println("      ✅ $method_term → $best_match ($match_type, $(round(score, digits=2)))")
        else
            push!(unmatched, method_term)
            println("      ❌ $method_term (no match)")
        end
    end
    
    recovery_rate = length(method_terms) > 0 ? matched_count / length(method_terms) : 0.0
    
    return Dict(
        "total_indications" => length(method_terms),
        "matched_indications" => matched_count,
        "unmatched_indications" => length(unmatched),
        "recovery_rate" => recovery_rate,
        "matches" => matches,
        "unmatched_terms" => unmatched
    )
end

function evaluate_drug_simple(drug_name::String)
    """Simple string-based evaluation of a single drug"""
    
    println("🔍 Simple string evaluation: $drug_name")
    
    # Load method data
    methods = load_method_data(drug_name)
    
    println("  📊 DrugBank (ground truth): $(length(methods["drugbank"])) terms")
    println("  📊 Knowledge method: $(length(methods["knowledge"])) terms")
    println("  📊 Literature method: $(length(methods["literature"])) terms")
    
    if isempty(methods["drugbank"])
        println("  ⚠️ No DrugBank ground truth terms found, skipping evaluation")
        return nothing
    end
    
    # Evaluate each method against DrugBank
    println("\n  🎯 KNOWLEDGE METHOD EVALUATION:")
    knowledge_results = evaluate_method_against_drugbank(
        methods["knowledge"], methods["drugbank"], "knowledge"
    )
    
    println("\n  🎯 LITERATURE METHOD EVALUATION:")
    literature_results = evaluate_method_against_drugbank(
        methods["literature"], methods["drugbank"], "literature"
    )
    
    # Analyze unique indications
    unique_analysis = analyze_unique_indications(methods)
    
    # Compile final results
    final_result = Dict(
        "drug_name" => drug_name,
        "evaluation_date" => string(now()),
        "evaluation_method" => "simple_string_matching",
        "drugbank_ground_truth" => Dict(
            "terms" => methods["drugbank"],
            "count" => length(methods["drugbank"])
        ),
        "method_evaluation" => Dict(
            "knowledge" => knowledge_results,
            "literature" => literature_results
        ),
        "unique_indications_analysis" => unique_analysis,
        "summary" => Dict(
            "knowledge_recovery_rate" => knowledge_results["recovery_rate"],
            "literature_recovery_rate" => literature_results["recovery_rate"],
            "unique_to_knowledge" => length(unique_analysis["unique_knowledge"]),
            "unique_to_literature" => length(unique_analysis["unique_literature"]),
            "all_methods_overlap" => length(unique_analysis["all_three_overlap"]),
            "total_unique_across_all_methods" => unique_analysis["total_unique_indications"]
        )
    )
    
    # Save results
    mkpath("phase3_simple_results")
    output_file = "phase3_simple_results/$(drug_name)_simple_evaluation.json"
    
    open(output_file, "w") do f
        JSON3.pretty(f, final_result)
    end
    
    println("\n  ✅ Results saved: $output_file")
    println("  📈 Knowledge recovery: $(round(knowledge_results["recovery_rate"]*100, digits=1))%")
    println("  📈 Literature recovery: $(round(literature_results["recovery_rate"]*100, digits=1))%")
    
    return final_result
end

function generate_summary_report(all_results::Vector)
    """Generate comprehensive summary report"""
    
    if isempty(all_results)
        return
    end
    
    # Calculate overall statistics
    knowledge_rates = [r["summary"]["knowledge_recovery_rate"] for r in all_results]
    literature_rates = [r["summary"]["literature_recovery_rate"] for r in all_results]
    
    overall_stats = Dict(
        "total_drugs_evaluated" => length(all_results),
        "avg_knowledge_recovery" => mean(knowledge_rates),
        "avg_literature_recovery" => mean(literature_rates),
        "best_knowledge_drug" => all_results[argmax(knowledge_rates)]["drug_name"],
        "best_literature_drug" => all_results[argmax(literature_rates)]["drug_name"],
        "total_unique_knowledge" => sum([r["summary"]["unique_to_knowledge"] for r in all_results]),
        "total_unique_literature" => sum([r["summary"]["unique_to_literature"] for r in all_results]),
        "total_overlapping_all_methods" => sum([r["summary"]["all_methods_overlap"] for r in all_results])
    )
    
    # Create summary report
    summary_report = Dict(
        "evaluation_date" => string(now()),
        "evaluation_method" => "simple_string_matching",
        "overall_statistics" => overall_stats,
        "per_drug_summary" => [
            Dict(
                "drug" => r["drug_name"],
                "knowledge_recovery" => r["summary"]["knowledge_recovery_rate"],
                "literature_recovery" => r["summary"]["literature_recovery_rate"],
                "unique_knowledge" => r["summary"]["unique_to_knowledge"],
                "unique_literature" => r["summary"]["unique_to_literature"],
                "overlap_all_methods" => r["summary"]["all_methods_overlap"]
            ) for r in all_results
        ],
        "detailed_results" => all_results
    )
    
    # Save JSON summary
    open("phase3_simple_results/summary_simple_evaluation.json", "w") do f
        JSON3.pretty(f, summary_report)
    end
    
    # Create text report
    open("phase3_simple_results/summary_simple_evaluation.txt", "w") do f
        println(f, "THERA-IE Phase 3: Simple String-Based Evaluation Summary")
        println(f, "="^60)
        println(f, "Generated: $(now())")
        println(f, "")
        
        println(f, "OVERALL STATISTICS:")
        println(f, "- Total drugs evaluated: $(overall_stats["total_drugs_evaluated"])")
        println(f, "- Average knowledge recovery rate: $(round(overall_stats["avg_knowledge_recovery"]*100, digits=1))%")
        println(f, "- Average literature recovery rate: $(round(overall_stats["avg_literature_recovery"]*100, digits=1))%")
        println(f, "- Best knowledge method drug: $(overall_stats["best_knowledge_drug"])")
        println(f, "- Best literature method drug: $(overall_stats["best_literature_drug"])")
        println(f, "- Total unique knowledge indications: $(overall_stats["total_unique_knowledge"])")
        println(f, "- Total unique literature indications: $(overall_stats["total_unique_literature"])")
        println(f, "- Total overlapping (all methods): $(overall_stats["total_overlapping_all_methods"])")
        println(f, "")
        
        println(f, "PER-DRUG RESULTS:")
        for drug_summary in summary_report["per_drug_summary"]
            println(f, "$(drug_summary["drug"]):")
            println(f, "  Knowledge: $(round(drug_summary["knowledge_recovery"]*100, digits=1))% recovery, $(drug_summary["unique_knowledge"]) unique")
            println(f, "  Literature: $(round(drug_summary["literature_recovery"]*100, digits=1))% recovery, $(drug_summary["unique_literature"]) unique")
            println(f, "  All methods overlap: $(drug_summary["overlap_all_methods"])")
            println(f, "")
        end
    end
    
    println("📊 Summary reports saved:")
    println("  📄 phase3_simple_results/summary_simple_evaluation.txt")
    println("  📋 phase3_simple_results/summary_simple_evaluation.json")
end

function main()
    println("🚀 THERA-IE Phase 3: Simple String-Based Evaluation")
    println("📅 Started: $(now())")
    
    top10_drugs = [
        "Atorvastatin", "Levothyroxine", "Lisinopril", "Metformin", 
        "Amlodipine", "Albuterol", "Omeprazole", "Losartan", 
        "Gabapentin", "Sertraline"
    ]
    
    println("📊 Evaluating $(length(top10_drugs)) drugs using simple string matching")
    
    all_results = []
    success_count = 0
    
    for (i, drug) in enumerate(top10_drugs)
        println("\n" * "="^60)
        println("Drug $i/$(length(top10_drugs)): $drug")
        println("="^60)
        
        try
            result = evaluate_drug_simple(drug)
            if result !== nothing
                push!(all_results, result)
                success_count += 1
            end
        catch e
            println("❌ Error evaluating $drug: $e")
        end
    end
    
    # Generate summary report
    if success_count > 0
        println("\n📊 Generating summary report...")
        generate_summary_report(all_results)
    end
    
    println("\n" * "="^60)
    println("✅ Simple string-based evaluation complete!")
    println("📊 Successfully evaluated: $success_count/$(length(top10_drugs)) drugs")
    println("📁 Results saved in: phase3_simple_results/")
    println("📅 Completed: $(now())")
    
    if success_count > 0
        # Quick stats
        knowledge_rates = [r["summary"]["knowledge_recovery_rate"] for r in all_results]
        literature_rates = [r["summary"]["literature_recovery_rate"] for r in all_results]
        
        println("\n🎯 KEY FINDINGS:")
        println("📈 Knowledge method average recovery: $(round(mean(knowledge_rates)*100, digits=1))%")
        println("📈 Literature method average recovery: $(round(mean(literature_rates)*100, digits=1))%")
        println("🥇 Best knowledge drug: $(all_results[argmax(knowledge_rates)]["drug_name"]) ($(round(maximum(knowledge_rates)*100, digits=1))%)")
        println("🥇 Best literature drug: $(all_results[argmax(literature_rates)]["drug_name"]) ($(round(maximum(literature_rates)*100, digits=1))%)")
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main()
end