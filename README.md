# Biomedical Drug-Disease Association Pipeline

A streamlined Julia pipeline for extracting approved FDA drugs from DrugBank, identifying disease-related MeSH descriptors, and querying PubMed for drug-disease associations.

## Core Functions

This pipeline performs three essential functions:

1. **Extract approved FDA drugs from DrugBank XML files**
2. **Extract MeSH descriptors of Disease semantic type (T047)**  
3. **Query PubMed for articles containing approved drugs indexed with disease-relevant MeSH descriptors**

## Summary

This streamlined pipeline performs the three core functions:

✅ **Extract FDA-approved drugs** from DrugBank XML files  
✅ **Extract disease-type MeSH descriptors** (semantic type T047)  
✅ **Query PubMed for drug-disease associations** through publication analysis

The pipeline is focused, efficient, and produces evidence-based drug-disease association data suitable for biomedical research and pharmaceutical analysis.

## Pipeline Components

### 1. Drug Extraction (`approved_drugs_extractor.jl`)
- Extracts approved drugs from DrugBank XML files
- Filters for FDA-approved drugs with valid indications
- Outputs curated drug datasets in multiple formats

### 2. Disease Classification (`mesh_t047_extractor.jl`)
- Extracts MeSH descriptors with semantic type T047 (Disease or Syndrome)
- Processes MeSH descriptor binary files
- Creates disease classification datasets

### 3. Drug-Disease Association (`pubmed_drug_indications.jl`)
- Unified pipeline that searches PubMed for publications mentioning approved drugs
- Fetches detailed publication data including MeSH descriptors
- Analyzes disease associations using MeSH T047 terms
- Generates comprehensive drug-disease association reports

## Features

- **Complete XML Parsing**: Parse DrugBank XML files efficiently with EzXML.jl
- **Quality Filtering**: Extract only approved drugs with meaningful indications  
- **Automated PubMed Search**: Intelligent query generation and publication retrieval
- **Disease Classification**: Semantic type T047 (diseases/syndromes) extraction
- **Association Analysis**: Maps drugs to disease conditions via MeSH descriptors
- **Multiple Formats**: JSON, CSV, and Julia-native outputs
- **Progress Tracking**: Real-time progress reporting for large datasets
- **Error Handling**: Robust error recovery and validation

## Configuration

### Demo vs Production Mode

The pipeline includes an easy toggle between demonstration and production modes:

**Demonstration Mode (Default)**
- Set `DEMO_MODE = true` in `pubmed_drug_indications.jl`
- Processes 10 drugs maximum
- Retrieves 50 results per drug
- Analyzes 10 PMIDs per drug
- Perfect for testing and validation

**Production Mode** 
- Set `DEMO_MODE = false` in `pubmed_drug_indications.jl`
- Processes all 2915+ approved drugs
- No limits on results or PMIDs
- Full-scale analysis for research use

Simply edit line 41 in `pubmed_drug_indications.jl`:
```julia
const DEMO_MODE = true   # Demonstration mode
const DEMO_MODE = false  # Production mode
```

## Requirements

### System Requirements
- Julia 1.6+
- Internet connection for PubMed API access

### Julia Packages
```julia
using Pkg
Pkg.add([
    "EzXML",        # XML parsing for DrugBank
    "HTTP",         # PubMed API requests  
    "JSON3",        # JSON processing
    "CSV",          # CSV file handling
    "DataFrames"    # Data manipulation
])
```

### Required Data Files
- **DrugBank XML**: Download from https://go.drugbank.com/releases/latest (requires free account)
- **MeSH Descriptor File**: Download from https://www.nlm.nih.gov/mesh/filelist.html

## File Structure

```
thera/
├── approved_drugs_extractor.jl       # Core: Extract FDA-approved drugs
├── mesh_t047_extractor.jl            # Core: Extract disease MeSH terms
├── pubmed_drug_indications.jl        # Core: Unified PubMed drug-disease analysis
├── README.md                         # Documentation
├── approved_drugs_dict.jl            # Output: Drug dictionary
├── mesh_t047_headings.jl            # Output: Disease classifications
└── [generated files]                 # Pipeline outputs
```

## Usage Example

```bash
# 1. Extract approved drugs
julia approved_drugs_extractor.jl drugbank.xml

# 2. Extract disease terms  
julia mesh_t047_extractor.jl d2025.bin

# 3. Analyze drug-disease associations (unified pipeline)
julia pubmed_drug_indications.jl
```

## License

This pipeline is designed for research and educational purposes.
Ensure compliance with DrugBank and PubMed usage policies.

## Data Sources

- **DrugBank**: Comprehensive drug database with approved FDA drugs
- **PubMed**: NCBI's biomedical literature database (30+ million citations)
- **MeSH**: Medical Subject Headings vocabulary for disease classification

## Pipeline Architecture

```
┌─────────────────────┐    ┌─────────────────────┐
│   DrugBank XML      │    │   MeSH Descriptors  │
│   (Drug Data)       │    │   (Disease Terms)   │
└──────────┬──────────┘    └──────────┬──────────┘
           │                          │
           ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐
│ approved_drugs_     │    │ mesh_t047_          │
│ extractor.jl        │    │ extractor.jl        │
└──────────┬──────────┘    └──────────┬──────────┘
           │                          │
           ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐
│ Approved Drugs      │    │ Disease             │
│ Dictionary          │    │ Classifications     │
│ (~3,000 drugs)      │    │ (~3,200 diseases)   │
└──────────┬──────────┘    └──────────┬──────────┘
           │                          │
           └──────────┬───────────────┘
                      ▼
           ┌─────────────────────┐
           │ pubmed_drug_        │
           │ indications.jl      │
           │ (Unified Pipeline)  │
           └──────────┬──────────┘
                      ▼
           ┌─────────────────────┐
           │ Drug-Disease        │
           │ Associations        │
           │ (Evidence-based)    │
           └─────────────────────┘
```

## Core Features

- **FDA-Approved Drugs Only**: Filters DrugBank for approved drugs with valid indications
