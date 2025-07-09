#!/usr/bin/env julia

"""
Levothyroxine UMLS Hierarchical Analysis

Implements proper UMLS-based ICD-10 mapping with hierarchical traversal:
1. Map indication text to UMLS CUI
2. Check if CUI has ICD-10 code
3. If not, traverse up hierarchy until ICD-10 code found
4. Match based on ICD-10 chapter codes
"""

using JSON3
using HTTP
using Dates

# Configuration
const UMLS_META_DIR = "/oscar/data/ursa/umls/2025AA/META"
const MRCONSO_FILE = joinpath(UMLS_META_DIR, "MRCONSO.RRF")
const MRHIER_FILE = joinpath(UMLS_META_DIR, "MRHIER.RRF")
const MRREL_FILE = joinpath(UMLS_META_DIR, "MRREL.RRF")
const MRSTY_FILE = joinpath(UMLS_META_DIR, "MRSTY.RRF")

# ICD-10 vocabularies
const ICD10_SOURCES = ["ICD10", "ICD10CM", "ICD10AM", "ICD10AMAE"]

# Medical condition semantic types
const MEDICAL_SEMANTIC_TYPES = Set([
    "T047",  # Disease or Syndrome
    "T048",  # Mental or Behavioral Dysfunction
    "T049",  # Cell or Molecular Dysfunction
    "T050",  # Experimental Model of Disease
    "T033",  # Finding
    "T046",  # Pathologic Function
    "T184",  # Sign or Symptom
    "T191",  # Neoplastic Process
    "T037",  # Injury or Poisoning
    "T190",  # Anatomical Abnormality
    "T019",  # Congenital Abnormality
])

struct UMLSMapping
    original_text::String
    cui::String
    preferred_name::String
    semantic_types::Set{String}
    icd10_code::String
    icd10_chapter::String
    icd10_source::String
    hierarchy_level::Int  # 0 = direct, 1+ = levels up hierarchy
    confidence::Float64
end

function load_umls_concepts()
    """Load UMLS concepts from MRCONSO file"""
    println("📚 Loading UMLS concepts...")
    
    concepts = Dict{String, Dict{String, Any}}()
    
    if !isfile(MRCONSO_FILE)
        println("❌ MRCONSO file not found: $MRCONSO_FILE")
        return concepts
    end
    
    line_count = 0
    for line in eachline(MRCONSO_FILE)
        line_count += 1
        if line_count % 1000000 == 0
            println("  Processed $line_count lines...")
        end
        
        fields = split(line, "|")
        if length(fields) >= 15
            cui = fields[1]
            source = fields[12]
            term = fields[15]
            
            if !haskey(concepts, cui)
                concepts[cui] = Dict(
                    "preferred_name" => "",
                    "synonyms" => Set{String}(),
                    "icd10_codes" => Dict{String, String}(),
                    "semantic_types" => Set{String}()
                )
            end
            
            # Add synonym
            push!(concepts[cui]["synonyms"], lowercase(term))
            
            # Check if this is preferred name (usually first occurrence)
            if concepts[cui]["preferred_name"] == ""
                concepts[cui]["preferred_name"] = term
            end
            
            # Add ICD-10 codes
            if source in ICD10_SOURCES
                concepts[cui]["icd10_codes"][source] = term
            end
        end
    end
    
    println("✅ Loaded $(length(concepts)) UMLS concepts")
    return concepts
end

function load_umls_semantic_types()
    """Load semantic types from MRSTY file"""
    println("🏷️  Loading semantic types...")
    
    semantic_types = Dict{String, Set{String}}()
    
    if !isfile(MRSTY_FILE)
        println("❌ MRSTY file not found: $MRSTY_FILE")
        return semantic_types
    end
    
    for line in eachline(MRSTY_FILE)
        fields = split(line, "|")
        if length(fields) >= 2
            cui = fields[1]
            sty = fields[2]
            
            if !haskey(semantic_types, cui)
                semantic_types[cui] = Set{String}()
            end
            push!(semantic_types[cui], sty)
        end
    end
    
    println("✅ Loaded semantic types for $(length(semantic_types)) concepts")
    return semantic_types
