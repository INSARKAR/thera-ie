# Thera Drug-Indication Analysis Project

A comprehensive Julia-based pipeline for extracting drug-indication pairings from PubMed publications using Llama 3.2 via Ollama on HPC/SLURM environments.

## 🚀 Quick Start

1. **Run the complete analysis**:
   ```bash
   julia quick_start.jl
   ```

2. **For HPC/SLURM environments**:
   ```bash
   cd scripts/slurm
   ./submit_fresh_job.sh        # Submit Llama extraction job
   ./monitor_fresh_extraction.sh # Monitor progress
   ```

## 📁 Project Structure

```
thera/
├── 📊 **Core Analysis Scripts**
│   ├── quick_start.jl                    # Main entry point
│   ├── pubmed_drug_indications.jl        # Core PubMed analysis
│   └── slurm_pubmed_drug_indications.jl  # SLURM-compatible version
│
├── 🧠 **Llama/AI Extraction**
│   ├── scripts/extraction/              # Llama extraction scripts
│   │   ├── intelligent_drug_extractor.jl # Efficient drug-disease extraction
│   │   ├── test_intelligent_extractor.jl # Test script for the intelligent extractor
│   │   ├── intelligent_extraction.slurm # SLURM job for intelligent extraction
│   │   └── submit_intelligent_extractions.sh # Multi-drug submission helper
│   ├── scripts/slurm/                  # SLURM job scripts
│   └── scripts/monitoring/             # Progress monitoring tools
│
├── 🔧 **Configuration & Setup**
│   ├── config/                         # Configuration files
│   ├── scripts/setup/                  # Environment setup scripts
│   └── Project.toml                    # Julia project dependencies
│
├── 📚 **Data Directories**
│   ├── drug_pubmed_refs/               # Drug publication data
│   ├── llama_pubmed_extracted_indications/ # AI extraction results
│   └── logs/                           # Execution logs
│
├── 🧪 **Testing**
│   ├── tests/unit/                     # Unit tests
│   ├── tests/integration/              # Integration tests
│   └── tests/debug/                    # Debugging scripts
│
├── 📖 **Documentation**
│   ├── docs/usage/                     # User guides
│   ├── docs/implementation/            # Technical details
│   └── docs/summaries/                 # Project summaries
│
└── 🗄️ **Archive**
    ├── archive/old_versions/           # Previous versions
    └── archive/deprecated/             # Deprecated code
```

## 🎯 Main Features
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

# 3. Configure mode (optional - defaults to demo mode)
# Edit pubmed_drug_indications.jl line 41:
# const DEMO_MODE = true   # For demonstration (10 drugs)
# const DEMO_MODE = false  # For production (all drugs)

# 4. Analyze drug-disease associations (unified pipeline)
julia scripts/extraction/pubmed_drug_indications.jl
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

## Advanced Features

### 1. Traditional PubMed Analysis
- **Script**: `pubmed_drug_indications.jl`
- **Description**: Extracts drug-disease associations from MeSH terms
- **Output**: Structured JSON files with drug-indication mappings

### 2. AI-Powered Extraction (Llama 3.2)
- **Script**: `scripts/extraction/fresh_levothyroxine_extractor.jl`
- **Description**: Uses Llama 3.2 to extract indications from publication text
- **Features**: 
  - GPU-accelerated processing
  - SLURM job management
  - Batch processing with checkpointing
  - Error handling and recovery

### 3. HPC/SLURM Integration
- **Location**: `scripts/slurm/`
- **Features**:
  - Automated GPU allocation
  - Ollama server management
  - Job monitoring and logging
  - Batch processing capabilities

## 🧠 Intelligent Drug-Disease Extraction

The intelligent drug-disease extractor implements a more efficient approach to identify and confirm drug indications:

### Two-Phase Approach
1. **Identification Phase**: First scans a sample of publications to identify all potential drug-disease pairs
2. **Verification Phase**: For each identified pair, processes only enough publications to confirm the indication

### Advantages
- **Efficiency**: Avoids processing all publications when indications are already confirmed
- **Precision**: Focuses on verifying specific drug-disease relationships
- **Confidence**: Provides confidence scores for each verified indication
- **Scalability**: Can process multiple drugs in parallel on HPC/SLURM

