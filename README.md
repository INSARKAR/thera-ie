# THERA-IE: A System for Knowledge Based Drug Indication Extraction

**THERA** (Therapeutic Hypothesis Extraction and Relationship Analytics) **- IE** (Indication Extraction)

A Julia-based system for extracting therapeutic drug-indication relationships from biomedical literature using hybrid AI-powered and traditional MeSH-based approaches. This pipeline is optimized for HPC/SLURM environments.

## 🎯 Project Overview

THERA-IE integrates multiple methodological approaches to create a literature-mediated drug-indication dataset:

- **📚 Literature-Based**: Extracts indications from 5M+ PubMed publications
- **🏷️ MeSH-Guided**: Leverages Medical Subject Headings for semantic organization
- **🧠 AI-Powered**: Uses Llama 3.2 for intelligent text analysis and extraction  
- **⚡ HPC-Optimized**: Designed for parallel processing on SLURM/GPU systems

The results are benchmarked relative to indications noted in DrugBank. DrugBank is also the source of determining the set of FDA-approved drugs.

## 🚀 Quick Start

### Automatic Setup (Recommended)
```bash
# Auto-detect environment and run appropriate setup
julia final_scripts/phase0/phase0_step5_environment_setup.jl
```

### Manual Setup
```bash
# For local development
julia final_scripts/phase0/phase0_step6_local_setup.jl

# For HPC/SLURM environments
julia final_scripts/phase0/phase0_step7_hpc_setup.jl
```

## ✅ Current Status

| Phase | Component | Status | Results |
|-------|-----------|--------|---------|
| **Phase 0** | Foundation Setup | ✅ **COMPLETE** | 2,915 approved drugs, 5,895 MeSH descriptors |
| **Phase 1** | PubMed Extraction | ✅ **COMPLETE** | 2,623 drugs, 5M+ publications, 54M+ MeSH terms |
| **Phase 2** | AI Indication Extraction | ✅ **COMPLETE** | 4 methodologies, 2,600+ drugs per method |
| **Phase 3** | Comparative Analysis | 🎯 **READY** | Integration and validation framework prepared |

### Phase 2 Complete Results:
- **🏪 DrugBank AI Extraction**: 2,909 drugs with AI-parsed indication text
- **🏷️ MeSH-Based Analysis**: 2,623 drugs with literature-derived indications  
- **🧠 Knowledge-Based**: 2,932 drugs with LLM pre-trained knowledge
- **📖 Evidence-Based**: 2,624 drugs with PMID-supported indications

## 🏗️ Architecture

### Multi-Phase Pipeline
```
Phase 0: Foundation        Phase 1: Data Extraction      Phase 2: AI Processing
┌─────────────────┐       ┌─────────────────┐           ┌─────────────────┐
│ DrugBank XML    │────→  │ PubMed Search   │────→      │ Llama 3.2       │
│ MeSH Data       │       │ Publication     │           │ AI Extraction   │
│ Environment     │       │ Retrieval       │           │ Multi-Method    │
└─────────────────┘       └─────────────────┘           └─────────────────┘
        ↓                          ↓                            ↓
┌─────────────────┐       ┌─────────────────┐           ┌─────────────────┐
│ 2,915 Drugs     │       │ 5M+ Publications│           │ 4 Indication    │
│ 5,895 MeSH      │       │ 54M+ MeSH Terms │           │ Datasets        │
│ Dependencies    │       │ 2,623 Drug Files│           │ Evidence Links  │
└─────────────────┘       └─────────────────┘           └─────────────────┘
```

### Hybrid Extraction Methodologies

1. **📊 MeSH-Based** (`phase2_indications_mesh/`)
   - Traditional approach using MeSH descriptor co-occurrence
   - High precision, established medical vocabulary
   - Evidence: Publications with shared MeSH terms

2. **🧠 Knowledge-Based** (`phase2_indications_llama_naive/`) 
   - AI model's pre-trained pharmaceutical knowledge
   - Fast, dependency-free extraction
   - Evidence: LLM training data and medical knowledge