end

function load_umls_hierarchy()
    """Load UMLS hierarchy from MRREL file"""
    println("🌳 Loading UMLS hierarchy...")
    
    hierarchy = Dict{String, Set{String}}()  # child -> parents
    
    if !isfile(MRREL_FILE)
        println("❌ MRREL file not found: $MRREL_FILE")
        return hierarchy
    end
    
    line_count = 0
    for line in eachline(MRREL_FILE)
        line_count += 1
        if line_count % 1000000 == 0
            println("  Processed hierarchy $line_count lines...")
        end
        
        fields = split(line, "|")
        if length(fields) >= 8
            cui1 = fields[1]  # subject
            rel = fields[4]   # relation
            cui2 = fields[5]  # object
            
            # Look for hierarchical relationships
            if rel in ["CHD", "PAR", "RB", "RN"]  # Child, Parent, Broader, Narrower
                if rel in ["CHD", "RN"]  # cui1 is child of cui2
                    if !haskey(hierarchy, cui1)
                        hierarchy[cui1] = Set{String}()
                    end
                    push!(hierarchy[cui1], cui2)
                elseif rel in ["PAR", "RB"]  # cui1 is parent of cui2
                    if !haskey(hierarchy, cui2)
                        hierarchy[cui2] = Set{String}()
                    end
                    push!(hierarchy[cui2], cui1)
                end
            end
        end
    end
    
    println("✅ Loaded hierarchy for $(length(hierarchy)) concepts")
    return hierarchy
end

function map_text_to_cui(text::String, concepts::Dict, semantic_types::Dict)
    """Map text to UMLS CUI using fuzzy matching"""
    text_lower = lowercase(strip(text))
    
    # Direct exact match
    for (cui, concept) in concepts
        if text_lower in concept["synonyms"]
            # Check if medical condition
            if haskey(semantic_types, cui)
                cui_semantic_types = semantic_types[cui]
                if !isempty(intersect(cui_semantic_types, MEDICAL_SEMANTIC_TYPES))
                    return cui, concept["preferred_name"], cui_semantic_types, 1.0
                end
            end
        end
    end
    
    # Partial match
    for (cui, concept) in concepts
        for synonym in concept["synonyms"]
            if occursin(text_lower, synonym) || occursin(synonym, text_lower)
                # Check if medical condition
                if haskey(semantic_types, cui)
                    cui_semantic_types = semantic_types[cui]
                    if !isempty(intersect(cui_semantic_types, MEDICAL_SEMANTIC_TYPES))
                        return cui, concept["preferred_name"], cui_semantic_types, 0.8
                    end
                end
            end
        end
    end
    
    return "", "", Set{String}(), 0.0
end

function find_icd10_in_hierarchy(cui::String, concepts::Dict, hierarchy::Dict, max_levels::Int = 5)
    """Find ICD-10 code by traversing up UMLS hierarchy"""
    
    # Check direct mapping
    if haskey(concepts, cui) && !isempty(concepts[cui]["icd10_codes"])
        for (source, code) in concepts[cui]["icd10_codes"]
            if source in ICD10_SOURCES
                chapter = extract_icd10_chapter(code)
                return code, chapter, source, 0
            end
        end
    end
    
    # Traverse up hierarchy
    visited = Set{String}()
    current_level = Set([cui])
    
    for level in 1:max_levels
        next_level = Set{String}()
        
        for current_cui in current_level
            if current_cui in visited
                continue
            end
            push!(visited, current_cui)
            
            # Check parents
            if haskey(hierarchy, current_cui)
                for parent_cui in hierarchy[current_cui]
                    if haskey(concepts, parent_cui) && !isempty(concepts[parent_cui]["icd10_codes"])
                        for (source, code) in concepts[parent_cui]["icd10_codes"]
                            if source in ICD10_SOURCES
                                chapter = extract_icd10_chapter(code)
                                return code, chapter, source, level
                            end
                        end
                    end
                    push!(next_level, parent_cui)
                end
            end
        end
        
        current_level = next_level
        if isempty(current_level)
            break
        end
    end
    
    return "", "", "", -1
end

