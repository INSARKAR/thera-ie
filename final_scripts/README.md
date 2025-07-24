# Final Scripts Documentation

This directory contains the final, working versions of scripts organized by project phase and execution order.

## 📁 Directory Organization

```
final_scripts/
├── phase0/          # Foundation Setup (12 files)
│   ├── step1_*.jl   # DrugBank extraction
│   ├── step2_*.jl   # MeSH processing  
│   ├── step3_*.jl   # Environment validation
│   ├── step4_*.jl   # Dependency validation
│   ├── step5_*.jl   # Auto-detection setup
│   ├── step6_*.jl   # Local setup
│   ├── step7_*.jl   # HPC setup
│   ├── step8_*.jl   # LLM configuration
│   └── step9_*.sh   # SLURM runner
│
├── phase1/          # Data Extraction (12 files)
│   ├── step1_*.jl   # PubMed extraction
│   ├── step2_*.jl   # Empty results identification
│   ├── step3_*.jl   # Targeted reprocessing
│   ├── step4_*.jl   # Comprehensive validation
│   └── step5_*.jl   # MeSH filtering
│
├── phase2/          # AI Processing (14 files)
│   ├── step1_*.jl   # DrugBank AI extraction
│   ├── step2_*.jl   # MeSH indication extraction
│   ├── step3_*.jl   # Naive AI extraction
│   └── step4_*.jl   # PubMed AI extraction
│
└── README.md        # This documentation
```

**📝 Usage Note**: All scripts are now organized in phase subdirectories. When running scripts, use the full path (e.g., `julia phase0/phase0_step5_environment_setup.jl`).

## Phase 0: Foundational Data Preparation

**Objective**: Generate all foundational data dependencies required for Phase 1 PubMed extraction.

**Status**: ✅ **COMPLETED** - All dependency files generated

### Complete Phase 0 Workflow Overview:
1. **Data Dependencies**: DrugBank extraction, MeSH semantic processing
2. **Environment Setup**: Auto-detection, local/HPC configuration  
3. **Validation**: Dependency and setup verification
4. **Runtime Configuration**: LLM and SLURM integration

### Step 1: DrugBank Approved Drugs Extraction

**Files**:
- `phase0/phase0_step1_drugbank_extractor.jl` - DrugBank XML processor
- `phase0/phase0_step1_submit_drugbank_extraction.sh` - Extraction submission script

**Purpose**: 
- Processes DrugBank XML files to extract only approved drugs
- Filters out investigational, experimental, and withdrawn drugs
- Cleans indication text and removes duplicates
- Performs quality filtering for meaningful pharmaceutical data

**Usage**:
```bash
# Submit DrugBank extraction
./phase0/phase0_step1_submit_drugbank_extraction.sh

# Manual execution with specific XML file
julia phase0/phase0_step1_drugbank_extractor.jl /path/to/drugbank.xml
```

**Dependencies**: DrugBank XML file (place in `_data/drugbank/full_database.xml`)
**Output**: 2,915 approved drugs in `generated_dependency_files/approved_drugs_dict.jl`

---

### Step 2: MeSH Semantic Type Extraction  

**Files**:
- `phase0_step2_mesh_semantic_extractor.jl` - MeSH descriptor processor
- `phase0_step2_submit_mesh_extraction.sh` - Extraction submission script

**Purpose**:
- Parses MeSH descriptor files (d2025.bin) to extract medical semantic types
- Includes 15+ medical semantic types (T047, T191, T048, T184, etc.)
- Generates comprehensive medical headings set for semantic filtering
- Provides both Julia and plain text output formats

**Usage**:
```bash
# Submit MeSH extraction
./phase0_step2_submit_mesh_extraction.sh

# Manual execution
julia phase0_step2_mesh_semantic_extractor.jl
```

**Dependencies**: MeSH d2025.bin file (place in `_data/mesh/d2025.bin`)
**Output**: 5,895 medical MeSH descriptors in `generated_dependency_files/mesh_semantic_headings.jl`

---

### Step 3: Environment Setup and Validation

**Files**:
- `phase0_step3_validate_setup.jl` - Local environment validation
- `phase0_step3_validate_hpc_setup.jl` - HPC environment validation

**Purpose**:
- Validates Julia environment and required packages
- Tests API connectivity (PubMed E-utilities)
- Verifies directory structure and file permissions
- Checks HPC-specific requirements (SLURM, modules)