### Usage

#### Local Testing
```bash
# Test the intelligent extractor locally
julia scripts/extraction/test_intelligent_extractor.jl
```

#### SLURM Execution
```bash
# Run for a single drug
sbatch scripts/extraction/intelligent_extraction.slurm Levothyroxine

# Run for multiple drugs
scripts/extraction/submit_intelligent_extractions.sh Levothyroxine Ibuprofen Metformin

# Run for drugs listed in a file
scripts/extraction/submit_intelligent_extractions.sh --list drug_list.txt
```

### Intelligent Extraction Output
```json
{
  "metadata": {
    "drug_name": "Levothyroxine",
    "total_publications": 5847,
    "processed_publications": 482,
    "total_disease_pairs": 16,
    "confirmed_disease_pairs": 7,
    "total_indications": 28,
    "confirmation_rate_percent": 43.75,
    "model_used": "llama3.2"
  },
  "disease_pairs": [
    {
      "drug": "Levothyroxine",
      "disease": "Hypothyroidism",
      "confidence": 0.92,
      "confirmed": true,
      "evidence_count": 3,
      "evidence": [
        {
          "pmid": "12345678",
          "confidence": 0.92,
          "title": "Treatment of hypothyroidism...",
          "extracted_at": "2025-07-01T21:00:00",
          "confirmed": true
        }
      ]
    }
  ]
}
```

## 🔬 Phase 1 Evaluation Pipeline

### Comprehensive Recovery Analysis
The project includes a sophisticated Phase 1 evaluation system that analyzes drug-indication recovery rates using multiple approaches:

1. **Naive LLM Extraction**: Direct indication extraction from publication abstracts
2. **PubMed LLM Analysis**: Enhanced extraction using structured PubMed data
3. **Recovery Analysis**: Compares extracted indications against DrugBank ground truth using UMLS medical terminology hierarchy

### Phase 1 Processing Features
- **UMLS Integration**: Uses comprehensive medical terminology database for semantic matching
- **Hierarchy-aware Recovery**: Leverages concept relationships for improved matching
- **Parallel Processing**: Optimized for HPC environments with sequential database access
- **Comprehensive Coverage**: **COMPLETE** - Processed 2,705+ approved drugs with detailed analytics (92.8% success rate)
- **Database Optimization**: Resolved SQLite concurrency issues for reliable large-scale processing

### Running Phase 1 Evaluation
```bash
# Run phase1 evaluation for all drugs
julia scripts/analysis/phase1_evaluation.jl

# For parallel processing (recommended for large datasets)
julia simple_parallel_analyzer.jl [drug_name]

# Check processing status
ls results_phase1/ | wc -l  # Count completed evaluations
```

### Phase 1 Output Format
```json
{
  "metadata": {
    "drug_name": "Levothyroxine", 
    "drugbank_indications_count": 3,
    "naive_indications_count": 8,
    "pubmed_llm_indications_count": 12,
    "processing_timestamp": "2025-07-12T10:15:57"
  },
  "recovery_analysis": {
    "naive_recovered": 2,
    "pubmed_recovered": 3,
    "naive_recovery_rate": 66.7,
    "pubmed_recovery_rate": 100.0,
    "drugbank_indications": ["Hypothyroidism", "Myxedema", "Thyroid hormone deficiency"]
  },
  "indications": {
    "naive_indications": [...],
    "pubmed_llm_indications": [...],
    "matched_concepts": [...]
  }
}
```

## 🚀 Usage Examples

### Basic Drug Analysis
```julia
# Analyze all approved drugs
julia quick_start.jl

# Analyze specific drug with phase1 evaluation
julia simple_parallel_analyzer.jl "Levothyroxine"
```

### Complete Pipeline Execution
```bash
# 1. Run traditional PubMed analysis
julia scripts/extraction/pubmed_drug_indications.jl

# 2. Run AI-powered extraction
julia scripts/extraction/llama_drug_extractor.jl

# 3. Run comprehensive phase1 evaluation
julia scripts/analysis/phase1_evaluation.jl

# 4. Check results
ls results_phase1/  # Phase1 evaluation results
ls drug_pubmed_refs/  # Traditional analysis results  
ls llama_pubmed_extracted_indications/  # AI extraction results
```

