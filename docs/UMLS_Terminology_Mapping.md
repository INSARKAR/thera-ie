# UMLS-Based Medical Terminology Mapping

## Overview

This document describes the implementation of a scalable medical terminology mapping system using the **Unified Medical Language System (UMLS)** for drug indication overlap analysis.

## Why UMLS?

### Current Problem
Different extraction methods (PubMed, DrugBank, Naive) express the same medical conditions using different terminology:
- "Hypothyroidism" vs "Thyroid hormone deficiency" vs "Underactive thyroid"
- "Type 2 diabetes mellitus" vs "Diabetes" vs "Adult-onset diabetes"

### UMLS Solution
UMLS provides:
- **Standardized Concept Unique Identifiers (CUIs)** for medical concepts
- **Comprehensive synonym mapping** across 200+ medical vocabularies
- **Semantic type classification** (e.g., T047 = Disease or Syndrome)
- **Cross-vocabulary harmonization** (ICD, SNOMED, MeSH, etc.)

## Architecture

### Core Components

1. **UMLS Terminology Mapper** (`umls_terminology_mapper.jl`)
   - Maps text indications to UMLS CUIs
   - Handles synonym matching and semantic typing
   - Provides confidence scoring for mappings

2. **UMLS Overlap Analyzer** (`umls_overlap_analyzer.jl`)
   - Compares extraction methods using CUI-based matching
   - Calculates precise overlap percentages
   - Identifies semantic similarities beyond exact text matching

### Data Flow

```
Raw Indication Text → UMLS API → CUI Mapping → Overlap Analysis
                                    ↓
Medical Concepts ← Semantic Types ← Synonyms
```

## Setup Requirements

### 1. UMLS API Access
```bash
# Register at: https://uts.nlm.nih.gov/uts/
# Get API key and set environment variable
export UMLS_API_KEY="your_umls_api_key_here"
```

### 2. Installation
```bash
# Make scripts executable
chmod +x scripts/analysis/umls_terminology_mapper.jl
chmod +x scripts/analysis/umls_overlap_analyzer.jl

# Test UMLS connection
julia scripts/analysis/umls_terminology_mapper.jl test
```

## Usage Examples

### 1. Map Single Indication
```bash
julia scripts/analysis/umls_terminology_mapper.jl map_indication "Hypothyroidism"
```

### 2. Compare Extraction Methods
```bash
# Compare naive vs drugbank for Levothyroxine
julia scripts/analysis/umls_overlap_analyzer.jl naive drugbank Levothyroxine

# Compare pubmed vs drugbank for Metformin
julia scripts/analysis/umls_overlap_analyzer.jl pubmed drugbank Metformin
```

### 3. Build Concept Cache
```bash
julia scripts/analysis/umls_terminology_mapper.jl build_cache
```

## Key Features

### 1. Intelligent Concept Matching
- **Exact CUI matching**: Same concept, different text expressions
- **Semantic type matching**: Related concepts within same medical category
- **Confidence scoring**: Weighted by match quality and semantic relevance

### 2. Medical Condition Filtering
Uses UMLS semantic types to focus on medical conditions:
- T047: Disease or Syndrome
- T048: Mental or Behavioral Dysfunction  
- T049: Cell or Molecular Dysfunction
- T191: Neoplastic Process
- And 10+ other medical semantic types

### 3. Comprehensive Vocabulary Coverage
UMLS integrates 200+ medical vocabularies:
- **ICD-10**: International disease classification
- **SNOMED CT**: Clinical terminology
- **MeSH**: Medical subject headings
- **RxNorm**: Drug terminology
- **LOINC**: Laboratory data

### 4. Performance Optimization
- **Caching system**: Reduces repeated API calls
- **Batch processing**: Efficient for multiple indications
- **Rate limiting**: Respects UMLS API constraints

## Expected Improvements

### Before UMLS Mapping
```
Levothyroxine Overlap Analysis (Simple Text Matching):
- Naive vs DrugBank: 20% overlap
- Limited to exact text matches
- Misses semantic equivalences
```

### After UMLS Mapping
```
Levothyroxine Overlap Analysis (UMLS-Based):
- Naive vs DrugBank: 60-80% overlap (estimated)
- CUI-based concept matching
- Captures semantic relationships
- Standardized medical terminology
```

## Validation Approach

### 1. Medical Expert Review
- Sample mappings reviewed by medical professionals
- Validation of CUI assignments
- Assessment of clinical relevance

### 2. Cross-Vocabulary Consistency
- Compare mappings across different medical vocabularies
- Ensure consistent concept identification
- Validate semantic type assignments

### 3. Performance Metrics
- **Mapping Rate**: Percentage of indications successfully mapped
- **Confidence Distribution**: Quality of concept matches
- **Overlap Accuracy**: Clinical validation of identified overlaps

## Alternative Approaches

### 1. SNOMED CT Direct
- Use SNOMED CT concepts directly
- More clinically focused than UMLS
- Requires separate SNOMED license

### 2. BioPortal API
- Access to multiple ontologies via single API
- Includes UMLS but also specialized ontologies
- May have different rate limits

### 3. Local UMLS Installation
- Download full UMLS dataset locally
- Faster processing, no API limits
- Requires significant storage (>10GB)
- Complex setup and licensing

## Implementation Notes

### Error Handling
- Graceful API failure handling
- Fallback to text-based matching
- Comprehensive logging for debugging

### Scalability
- Batch processing for large datasets
- Caching for frequently accessed concepts
- Parallel processing capability

### Quality Assurance
- Confidence thresholds for mapping acceptance
- Manual review flags for low-confidence mappings
- Validation against known medical concept databases

## Output Format

### UMLS Mapping Result
```json
{
  "original_text": "Hypothyroidism",
  "cui": "C0020676",
  "preferred_name": "Hypothyroidism",
  "semantic_type": "T047",
  "confidence_score": 1.0,
  "mapping_method": "exact_preferred"
}
```

### Overlap Analysis Result
```json
{
  "metadata": {
    "drug_name": "Levothyroxine",
    "overlap_percentage": 75.0,
    "cui_exact_matches": 3,
    "semantic_matches": 1
  },
  "matched_pairs": [
    {
      "cui": "C0020676",
      "extraction1_text": "Hypothyroidism",
      "extraction2_text": "Thyroid hormone deficiency"
    }
  ]
}
```

This UMLS-based approach provides a robust, scalable foundation for medical terminology mapping that will significantly improve the accuracy of drug indication overlap analysis across different extraction methods.