**Usage**:
```bash
# Local environment validation
julia phase0_step3_validate_setup.jl

# HPC environment validation (on SLURM systems)
julia phase0_step3_validate_hpc_setup.jl
```

**Dependencies**: System environment
**Output**: Environment validation reports

---

### Step 4: Dependency File Validation

**Files**:
- `phase0_step4_validate_dependencies.jl` - Generated files validation

**Purpose**:
- Validates all generated dependency files are complete and well-formatted
- Checks data quality statistics and completeness
- Verifies Phase 1 readiness and required function availability
- Generates comprehensive dependency summary report

**Usage**:
```bash
julia phase0_step4_validate_dependencies.jl
```

**Dependencies**: All generated files from Steps 1-2
**Output**: Comprehensive Phase 1 readiness validation report

---

## Phase 1: PubMed Extraction

**Objective**: Extract comprehensive publication data and MeSH descriptors for all approved drugs from PubMed.

**Status**: ✅ **COMPLETED** - 100% success rate (2,623/2,623 processable drugs)

### Step 1: Main Extraction

**Files**:
- `phase1_step1_main_extraction_worker.jl` - Core extraction worker
- `phase1_step1_main_extraction.slurm` - SLURM job array script  
- `phase1_step1_submit_main_extraction.sh` - Job submission script

**Purpose**: 
- Performs comprehensive PubMed searches for all approved drugs
- Retrieves unlimited publications per drug (no artificial limits)
- Extracts titles, abstracts, PMIDs, and complete MeSH descriptors
- Uses conservative API rate limiting for reliability
- Processes drugs in parallel across multiple SLURM jobs

**Usage**:
```bash
# Submit main extraction jobs
./phase1_step1_submit_main_extraction.sh

# Monitor progress  
squeue -u $USER
ls phase1_drug_pubmed_refs/*.json | wc -l
```

**Output**: JSON files in `phase1_drug_pubmed_refs/` directory, one per drug.

---

### Step 2: Quality Validation

**Files**:
- `phase1_step2_identify_empty_results.jl` - Validation and issue detection

**Purpose**:
- Validates all extracted JSON files for completeness
- Identifies drugs with empty `publications_analyzed` arrays despite having `total_publications_found > 0`
- Generates lists of problematic drugs for targeted reprocessing
- Provides dataset statistics and quality metrics

**Usage**:
```bash
julia phase1_step2_identify_empty_results.jl
```

**Output**: 
- Console report of validation results
- `empty_results_drugs.txt` - List of drugs needing reprocessing

---

### Step 3: Targeted Reprocessing  

**Files**:
- `phase1_step3_targeted_reprocessing_worker.jl` - Specialized reprocessing worker
- `phase1_step3_targeted_reprocessing.slurm` - SLURM script for reprocessing
- `phase1_step3_submit_targeted_reprocessing.sh` - Submission script

**Purpose**:
- Reprocesses only drugs identified as having incomplete results
- Uses more aggressive rate limiting and smaller batch sizes for reliability
- Overwrites existing incomplete files with complete data
- Preserves all existing valid data

**Usage**:
```bash
# Submit targeted reprocessing (only after Step 2 identifies issues)
./phase1_step3_submit_targeted_reprocessing.sh

# Monitor progress
squeue -u $USER
julia phase1_step2_identify_empty_results.jl  # Check remaining issues
```

**Output**: Updated JSON files for previously incomplete drugs.

---

### Step 4: Comprehensive Validation

**Files**:
- `phase1_step4_comprehensive_validation.jl` - Final dataset validation

**Purpose**:
- Performs comprehensive quality assessment of entire dataset
- Validates JSON structure, publication counts, and MeSH descriptor coverage
- Generates detailed statistics and completion metrics
- Identifies any remaining data quality issues

**Usage**:
```bash
julia phase1_step4_comprehensive_validation.jl
```

**Output**: Comprehensive dataset quality report with statistics.

---

### Step 5: MeSH Filtering and Reorganization

**Files**:
- `phase1_step5_mesh_filtering_worker.jl` - MeSH filtering and reorganization worker
- `phase1_step5_mesh_filtering.slurm` - SLURM job array script  
- `submit_phase1_step5_mesh_filtering.sh` - Job submission script