function extract_icd10_chapter(code::String)
    """Extract ICD-10 chapter from code"""
    if isempty(code)
        return ""
    end
    
    # ICD-10 chapter is typically the first character(s)
    if length(code) >= 3
        return code[1:3]
    elseif length(code) >= 2
        return code[1:2]
    else
        return code
    end
end

function analyze_levothyroxine_umls_hierarchical()
    """Analyze Levothyroxine using UMLS hierarchical mapping"""
    
    println("🔬 Starting Levothyroxine UMLS Hierarchical Analysis")
    println("=" ^ 60)
    
    # Load UMLS data
    concepts = load_umls_concepts()
    semantic_types = load_umls_semantic_types()
    hierarchy = load_umls_hierarchy()
    
    if isempty(concepts)
        println("❌ Failed to load UMLS concepts")
        return
    end
    
    # Load extraction data
    println("\\n📁 Loading extraction data...")
    
    # DrugBank indication
    include("/oscar/home/isarkar/sarkarcode/thera/approved_drugs_dict.jl")
    drugbank_indication = APPROVED_DRUGS_DICT["Levothyroxine"]
    
    # Parse DrugBank indication into components
    drugbank_conditions = [
        "Hypothyroidism (primary, secondary, tertiary congenital or acquired)",
        "Thyrotropin-dependent well-differentiated thyroid cancer",
        "Thyroidal cancer (adjunctive therapy)",
        "Well-differentiated thyroid cancer (management)"
    ]
    
    # Naive LLM results
    naive_file = "llama_naive_extracted_indications/Levothyroxine_naive_extracted_indications.json"
    naive_conditions = String[]
    if isfile(naive_file)
        naive_data = JSON3.read(read(naive_file, String))
        for indication in naive_data["indications"]
            if get(indication, "confirmed", false)
                push!(naive_conditions, indication["condition"])
            end
        end
    end
    
    # PubMed LLM results
    pubmed_file = "llama_pubmed_extracted_indications/Levothyroxine_llama_extracted_indications.json"
    pubmed_conditions = String[]
    if isfile(pubmed_file)
        pubmed_data = JSON3.read(read(pubmed_file, String))
        for pair in pubmed_data["disease_pairs"]
            if get(pair, "confirmed", false)
                push!(pubmed_conditions, pair["disease"])
            end
        end
    end
    
    println("  DrugBank: $(length(drugbank_conditions)) conditions")
    println("  Naive: $(length(naive_conditions)) conditions")
    println("  PubMed: $(length(pubmed_conditions)) conditions")
    
    # Map each method to UMLS and ICD-10
    println("\\n🏥 Mapping to UMLS CUIs and ICD-10 codes...")
    
    drugbank_mappings = map_conditions_to_icd10(drugbank_conditions, concepts, semantic_types, hierarchy, "DrugBank")
    naive_mappings = map_conditions_to_icd10(naive_conditions, concepts, semantic_types, hierarchy, "Naive")
    pubmed_mappings = map_conditions_to_icd10(pubmed_conditions, concepts, semantic_types, hierarchy, "PubMed")
    
    # Calculate overlaps based on ICD-10 chapters
    println("\\n📊 Calculating ICD-10 chapter overlaps...")
    
    drugbank_chapters = Set([m.icd10_chapter for m in drugbank_mappings if !isempty(m.icd10_chapter)])
    naive_chapters = Set([m.icd10_chapter for m in naive_mappings if !isempty(m.icd10_chapter)])
    pubmed_chapters = Set([m.icd10_chapter for m in pubmed_mappings if !isempty(m.icd10_chapter)])
    
    naive_overlap = intersect(naive_chapters, drugbank_chapters)
    pubmed_overlap = intersect(pubmed_chapters, drugbank_chapters)
    
    naive_recovery_rate = length(naive_overlap) / length(drugbank_chapters) * 100
    pubmed_recovery_rate = length(pubmed_overlap) / length(drugbank_chapters) * 100
    
    println("\\n🎯 RESULTS:")
    println("  DrugBank ICD-10 chapters: $(collect(drugbank_chapters))")
    println("  Naive ICD-10 chapters: $(collect(naive_chapters))")
    println("  PubMed ICD-10 chapters: $(collect(pubmed_chapters))")
    println()
    println("  Naive overlap: $(collect(naive_overlap))")
    println("  PubMed overlap: $(collect(pubmed_overlap))")
    println()
    println("  Naive recovery rate: $(round(naive_recovery_rate, digits=1))%")
    println("  PubMed recovery rate: $(round(pubmed_recovery_rate, digits=1))%")
    
    # Detailed mapping results
    println("\\n📋 Detailed Mappings:")
    print_mappings("DrugBank", drugbank_mappings)
    print_mappings("Naive", naive_mappings)
    print_mappings("PubMed", pubmed_mappings[1:min(10, length(pubmed_mappings))])  # Show first 10
    
    # Save results
    results = Dict(
        "analysis_timestamp" => string(now()),
        "drugbank_mappings" => [mapping_to_dict(m) for m in drugbank_mappings],
        "naive_mappings" => [mapping_to_dict(m) for m in naive_mappings],
        "pubmed_mappings" => [mapping_to_dict(m) for m in pubmed_mappings],
        "recovery_rates" => Dict(
            "naive" => naive_recovery_rate,
            "pubmed" => pubmed_recovery_rate
        ),
        "chapter_overlaps" => Dict(
            "drugbank" => collect(drugbank_chapters),
            "naive" => collect(naive_chapters),
            "pubmed" => collect(pubmed_chapters),
            "naive_overlap" => collect(naive_overlap),
            "pubmed_overlap" => collect(pubmed_overlap)
        )
    )
    
    output_file = "levothyroxine_umls_hierarchical_analysis.json"
    open(output_file, "w") do f
        JSON3.pretty(f, results)
    end
    
    println("\\n✅ Analysis saved to: $output_file")
