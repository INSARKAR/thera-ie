# THERA-IE Deployment Guide

## Quick Deployment for New Projects

### Prerequisites Checklist
- [ ] Julia 1.11+ installed
- [ ] Python 3.11+ with spaCy (`python -m spacy download en_core_web_sm`)
- [ ] Ollama with Llama 3.2 model
- [ ] Access to UMLS 2025AA database
- [ ] MeSH 2025 data files (place in `../_data/mesh/` directory)
- [ ] SLURM environment (optional, for HPC deployment)

### Core Package (Minimal Deployment)

For new projects, you only need these **essential files**:

```bash
# Core extraction scripts (3 files)
core_scripts/extraction/phase2_step1_top10_drugbank_extractor.jl
core_scripts/extraction/phase2_step2_top10_naive_extractor.jl
core_scripts/extraction/phase2_step3_top10_pubmed_extractor.jl

# Core evaluation script (1 file)
core_scripts/evaluation/phase3_simple_string_evaluator.jl

# Core analysis scripts (3 files)  
core_scripts/analysis/analyze_pubmed_corpus.jl
core_scripts/analysis/analyze_cross_method_stats.jl
core_scripts/analysis/generate_pubmed_mesh_table.jl

# Utilities (2 files)
utilities/quickumls_wrapper.py
utilities/install_quickumls.py

# Configuration (2 directories)
config/
prompts/

# Documentation (3 files)
README.md
THERA-IE_FINAL_RESULTS.md
DEPLOYMENT_GUIDE.md
```

### Configuration Setup

1. **Update paths in config files**:
```bash
# Edit config/hpc_config.env
export UMLS_DB_PATH="/your/path/to/umls/2025AA/"
export OLLAMA_HOST="localhost:11434"

# Edit config/umls_config.json
{
  "umls_db_path": "/your/path/to/umls/umls_medical.db",
  "quickumls_index": "/your/path/to/quickumls_index"
}

# Ensure MeSH data is available
# Place MeSH 2025 data files (e.g., d2025.bin) in:
mkdir -p ../_data/mesh/
# Copy your MeSH files to ../_data/mesh/
```

2. **Customize drug lists**:
```bash
# Create your target drug list
echo -e "Drug1\nDrug2\nDrug3" > your_drugs.txt
```

3. **Adapt prompts** (optional):
```bash
# Modify prompts in prompts/ directory for:
# - Different therapeutic areas
# - Alternative output formats  
# - Specific clinical contexts
```

### Running for New Drugs

1. **Single drug extraction**:
```bash
# DrugBank method
julia core_scripts/extraction/phase2_step1_top10_drugbank_extractor.jl YourDrug

# Knowledge method
julia core_scripts/extraction/phase2_step2_top10_naive_extractor.jl YourDrug

# Literature method  
julia core_scripts/extraction/phase2_step3_top10_pubmed_extractor.jl YourDrug
```

2. **Batch processing**:
```bash
# Process multiple drugs from file
for drug in $(cat your_drugs.txt); do
    julia core_scripts/extraction/phase2_step2_top10_naive_extractor.jl $drug
done
```

3. **Cross-method evaluation**:
```bash
julia core_scripts/evaluation/phase3_simple_string_evaluator.jl
```

### Customization Examples

#### New Therapeutic Area (Oncology)
```bash
# 1. Create oncology drug list
echo -e "Doxorubicin\nCisplatin\nTamoxifen" > oncology_drugs.txt

# 2. Customize prompts for cancer indications
sed 's/disease/cancer type/g' prompts/llm_prompt_naive_snomed_top10.txt > prompts/oncology_naive.txt

# 3. Run extraction
julia core_scripts/extraction/phase2_step2_top10_naive_extractor.jl Doxorubicin
```

#### Different Output Format
```julia
# Modify extraction scripts to output CSV instead of JSON
# Example: Replace JSON3.pretty() with CSV.write()
```

#### Integration with EHR System
```julia
# Add database connection in extraction scripts
# Example: Write results directly to clinical database
```

### Performance Optimization

#### Speed Optimization
```bash
# Use knowledge method for rapid screening
julia core_scripts/extraction/phase2_step2_top10_naive_extractor.jl
# Processing time: ~3 minutes per drug
```

#### Accuracy Optimization  
```bash
# Use literature method for comprehensive analysis
julia core_scripts/extraction/phase2_step3_top10_pubmed_extractor.jl
# Processing time: ~8 minutes per drug, higher recall
```

#### Balanced Approach
```bash
# Run both methods and combine results
# Achieves 91.8% unique indication coverage
```

### HPC Deployment

For large-scale pharmaceutical deployment:

1. **SLURM integration**:
```bash
# Create SLURM scripts based on core extraction scripts
# Example template for drugbank extraction:
#SBATCH --job-name=drugbank_extraction
#SBATCH --nodes=1
#SBATCH --tasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16GB
julia core_scripts/extraction/phase2_step1_top10_drugbank_extractor.jl
```

2. **GPU allocation**:
```bash
#SBATCH --gres=gpu:1
#SBATCH --mem=16G
```

3. **Parallel processing**:
```bash
# Process multiple drugs simultaneously
# Use array jobs for batch processing
```

### Quality Assurance

#### Validation Pipeline
```bash
# 1. Run extraction
julia core_scripts/extraction/phase2_step2_top10_naive_extractor.jl YourDrug

# 2. Validate results
julia core_scripts/evaluation/phase3_simple_string_evaluator.jl

# 3. Generate reports
julia core_scripts/analysis/analyze_cross_method_stats.jl
```

#### Error Handling
- Check confidence scores (>0.6 recommended)
- Validate SNOMED codes against UMLS
- Review supporting PMIDs for literature method

### Troubleshooting

#### Common Issues
1. **UMLS connection**: Check database path in config
2. **Ollama model**: Ensure Llama 3.2 is downloaded
3. **Python dependencies**: Install spaCy English model
4. **Memory issues**: Increase allocation for large drug lists

#### Performance Monitoring
```bash
# Track processing times
time julia core_scripts/extraction/phase2_step2_top10_naive_extractor.jl YourDrug

# Monitor confidence scores
grep "confidence" results/YourDrug_naive_snomed.json
```

### Support and Extension

#### Adding New Methods
1. Create new extraction script in `core_scripts/extraction/`
2. Add corresponding prompt in `prompts/`
3. Update evaluation script to include new method
4. Document changes in README.md

#### Integration Points
- **Database connectors**: Add in extraction scripts
- **API endpoints**: Wrap scripts in web service
- **Real-time processing**: Implement streaming interface
- **Clinical workflows**: Integrate with EHR systems

### Maintenance

#### Regular Updates
- Update UMLS database annually
- Refresh PubMed corpus quarterly  
- Monitor LLM model performance
- Validate against new clinical guidelines

#### Backup Strategy
- Version control all scripts
- Archive result datasets
- Maintain configuration history
- Document customizations

---

**Ready for deployment!** This guide provides everything needed to deploy THERA-IE for new therapeutic areas, drug lists, or clinical applications. The modular architecture ensures easy customization while maintaining core functionality.

*For technical support, see THERA-IE_FINAL_RESULTS.md for complete results and methodology details.*