**Purpose**:
- Applies semantic filtering to keep only publications with relevant medical MeSH descriptors
- Applies frequency filtering to keep MeSH terms appearing in >1% of drug's publications
- Organizes publications by MeSH descriptor categories (allowing PMID redundancy)
- Handles edge cases (≤5 publications after semantic filtering by keeping all)
- Processes 2,623 drug files across 8 parallel SLURM jobs

**Usage**:
```bash
# Submit MeSH filtering jobs
./submit_phase1_step5_mesh_filtering.sh

# Monitor progress  
squeue -u $USER
ls phase1_drug_pubmed_mesh/*.json | wc -l
```

**Output**: Filtered and organized JSON files in `phase1_drug_pubmed_mesh/` directory, one per drug.

**Dependencies**: Requires `../generated_dependency_files/mesh_semantic_headings.jl`

---

## Phase 2: Indication Extraction

**Objective**: Extract drug-indication pairings using multiple methodologies to create comprehensive indication datasets.

**Status**: ✅ **COMPLETED** - Both AI-powered and MeSH-based extraction completed

### Step 1: DrugBank Llama Extraction

**Files**:
- `phase2_step1_drugbank_llama_coordinator.jl` - Dual-GPU coordinator script
- `phase2_step1_drugbank_llama_extractor.jl` - Individual drug processing worker  
- `phase2_step1_drugbank_llama_extraction.slurm` - SLURM job script
- `submit_phase2_step1_drugbank_llama_extraction.sh` - Job submission script

**Purpose**:
- Extracts therapeutic indications from DrugBank XML indication text using Llama 3.2 AI model
- Uses dual-GPU SLURM architecture for maximum parallel processing efficiency
- Processes approved drugs with AI-powered text analysis and structured extraction
- Generates confidence-scored JSON output with normalized medical conditions

**Key Features**:
- **Dual-GPU parallel processing** for maximum efficiency
- **AI-powered text analysis** using Llama 3.2 with pharmaceutical knowledge
- **Confidence scoring** with 0.6 threshold for confirmed indications
- **Resume capability** - automatically skips already processed drugs
- **Filename sanitization** - handles spaces and special characters properly
- **Structured output** with condition names, confidence scores, and reasoning

**Processing Logic**:
1. Load approved drugs from generated dependency files
2. Check existing output files for resume capability
3. Start Ollama servers on both allocated GPUs
4. Split remaining drugs between GPUs for parallel processing
5. Process each drug's indication text with Llama 3.2
6. Extract and normalize medical conditions with confidence assessment
7. Apply confidence threshold filtering and save structured results

**Usage**:
```bash
# Submit DrugBank Llama extraction
./submit_phase2_step1_drugbank_llama_extraction.sh

# Monitor progress
squeue -u $USER
ls phase2_indications_llama_drugbank/*.json | wc -l

# View logs
tail -f logs/phase2_drugbank_llama_*.out
```

**Input**: Approved drugs dictionary with DrugBank indication text
**Output**: JSON files with AI-extracted indications in `phase2_indications_llama_drugbank/` directory
**Results**: 2,909 drugs processed (99.8% coverage of approved drugs)
**Dependencies**: Requires `../generated_dependency_files/approved_drugs_dict.jl`

---

### Step 2: MeSH-Based Indication Extraction

**Files**:
- `phase2_step2_mesh_indication_extractor.jl` - MeSH indication extraction worker
- `phase2_step2_mesh_indication_extraction.slurm` - SLURM job array script
- `submit_phase2_step2_mesh_indication_extraction.sh` - Job submission script

**Purpose**:
- Extracts unique MeSH descriptors as drug indications from Phase 1 filtered publications
- Processes MeSH-organized publication data to identify evidence-based indication patterns
- Counts supporting publications and maintains PMID evidence for validation
- Creates literature-based indication datasets complementary to AI extraction approaches

**Key Features**:
- **Evidence-based extraction** from peer-reviewed literature analysis
- **Publication counting** for indication strength and reliability assessment
- **PMID tracking** for complete evidence validation and traceability
- **Parallel batch processing** across 8 SLURM jobs (~330 files per job)
- **Resume capability** with intelligent filename matching for interrupted runs
- **Literature foundation** using Phase 1's comprehensive PubMed extraction

**Processing Logic**:
1. Load Phase 1 MeSH-organized publication data for each drug
2. Extract unique MeSH descriptor keys as potential indications
3. Count supporting publications per MeSH descriptor for evidence strength
4. Collect PMIDs for complete evidence tracking and validation
5. Sort indications by publication support strength and frequency
6. Generate structured indication files with evidence metadata