end

function map_conditions_to_icd10(conditions::Vector{String}, concepts::Dict, semantic_types::Dict, hierarchy::Dict, method_name::String)
    """Map conditions to ICD-10 using UMLS hierarchy"""
    mappings = UMLSMapping[]
    
    for condition in conditions
        cui, preferred_name, semantic_types_set, confidence = map_text_to_cui(condition, concepts, semantic_types)
        
        if !isempty(cui)
            icd10_code, chapter, source, hierarchy_level = find_icd10_in_hierarchy(cui, concepts, hierarchy)
            
            if !isempty(icd10_code)
                mapping = UMLSMapping(
                    condition,
                    cui,
                    preferred_name,
                    semantic_types_set,
                    icd10_code,
                    chapter,
                    source,
                    hierarchy_level,
                    confidence
                )
                push!(mappings, mapping)
                
                println("  ✅ $method_name: \"$condition\" → $chapter ($icd10_code) [level $hierarchy_level]")
            else
                println("  ❌ $method_name: \"$condition\" → No ICD-10 code found")
            end
        else
            println("  ❌ $method_name: \"$condition\" → No UMLS CUI found")
        end
    end
    
    return mappings
end

function print_mappings(method_name::String, mappings::Vector{UMLSMapping})
    """Print mapping details"""
    println("\\n$method_name mappings:")
    for mapping in mappings
        println("  • \"$(mapping.original_text)\"")
        println("    → CUI: $(mapping.cui) ($(mapping.preferred_name))")
        println("    → ICD-10: $(mapping.icd10_code) (Chapter: $(mapping.icd10_chapter))")
        println("    → Hierarchy level: $(mapping.hierarchy_level), Confidence: $(mapping.confidence)")
    end
end

function mapping_to_dict(mapping::UMLSMapping)
    """Convert UMLSMapping to dictionary for JSON serialization"""
    return Dict(
        "original_text" => mapping.original_text,
        "cui" => mapping.cui,
        "preferred_name" => mapping.preferred_name,
        "semantic_types" => collect(mapping.semantic_types),
        "icd10_code" => mapping.icd10_code,
        "icd10_chapter" => mapping.icd10_chapter,
        "icd10_source" => mapping.icd10_source,
        "hierarchy_level" => mapping.hierarchy_level,
        "confidence" => mapping.confidence
    )
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    analyze_levothyroxine_umls_hierarchical()
end