3. **📖 Evidence-Based** (`phase2_indications_llama_pubmed/`)
   - AI analysis of actual research abstracts
   - Highest quality, PMID-linked evidence
   - Evidence: Specific research publications with citations

4. **🏪 DrugBank AI** (`phase2_indications_llama_drugbank/`)
   - AI parsing of structured drug database text
   - Comprehensive therapeutic coverage
   - Evidence: Official drug labeling and documentation

## 📁 Project Structure

```
thera/
├── 🎯 final_scripts/              # Complete organized workflow (39 files)
│   ├── phase0/                    # Foundation setup and data preparation (12 files)
│   ├── phase1/                    # PubMed extraction and processing (12 files)
│   ├── phase2/                    # AI-powered indication extraction (14 files)
│   └── README.md                  # Detailed workflow documentation
│
├── 🔧 scripts/                    # Development utilities (58 files)
│   ├── extraction/                # Extraction tools and utilities
│   ├── analysis/                  # Analysis and validation scripts
│   ├── setup/                     # Environment setup utilities
│   └── slurm/                     # HPC job management scripts
│
├── 📊 **Results** (excluded from git)
│   ├── phase1_drug_pubmed_mesh/   # 10GB: MeSH-organized publications
│   ├── phase2_indications_*/      # 330MB: Final indication datasets
│   └── logs/                      # 797MB: Processing logs and outputs
│
├── 📖 docs/                       # Comprehensive documentation
│   ├── usage/                     # User guides and tutorials
│   ├── implementation/            # Technical implementation details
│   └── summaries/                 # Project reports and summaries
│
├── ⚙️ config/                     # Configuration files
│   ├── llama_config.jl           # LLM model parameters
│   ├── hpc_config.env            # HPC environment settings
│   └── umls_config.json          # Medical terminology settings
│
├── 💬 prompts/                    # LLM prompt templates
│   ├── llm_prompt_pubmed.txt     # Evidence-based extraction
│   ├── llm_prompt_naive.txt      # Knowledge-based extraction
│   └── llm_prompt_drugbank.txt   # DrugBank text parsing
│
└── 🧪 tests/                      # Validation and testing
    ├── unit/                      # Unit tests for core functions
    └── integration/               # End-to-end workflow tests
```

## 🎯 Key Features

### 🔬 **Comprehensive Coverage**
- **2,915 FDA-approved drugs** from DrugBank with quality filtering
- **5M+ publications** analyzed from PubMed's biomedical database
- **54M+ MeSH descriptors** extracted and semantically organized
- **4 extraction methodologies** for cross-validation and completeness

### 🚀 **HPC-Optimized Performance**
- **SLURM job arrays** with intelligent batch processing
- **GPU acceleration** for AI extraction with Ollama/Llama 3.2
- **Parallel processing** across multiple compute nodes
- **Checkpoint recovery** for fault-tolerant long-running jobs

### 🧠 **Advanced AI Integration**
- **Llama 3.2 LLM** for intelligent text analysis and extraction
- **Confidence scoring** with threshold filtering for quality assurance
- **Context-aware parsing** of complex medical and pharmaceutical text
- **Evidence linking** with PMID citations for traceability

### 📊 **Quality Assurance**
- **Multi-method validation** across different extraction approaches
- **MeSH semantic filtering** using medical terminology standards
- **Comprehensive logging** and progress tracking
- **Robust error handling** with graceful failure recovery

## 🔬 Scientific Applications

### Research Use Cases
- **Drug Repositioning**: Identify new therapeutic applications for existing drugs
- **Indication Discovery**: Find evidence for off-label or emerging uses
- **Literature Synthesis**: Aggregate evidence across large publication corpora
- **Comparative Pharmacology**: Analyze therapeutic overlap and distinctions