**Usage**:
```bash
# Submit MeSH indication extraction
./submit_phase2_step2_mesh_indication_extraction.sh

# Monitor progress
squeue -j [JOB_ARRAY_ID]
ls phase2_indications_mesh/*.json | wc -l

# View logs
tail -f logs/phase2_mesh_indications_*_1.out
```

**Input**: Phase 1 MeSH-organized publication files from `phase1_drug_pubmed_mesh/`
**Output**: JSON files with MeSH-based indications in `phase2_indications_mesh/` directory
**Results**: 2,623 drugs processed (100% of Phase 1 filtered drugs)
**Dependencies**: Requires Phase 1 Step 5 completion (`phase1_drug_pubmed_mesh/` files)

---

## Workflow Summary

### Standard Execution Order:

**Phase 0 - Foundational Setup:**
1. **Step 1**: Extract approved drugs from DrugBank XML
2. **Step 2**: Extract medical MeSH descriptors from MeSH data
3. **Step 3**: Validate environment setup and connectivity
4. **Step 4**: Validate all generated dependency files

**Phase 1 - PubMed Extraction:**
1. **Step 1**: Run main extraction for all drugs
2. **Step 2**: Validate results and identify incomplete extractions  
3. **Step 3**: Reprocess incomplete drugs (if any identified)
4. **Step 4**: Final validation and statistics
5. **Step 5**: MeSH filtering and reorganization

**Phase 2 - Indication Extraction:**
1. **Step 1**: DrugBank Llama extraction using AI-powered analysis
2. **Step 2**: MeSH-based indication extraction from filtered publications

### Key Features:
- **Fault tolerant**: Each step can be run independently
- **Resumable**: Existing valid data is preserved
- **Scalable**: Parallel processing with SLURM job arrays
- **Quality assured**: Multiple validation checkpoints
- **API compliant**: Conservative rate limiting throughout

### Final Results:

**Phase 0 Outputs:**
- **2,915 approved drugs** extracted from DrugBank with valid indications
- **5,895 medical MeSH descriptors** extracted across 15+ semantic types
- **Complete dependency files** generated in Julia, JSON, and CSV formats
- **Environment validation** passed for both local and HPC environments

**Phase 1 Outputs:**
- **2,623 drugs** with complete PubMed data (processable subset)
- **5,013,484 publications** extracted and analyzed
- **54,180,820 MeSH descriptors** captured from publications
- **100% completion rate** for processable drugs
- **0% data corruption** - all files validated  
- **2,623 MeSH-filtered files** organized by medical descriptor categories

### Step 3: Naive Llama Extraction

**Files**:
- `phase2_step3_naive_llama_extractor.jl` - Knowledge-based extraction worker
- `phase2_step3_naive_llama_extraction.slurm` - SLURM job array script
- `submit_phase2_step3_naive_llama_extraction.sh` - Job submission script

**Purpose**:
- Extracts drug indications using Llama 3.2's pre-trained pharmaceutical knowledge without external data
- Provides knowledge-based indication extraction independent of literature or databases
- Creates baseline indication datasets using AI model's trained medical knowledge
- Offers rapid indication assessment without requiring external data processing

**Key Features**:
- **Knowledge-based approach** using LLM's pre-trained pharmaceutical data
- **Single-query efficiency** per drug with no external data dependencies
- **Structured evidence-confidence-reasoning format** for transparent assessment
- **Batch processing** with 30 parallel jobs (100 drugs per job)
- **Conservative resource usage** with intelligent queue management
- **Zero external dependencies** - works purely from model knowledge

**Processing Logic**:
1. Load approved drugs from dependency files
2. Check existing results for efficient resume capability
3. Format naive prompt template with drug name substitution
4. Query Llama 3.2 for known therapeutic indications from training data
5. Parse structured response format (Evidence/Confidence/Reasoning triplets)
6. Apply confidence threshold filtering (≥0.6) for reliable indications
7. Save structured results with complete reasoning chains

**Usage**:
```bash
# Submit naive llama extraction
./submit_phase2_step3_naive_llama_extraction.sh

# Monitor progress
squeue -u $USER
ls phase2_indications_llama_naive/*.json | wc -l

# View logs
tail -f logs/phase2_step3_naive_llama_*_1.out
```