### SLURM Job Management
```bash
# Check job status
squeue -u $USER

# View logs
tail -f logs/fresh_extraction_*.out

# Cancel job if needed
scancel <job_id>
```

## 🔧 Dependencies

### Core Dependencies
- **Julia** ≥ 1.8
- **HTTP.jl** - API communication
- **JSON3.jl** - JSON processing
- **CSV.jl** - Data export
- **Dates.jl** - Timestamp handling

### HPC Dependencies
- **SLURM** - Job scheduling
- **Ollama** - Llama model hosting
- **CUDA** - GPU acceleration (for Llama)

### Install Dependencies
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## 📊 Output Formats

### Traditional Analysis Output
```json
{
  "drug_name": "Levothyroxine",
  "total_publications": 5847,
  "disease_associations": [
    {
      "disease": "Hypothyroidism",
      "mesh_term": "D007037",
      "publication_count": 2834,
      "confidence": 0.95
    }
  ]
}
```

### AI Extraction Output
```json
{
  "metadata": {
    "drug_name": "Levothyroxine",
    "total_publications": 5847,
    "successful_extractions": 2156,
    "total_indications": 24,
    "model_used": "llama3.2"
  },
  "indications": [
    {
      "indication": "Hypothyroidism",
      "confidence": 0.9,
      "pmid": "12345678",
      "title": "Treatment of hypothyroidism...",
      "extracted_at": "2025-07-01T21:00:00"
    }
  ]
}
```

## 🐛 Troubleshooting

### Common Issues

1. **Julia Package Errors**
   ```bash
   julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
   ```

2. **SLURM Job Failures**
   - Check logs in `logs/` directory
   - Verify GPU availability: `sinfo -p gpu`
   - Ensure Ollama module is loaded

3. **SQLite Database Locking Issues**
   ```bash
   # Remove stale lock files if database locking occurs
   rm -f /path/to/umls_medical.db-shm
   rm -f /path/to/umls_medical.db-wal
   
   # Use sequential processing instead of parallel for database-intensive tasks
   julia sequential_phase1_processor.jl [start_index] [batch_size]
   ```

4. **Ollama Connection Issues**
   ```bash
   module load ollama
   ollama serve &
   ollama pull llama3.2
   ```

5. **Large File Handling**
   - Use `.gitignore` to exclude large data files
   - Consider using `git lfs` for large model files

### Database Concurrency Best Practices
- **Sequential Processing**: For UMLS database queries, use sequential processing to avoid SQLite locking
- **Lock File Cleanup**: Remove `.db-shm` and `.db-wal` files if persistent locking occurs
- **Connection Management**: Implement retry logic with exponential backoff for database connections

### Performance Optimization

1. **For Large Datasets**
   - Use batch processing (`BATCH_SIZE` parameter)
   - Enable checkpointing for long-running jobs
   - Monitor memory usage with `scripts/monitoring/`

2. **For Faster Processing**
   - Increase parallel workers
   - Use SSD storage for temporary files
   - Optimize Ollama model settings

## 📈 Monitoring & Logging

### Real-time Monitoring
```bash
# Monitor job progress
watch -n 30 'squeue -u $USER'

# Monitor extraction progress
tail -f logs/fresh_extraction_*.out

# Check resource usage
watch -n 5 'nvidia-smi'
```

### Log Analysis
- **Job logs**: `logs/` directory
- **Error logs**: `*.err` files
- **Progress logs**: Look for progress indicators in output logs

## 🤝 Contributing

1. **Adding New Features**
   - Place scripts in appropriate `scripts/` subdirectory
   - Update documentation in `docs/`
   - Add tests in `tests/`

2. **Code Organization**
   - Core functionality: Root directory
   - Utilities: `scripts/` subdirectories  
   - Configuration: `config/` directory
   - Archives: `archive/` directory

## 📄 License

This project is licensed under the terms specified in the `LICENSE` file.

## 🆘 Support

For issues and questions:
1. Check the documentation in `docs/`
2. Review common issues in this README
3. Check existing logs for error messages
4. Review the archived solutions in `archive/`

---

**Note**: This project is optimized for HPC environments with SLURM job scheduling and GPU acceleration capabilities.
