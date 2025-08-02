# THERA-IE: Therapeutic Indication Extraction System

A system for automated drug indication extraction using multiple approaches: DrugBank-based (ground truth), knowledge-based LLM extraction (naive), and literature-based evidence mining (pubmed).

## Overview

THERA-IE systematically evaluates three methods for extracting therapeutic indications:

1. **DrugBank Method**: Ground truth extraction from DrugBank pharmaceutical database
2. **Knowledge Method**: Direct LLM-based extraction using pre-trained pharmaceutical knowledge  
3. **Literature Method**: Evidence-based extraction from PubMed scientific literature

## Key Results

### Phase 3 Cross-Method Evaluation (Top 10 US Drugs)

- **Literature method outperforms knowledge method**: 23.8% vs 17.4% average recovery rate
- **High complementarity**: 91.8% of indications are unique to each method
- **Processing efficiency**: Knowledge (2.9±0.2 min/drug), Literature (7.9±0.7 min/drug)
- **Confidence scores**: Knowledge (0.79±0.10), Literature (0.73±0.15)

### Corpus Statistics
(as of 2025-08-01)
- **97,963 publications** identified across 10 target drugs
- **73,736 publications** retained after filtering (75.3% retention)
- **9,712 unique MeSH descriptors** analyzed
- **39.7%** of publications from last 10 years

## Project Structure

```
thera-ie/
├── README.md                          # Project overview
├── DEPLOYMENT_GUIDE.md                # Deployment instructions
├── THERA-IE_FINAL_RESULTS.md          # Complete results summary
├── analysis_results/                  # Organized analysis outputs
├── config/                            # Configuration files
├── core_scripts/                      # Main extraction & analysis scripts
├── phase1_step1_drugbank_extraction/  # DrugBank ground truth data
├── phase2_step1_drugbank_snomed/      # DrugBank method results
├── phase2_step2_naive_snomed/         # Knowledge method results  
├── phase2_step3_pubmed_snomed/        # Literature method results
├── phase3_simple_results/             # Cross-method evaluation
├── prompts/                           # LLM prompts for each method
└── utilities/                         # QuickUMLS integration scripts
```

## Quick Start

### Prerequisites

- Julia 1.11+
- Python 3.11+ with spaCy
- Access to UMLS 2025AA database
- MeSH 2025 data files (place in `../_data/mesh/` directory)
- Ollama with Llama 3.2 model

### Running Evaluations

1. **Phase 2 Extraction** (all methods):
```bash
# DrugBank method
julia phase2_step1_top10_drugbank_extractor.jl

# Knowledge method  
julia phase2_step2_top10_naive_extractor.jl

# Literature method
julia phase2_step3_top10_pubmed_extractor.jl
```

2. **Phase 3 Cross-Method Evaluation**:
```bash
julia phase3_simple_string_evaluator.jl
```

3. **Generate Analysis Reports**:
```bash
julia analyze_pubmed_corpus.jl
julia analyze_cross_method_stats.jl
```

## Key Scripts

### Core Extraction Scripts
- `phase2_step1_top10_drugbank_extractor.jl` - DrugBank ground truth extraction
- `phase2_step2_top10_naive_extractor.jl` - Knowledge-based extraction  
- `phase2_step3_top10_pubmed_extractor.jl` - Literature-based extraction
- `phase3_simple_string_evaluator.jl` - Cross-method evaluation

### Analysis Scripts
- `analyze_pubmed_corpus.jl` - PubMed corpus statistics
- `analyze_cross_method_stats.jl` - Cross-method performance analysis
- `generate_pubmed_mesh_table.jl` - MeSH descriptor analysis

### Utility Scripts
- `quickumls_wrapper.py` - UMLS concept mapping interface
- `reprocess_parsing_fix.jl` - Result validation and correction

## Methods

### DrugBank Method
- Extracts confirmed therapeutic indications from DrugBank database
- Maps to SNOMED CT terminology using UMLS
- Serves as ground truth for evaluation

### Knowledge Method  
- Uses Llama 3.2 LLM with pharmaceutical knowledge
- Direct extraction without external data sources
- Fast processing: 2.9±0.2 minutes per drug

### Literature Method
- Samples 5 publications per MeSH descriptor from PubMed corpus
- LLM extraction with literature evidence
- Comprehensive processing: 7.9±0.7 minutes per drug

## Evaluation Metrics

- **Recovery Rate**: Percentage of ground truth indications identified
- **Unique Contributions**: Method-specific therapeutic discoveries
- **Confidence Scores**: Extraction reliability (0-1 scale)
- **Processing Time**: Computational efficiency

## Key Findings

1. **Complementary Methods**: 91.8% of indications are unique to each method
2. **Literature Advantage**: Evidence-based approach outperforms knowledge-only
3. **Scalability**: Both methods suitable for pharmaceutical-scale deployment
4. **Quality**: High confidence scores across all methods

## Configuration

### UMLS Database
- Path: `/oscar/data/ursa/umls/2025AA/`
- Local cache: `umls/umls_medical.db`

### LLM Configuration  
- Model: Llama 3.2 (via Ollama)
- Temperature: 0.1 (deterministic extraction)
- Max tokens: 2000

### SLURM Integration
- GPU allocation for LLM processing
- Batch job submission scripts in `slurm_scripts/`

## Output Formats

### Individual Drug Results
```json
{
  "drug_name": "Atorvastatin",
  "snomed_indications": [
    {
      "snomed_term": "Hypercholesterolemia", 
      "snomed_code": "13644009",
      "confidence": 0.95,
      "supporting_pmids": ["12345678", "87654321"]
    }
  ],
  "extraction_metadata": {...}
}
```

### Cross-Method Evaluation
```json
{
  "drug_name": "Atorvastatin",
  "method_evaluation": {
    "knowledge": {"recovery_rate": 0.50, "matches": [...]},
    "literature": {"recovery_rate": 0.29, "matches": [...]}
  },
  "unique_indications_analysis": {...}
}
```

## Citation

```bibtex
@misc{thera-ie-2025,
  title={THERA-IE: A System for Knowledge-Based Drug Indication Extraction},
  author={THERA-IE Development Team},
  year={2025},
  note={Comprehensive evaluation of therapeutic indication extraction methods}
}
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## Support

For questions or issues:
- See `THERA-IE_FINAL_RESULTS.md` for comprehensive methodology and results
- Review `DEPLOYMENT_GUIDE.md` for step-by-step deployment instructions
- Check example outputs in result directories
- See configuration files in `config/`

---
**THERA-IE**: Advancing pharmaceutical knowledge discovery through systematic therapeutic indication extraction. Portions of the code included here was developed or improved using Claude Code Agent (Sonnet 4). This documentation was also partially auto-generated using Claude (Sonnet 4).