**Input**: Approved drugs list for knowledge-based querying
**Output**: JSON files with knowledge-based indications in `phase2_indications_llama_naive/` directory
**Results**: 2,932 drugs processed (100.5% coverage including drug variants)
**Dependencies**: Requires `../generated_dependency_files/approved_drugs_dict.jl` and `prompts/llm_prompt_naive.txt`

---

### Step 4: MeSH-Guided PubMed Analysis with Llama 3.2

**Files**:
- `phase2_step4_pubmed_llama_extractor.jl` - MeSH-guided literature analysis worker
- `phase2_step4_single_gpu_batch.slurm` - SLURM batch processing script
- `submit_phase2_step4_single_gpu.sh` - Job submission and management script
- `phase2_step4_monitor_zero_indications.jl` - Debugging and monitoring script

**Purpose**:
- Combines MeSH-guided literature analysis with AI-powered extraction using Llama 3.2
- Processes research abstracts from PubMed to identify specific therapeutic indications
- Extracts supporting PMIDs for evidence traceability and validation
- Provides the most comprehensive and evidence-based indication extraction approach

**Key Features**:
- **Evidence-based extraction** with supporting PMIDs from research literature
- **MeSH-guided analysis** using up to 5 abstracts per MeSH descriptor
- **Single API call efficiency** - combines all abstracts per drug in one prompt
- **Robust parsing** - handles multiple LLM response formats (`Indication 1:` and `1.`)
- **Confidence scoring** with 0.6 threshold for confirmed therapeutic indications
- **Clean output format** with simplified MeSH summaries
- **Enhanced error handling** - gracefully handles edge cases and parsing variations
- **Debugging capabilities** - monitoring script to classify and analyze zero-indication results

**Processing Logic**:
1. Load Phase 1 MeSH-organized publication data for each drug
2. Select up to 5 abstracts per MeSH descriptor for focused analysis
3. Combine all abstracts from all MeSH descriptors into single prompt
4. Query Llama 3.2 for therapeutic indications with PMID evidence
5. Parse structured response extracting indication names, confidence, PMIDs, and reasoning
6. Apply confidence threshold filtering and generate clean JSON output

**Usage**:
```bash
# Submit all MeSH-guided PubMed analysis jobs
./submit_phase2_step4_single_gpu.sh

# Monitor progress
squeue -u $USER
watch 'ls phase2_indications_llama_pubmed/ | wc -l'

# View logs
tail -f logs/phase2_pubmed_batch_*_1.out

# Check specific results
cat phase2_indications_llama_pubmed/Artemether_pubmed_llama_indications.json

# Monitor and debug zero indication results
julia phase2_step4_monitor_zero_indications.jl
```

**Output Format**:
```json
{
  "metadata": {
    "drug_name": "Artemether",
    "total_indications_found": 3,
    "confirmed_indications": 3,
    "total_publications_analyzed": 467,
    "model_used": "llama3.2",
    "approach": "mesh_guided_pubmed_llama"
  },
  "indications": [
    {
      "indication": "Malaria",
      "confidence": 0.9,
      "evidence": true,
      "confirmed": true,
      "supporting_pmids": ["25877884", "11592502"],
      "publication_count": 2,
      "reasoning": "Evidence of effectiveness in treating malaria"
    }
  ],
  "mesh_analysis_summary": [
    {
      "mesh_descriptor": "243 MeSH descriptors analyzed",
      "indications_extracted": ["Malaria", "Schistosomiasis"],
      "max_confidence": 0.9,
      "publications_analyzed": 467
    }
  ]
}
```

**Performance Characteristics**:
- **Resource Efficient**: 1 GPU, 8GB RAM, 1 CPU per job
- **Batch Processing**: 10 drugs per job, 263 total jobs
- **Processing Time**: ~8-12 seconds per drug average
- **Concurrent Execution**: ~10-20 jobs running simultaneously
- **Total Estimated Time**: ~52 hours for all 2,623 drugs

**Input**: Phase 1 MeSH-organized publication files from `phase1_drug_pubmed_mesh/`
**Output**: JSON files with evidence-based indications in `phase2_indications_llama_pubmed/` directory
**Results**: 2,623 drugs processed (100% of Phase 1 filtered drugs)
**Dependencies**: Requires Phase 1 Step 5 completion and `prompts/llm_prompt_pubmed.txt`

---

