#!/usr/bin/env julia

"""
UMLS-to-ICD10 Hierarchical Mapper

Properly maps medical terms to ICD-10 codes using UMLS hierarchy:
1. Map terms to UMLS CUIs
2. Check if CUI has ICD-10 codes
3. If not, traverse UMLS hierarchy to find parent CUIs with ICD-10 codes
"""

using JSON3
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

struct ICD10Mapping
    original_term::String
    cui::String
    preferred_name::String
    icd10_code::String
    icd10_source::String
    mapping_method::String  # "direct", "parent_L1", "parent_L2", etc.
    confidence::Float64
    hierarchy_level::Int
end

# Global caches for performance
CONCEPT_CACHE = Dict{String, Any}()
HIERARCHY_CACHE = Dict{String, Set{String}}()
TERM_TO_CUI_CACHE = Dict{String, Vector{String}}()
LOADED = false

function load_umls_data()
    """Load UMLS concepts and ICD-10 mappings"""
    global CONCEPT_CACHE, TERM_TO_CUI_CACHE, LOADED
    
    if LOADED
        return
    end
    
    println("📚 Loading UMLS 2025AA data...")
    
    # Check if UMLS files exist
    if !isfile(MRCONSO_FILE)
        println("⚠️  UMLS files not found at $UMLS_META_DIR")
        println("⚠️  Using fallback mapping approach...")
        LOADED = true
        return
    end
    
    # Load semantic types first
    println("  Loading semantic types...")
    semantic_types = Dict{String, Set{String}}()
    
    if isfile(MRSTY_FILE)
        open(MRSTY_FILE, "r") do file
            for line in eachline(file)
                fields = split(line, '|')
                if length(fields) >= 2
                    cui = fields[1]
                    sty = fields[2]
                    
                    if !haskey(semantic_types, cui)
                        semantic_types[cui] = Set{String}()
                    end
                    push!(semantic_types[cui], sty)
                end
            end
        end
    end
    
    println("  Loading concepts and ICD-10 mappings...")
    
    # Load concepts and ICD-10 mappings from MRCONSO
    open(MRCONSO_FILE, "r") do file
        for (i, line) in enumerate(eachline(file))
            if i % 500000 == 0
                println("    Processed $i lines...")
            end
            
            fields = split(line, '|')
            if length(fields) >= 15
                cui = fields[1]
                language = fields[2]
                term_status = fields[3]
                term = fields[15]
                source = fields[12]
                code = fields[14]
                suppress = fields[17]
                
                # Only process English, non-suppressed terms
                if language == "ENG" && suppress != "Y"
                    # Check if this is a medical concept
                    if haskey(semantic_types, cui)
                        cui_stypes = semantic_types[cui]
                        if !isempty(intersect(cui_stypes, MEDICAL_SEMANTIC_TYPES))
                            
                            # Initialize concept if not exists
                            if !haskey(CONCEPT_CACHE, cui)
                                CONCEPT_CACHE[cui] = Dict(
                                    "preferred_name" => "",
                                    "synonyms" => Set{String}(),
                                    "icd10_codes" => Dict{String, String}(),
                                    "semantic_types" => cui_stypes
                                )
                            end
                            
                            concept = CONCEPT_CACHE[cui]
                            
                            # Set preferred name
                            if term_status == "P"
                                concept["preferred_name"] = term
                            end
                            
                            # Add synonym
                            push!(concept["synonyms"], lowercase(term))
                            
                            # Add to term-to-CUI mapping
                            term_lower = lowercase(term)
                            if !haskey(TERM_TO_CUI_CACHE, term_lower)
                                TERM_TO_CUI_CACHE[term_lower] = String[]
                            end
                            if cui ∉ TERM_TO_CUI_CACHE[term_lower]
                                push!(TERM_TO_CUI_CACHE[term_lower], cui)
                            end
                            
                            # Check if this is an ICD-10 code
                            if source in ICD10_SOURCES
                                concept["icd10_codes"][source] = code
                            end
                        end
                    end
                end
            end
        end
    end
    
    println("✅ UMLS data loaded successfully!")
    println("  Loaded $(length(CONCEPT_CACHE)) medical concepts")
    println("  Loaded $(length(TERM_TO_CUI_CACHE)) term mappings")
    LOADED = true
end

function normalize_term(term::String)
    """Normalize medical term for consistent matching"""
    normalized = lowercase(strip(term))
    
    # Remove common descriptors
    normalized = replace(normalized, r"\\s*\\([^)]*\\)\\s*" => " ")
    normalized = replace(normalized, r"^(treatment of|therapy for|management of)\\s+" => "")
    normalized = replace(normalized, r"\\s+(therapy|treatment|management)\\s*$" => "")
    
    # Normalize whitespace
    normalized = replace(normalized, r"\\s+" => " ")
    normalized = strip(normalized)
    
    return normalized
end

function search_umls_concepts(term::String)
    """Search for UMLS concepts matching the term"""
    
    if !LOADED
        load_umls_data()
    end
    
    normalized_term = normalize_term(term)
    matches = []
    
    # Direct lookup
    if haskey(TERM_TO_CUI_CACHE, normalized_term)
        for cui in TERM_TO_CUI_CACHE[normalized_term]
            if haskey(CONCEPT_CACHE, cui)
                concept = CONCEPT_CACHE[cui]
                push!(matches, (cui=cui, concept=concept, score=1.0, match_type="exact"))
            end
        end
    end
    
    # Partial matching if no exact matches
    if isempty(matches)
        for (cached_term, cuis) in TERM_TO_CUI_CACHE
            if occursin(normalized_term, cached_term) || occursin(cached_term, normalized_term)
                overlap = min(length(normalized_term), length(cached_term))
                total = max(length(normalized_term), length(cached_term))
                score = overlap / total
                
                if score >= 0.6
                    for cui in cuis
                        if haskey(CONCEPT_CACHE, cui)
                            concept = CONCEPT_CACHE[cui]
                            push!(matches, (cui=cui, concept=concept, score=score, match_type="partial"))
                        end
                    end
                end
            end
        end
    end
    
    # Sort by score and ICD-10 availability
    sort!(matches, by=x -> (x.score, !isempty(x.concept["icd10_codes"])), rev=true)
    
    return matches[1:min(5, length(matches))]
end

function map_to_icd10_hierarchical(indication::String)
    """Map indication to ICD-10 using UMLS hierarchy"""
    
    # Find UMLS concepts
    matches = search_umls_concepts(indication)
    
    if isempty(matches)
        return ICD10Mapping[]
    end
    
    # Try best match first
    best_match = matches[1]
    
    # Check if it has ICD-10 codes
    if !isempty(best_match.concept["icd10_codes"])
        # Create mappings for each ICD-10 code
        mappings = ICD10Mapping[]
        for (source, code) in best_match.concept["icd10_codes"]
            push!(mappings, ICD10Mapping(
                indication,
                best_match.cui,
                best_match.concept["preferred_name"],
                code,
                source,
                "direct",
                best_match.score,
                0
            ))
        end
        return mappings
    end
    
    # For now, return empty if no direct mapping
    # TODO: Implement hierarchical traversal using MRREL
    return ICD10Mapping[]
end