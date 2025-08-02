# THERA-IE Directory Structure

## Core Data Directories
- `phase1_step1_drugbank_extraction/` - DrugBank ground truth data (10 drugs)
- `phase2_step1_drugbank_snomed/` - DrugBank method results (10 drugs)  
- `phase2_step2_naive_snomed/` - Knowledge method results (10 drugs)
- `phase2_step3_pubmed_snomed/` - Literature method results (10 drugs)
- `phase3_simple_results/` - Cross-method evaluation results (11 files)

## Core Scripts
- `core_scripts/extraction/` - Main extraction algorithms (3 methods)
- `core_scripts/evaluation/` - Cross-method evaluation
- `core_scripts/analysis/` - Statistical analysis and reporting

## Configuration & Utilities
- `config/` - System configuration files
- `prompts/` - LLM prompts for each method (3 files)
- `utilities/` - QuickUMLS integration scripts

## Analysis Results
- `analysis_results/` - Organized analysis outputs
  - `corpus_analysis/` - PubMed corpus statistics
  - `evaluation_results/` - Cross-method analysis
  - `reference_data/` - Reference datasets
  - `terminology_mapping/` - MeSH-SNOMED mapping

## Documentation  
- `README.md` - Project overview and quick start
- `THERA-IE_FINAL_RESULTS.md` - Complete results summary
- `DEPLOYMENT_GUIDE.md` - Step-by-step deployment guide

## External Dependencies
- `../_data/mesh/` - MeSH 2025 data files (external)