**Phase 2 Outputs:**
- **AI-extracted indications** from DrugBank data using Llama 3.2 analysis (2,909 drugs in `phase2_indications_llama_drugbank/`)
- **MeSH-based indications** extracted from PubMed publications (2,623 drugs in `phase2_indications_mesh/`)
- **Knowledge-based indications** from Llama 3.2 pre-trained knowledge (2,932 drugs in `phase2_indications_llama_naive/`)
- **Evidence-based indications** from MeSH-guided PubMed analysis with PMID support (2,623 drugs in `phase2_indications_llama_pubmed/`)
- **Quad-methodology approach** enabling comprehensive indication coverage, cross-validation, methodology comparison, and evidence traceability

---

## Generated Dependency Files

Scripts in this directory depend on generated files stored in the `../generated_dependency_files/` directory:

**Generated by Phase 0:**
- **`approved_drugs_dict.jl`** - Dictionary of 2,915 approved drugs with indication text (used by Phase 1 Step 1)
- **`approved_drugs_dict.json`** - JSON format version for external tools
- **`approved_drugs_list.csv`** - CSV format for data analysis
- **`mesh_semantic_headings.jl`** - Set of 5,895 medical MeSH descriptors for semantic filtering (used by Phase 1 Step 5)
- **`mesh_semantic_headings.txt`** - Plain text list for manual review

**Phase 0 → Phase 1 Data Flow:**
```
DrugBank XML → Phase 0 Step 1 → approved_drugs_dict.jl
MeSH d2025.bin → Phase 0 Step 2 → mesh_semantic_headings.jl
                            ↓
Phase 1 scripts load these dependency files for PubMed extraction
```

These files contain curated, validated data that forms the foundation of the entire extraction pipeline.

---

## File Naming Convention

Scripts follow the pattern: `phase{X}_step{Y}_{description}.{ext}`
- `X` = Phase number (1, 2, 3, etc.)
- `Y` = Step number within phase (1, 2, 3, etc.)  
- `description` = Brief functional description
- `ext` = File extension (.jl, .slurm, .sh, .md)

This ensures scripts are:
- **Chronologically ordered** by phase and step
- **Functionally descriptive** 
- **Easy to locate** and understand
- **Version controlled** as final working implementations
### Step 5: Environment Auto-Detection Setup

**Files**:
- `phase0_step5_environment_setup.jl` - Auto-detects local vs HPC environment

**Purpose**: 
- Automatically detects execution environment (local vs HPC/SLURM)
- Routes to appropriate setup scripts
- Provides unified entry point for different environments

**Usage**:
```bash
# Auto-detection and setup
julia phase0_step5_environment_setup.jl
```

**Dependencies**: System environment detection
**Output**: Executes appropriate setup workflow

---

### Step 6: Local Environment Setup

**Files**:
- `phase0_step6_local_setup.jl` - Local development environment setup

**Purpose**: 
- Sets up local development environment
- Validates Julia dependencies and packages
- Configures local data paths and processing

**Usage**:
```bash
# Local setup and execution
julia phase0_step6_local_setup.jl
```

**Dependencies**: Local Julia environment
**Output**: Configured local processing environment

---

### Step 7: HPC Environment Setup

**Files**:
- `phase0_step7_hpc_setup.jl` - HPC/SLURM environment setup

**Purpose**: 
- Sets up HPC/SLURM processing environment
- Configures GPU resources and job scheduling
- Validates Ollama and model availability

**Usage**:
```bash
# HPC setup and execution
julia phase0_step7_hpc_setup.jl
```

**Dependencies**: SLURM system, GPU resources
**Output**: Configured HPC processing environment

---

### Step 8: LLM Configuration

**Files**:
- `phase0_step8_llama_config.jl` - Llama model configuration

**Purpose**: 
- Defines LLM model parameters and endpoints
- Configures Ollama server settings
- Sets processing parameters for AI extraction

**Usage**:
```julia
# Include in other scripts
include("phase0_step8_llama_config.jl")
```

**Dependencies**: Ollama installation
**Output**: LLM configuration constants

---

### Step 9: SLURM Job Runner

**Files**:
- `phase0_step9_slurm_runner.sh` - Unified SLURM job submission

**Purpose**: 
- Provides unified interface for SLURM job submission
- Handles batch processing coordination
- Manages GPU resource allocation

**Usage**:
```bash
# Submit processing jobs
./phase0_step9_slurm_runner.sh [job_type] [parameters]
```

**Dependencies**: SLURM system, configured environment
**Output**: Submitted batch processing jobs