### Data Science Applications  
- **Knowledge Graph Construction**: Build drug-indication relationship networks
- **Machine Learning**: Train models on comprehensive indication datasets
- **Evidence Ranking**: Score indications by publication support and confidence
- **Cross-Method Validation**: Compare extraction methodologies for reliability

## 📈 Performance Metrics

| Metric | Phase 1 | Phase 2 | Total |
|--------|---------|---------|-------|
| **Drugs Processed** | 2,623 | 2,600+ per method | 10,400+ drug-method combinations |
| **Publications Analyzed** | 5,013,484 | Selected abstracts | Context-optimized |
| **Data Generated** | 18GB | 330MB | Structured JSON |
| **Processing Time** | ~200 CPU hours | ~500 GPU hours | Highly parallelized |
| **Success Rate** | 100% | 99.9%+ | Robust error handling |

## 🛠️ Requirements

### System Requirements
- **Julia** 1.8+ with package environment
- **HPC Environment** with SLURM job scheduling (recommended)
- **GPU Access** for AI extraction (CUDA-compatible)
- **Storage** 20GB+ for full dataset processing
- **Memory** 8GB+ per processing job

### Dependencies
```julia
# Core dependencies (automatically installed)
HTTP.jl      # PubMed API communication
JSON3.jl     # Structured data processing  
Dates.jl     # Timestamp and metadata handling
```

### External Tools
```bash
# HPC environment (for AI extraction)
module load ollama julia
ollama pull llama3.2
```

## 📖 Documentation

- **[Workflow Guide](final_scripts/README.md)**: Complete step-by-step execution
- **[Implementation Details](docs/implementation/)**: Technical architecture and design
- **[Usage Examples](docs/usage/)**: Common use cases and tutorials
- **[CLAUDE.md](CLAUDE.md)**: Development instructions and guidelines

## 🎯 Next Steps (Phase 3)

Phase 3 development is ready to begin with comprehensive analysis and integration:

1. **Cross-Method Validation**: Compare indication extraction across 4 methodologies
2. **Evidence Scoring**: Rank indications by publication support and AI confidence  
3. **Knowledge Integration**: Merge methodologies into unified high-confidence dataset
4. **Quality Metrics**: Develop comprehensive evaluation framework
5. **Research Output**: Generate publication-ready drug-indication database

## 📄 Data Sources & Compliance

- **🏪 DrugBank**: Comprehensive pharmaceutical database (requires free academic account)
- **📚 PubMed**: NCBI's biomedical literature database (public API with rate limiting)
- **🏷️ MeSH**: Medical Subject Headings vocabulary (public domain)
- **🧠 Llama 3.2**: Meta's open-source language model (academic use)

**Usage Compliance**: All data sources are used in accordance with their respective terms of service and academic research policies.

## 📊 Output Data Format

All results follow consistent JSON structure with metadata:
```json
{
  "metadata": {
    "drug_name": "Drug Name",
    "extraction_method": "method_type", 
    "total_indications_found": 0,
    "confidence_threshold": 0.6,
    "extracted_at": "2025-07-24T12:00:00"
  },
  "indications": [
    {
      "indication": "Medical Condition",
      "confidence": 0.85,
      "evidence": true,
      "supporting_pmids": ["12345678"],
      "reasoning": "Evidence description"
    }
  ]
}
```

## 🤝 Contributing

This project uses a clean, organized structure optimized for research collaboration:

1. **Core Workflow**: Use `final_scripts/` for production pipeline execution
2. **Development**: Add utilities to appropriate `scripts/` subdirectories  
3. **Documentation**: Update relevant files in `docs/` directory
4. **Testing**: Add validation scripts to `tests/` directory

## 📜 License

This project is designed for academic research and educational purposes. Please ensure compliance with all data source terms of service and institutional research policies.

---

**🔬 THERA-IE**: Therapeutic Hypothesis Extraction and Relationship Analytics for comprehensive drug-indication analysis with state-of-the-art AI and traditional literature mining approaches.
