# Llama 3.2 Drug-Indication Extraction System

This system analyzes drug files from PubMed publications using Llama 3.2 to extract drug-indication pairings. It's designed as a standalone program that complements the existing drug analysis pipeline.

## Overview

The system processes JSON files containing drug publication data and uses Llama 3.2's natural language processing capabilities to identify therapeutic indications for each drug. Each publication's title, abstract, and MeSH terms are analyzed to extract specific medical conditions or diseases that the drug treats.

## Prerequisites

1. **Julia** (version 1.6 or higher)
2. **Ollama** with Llama 3.2 model
3. **Required Julia packages**: HTTP, JSON3, Dates, Logging

## Installation and Setup

### 1. Setup for HPC Environment with GPU

This system is designed for an HPC environment. Use the automated setup script:

```bash
julia hpc_setup_and_run.jl
```

Or follow the manual steps:

```bash
# Request GPU resources
interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00

# Load Ollama module
module load ollama

# Start Ollama server (in background)
ollama serve &

# Check GPU assignment
myq

# SSH to assigned GPU node (replace XXXX with your GPU number)
ssh gpuXXXX

# Load and test Llama 3.2 model
ollama run llama3.2
```

### 1b. Alternative Local Installation

For local development environments:

```bash
# Install Ollama (visit https://ollama.ai for OS-specific instructions)
# For Linux/macOS:
curl -fsSL https://ollama.ai/install.sh | sh

# Start Ollama service
ollama serve

# Pull Llama 3.2 model
ollama pull llama3.2
```

### 2. Install Julia Dependencies

The setup script will automatically install required packages, or you can install them manually:

```julia
using Pkg
Pkg.add(["HTTP", "JSON3", "Dates", "Logging"])
```

## Usage

### Quick Start (HPC Environment)

For HPC environments with GPU access, use the automated setup script:

```bash
# Full analysis of all drugs
julia hpc_setup_and_run.jl

# Test mode (3 files only)
julia hpc_setup_and_run.jl --test

# Single drug analysis
julia hpc_setup_and_run.jl --drug Acetophenazine

# Check system status
julia hpc_setup_and_run.jl --status

# Show help
julia hpc_setup_and_run.jl --help
```

This script automatically:
- Checks for GPU session and SLURM job
- Loads Ollama module
- Starts Ollama server
- Detects GPU assignment
- Tests Llama 3.2 availability
- Runs the analysis

**Prerequisites for HPC:**
1. Must be in a GPU interactive session: `interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00`
2. Ollama module must be available: `module load ollama`

### Quick Start (Local Environment)

For local development, use the standard setup script:

```bash
julia setup_and_run.jl
```

This provides a menu with options to:
- Check dependencies and setup
- Run full analysis (all drug files)
- Run test analysis (first 5 files)
- Run single drug analysis
- View previous results
- Clean output directory

### Manual Execution

You can also run the extractor directly:

```bash
# Run full analysis
julia llama_drug_indication_extractor.jl

# Run in test mode (first 5 files)
LLAMA_TEST_MODE=true LLAMA_MAX_FILES=5 julia llama_drug_indication_extractor.jl

# Run single drug analysis
LLAMA_SINGLE_DRUG="Acetophenazine" julia llama_drug_indication_extractor.jl
```

## Input Data Format

The system expects JSON files in the `drug_pubmed_refs` directory with the following structure:

```json
{
  "metadata": {
    "drug_name": "DrugName",
    "filename": "DrugName.json"
  },
  "result": {
    "publications_analyzed": [
      {
        "pmid": "12345678",
        "title": "Publication title",
        "abstract": "Publication abstract...",
        "mesh_descriptors": [
          {
            "descriptor": "Disease Name",
            "qualifiers": ["therapy"]
          }
        ]
      }
    ]
  }
}
```

## Output Format

### Individual Drug Results

For each drug, the system creates a JSON file with extracted indications:

```json
{
  "metadata": {
    "drug_name": "DrugName",
    "analysis_time": "2024-01-01T12:00:00",
    "processing_duration_seconds": 45.2,
    "model_used": "llama3.2",
    "total_publications": 25,
    "successful_extractions": 23,
    "failed_extractions": 2,
    "total_indications_extracted": 8
  },
  "extracted_indications": [
    {
      "indication": "Schizophrenia",
      "confidence": 0.95,
      "pmid": "12345678",
      "title": "Publication title",
      "source_text": "Title: ... Abstract: ...",
      "extracted_at": "2024-01-01T12:00:00"
    }
  ]
}
```

### Summary Report

A comprehensive summary is generated as `extraction_summary.json`:

```json
{
  "analysis_summary": {
    "total_drugs_analyzed": 150,
    "total_publications_processed": 3750,
    "total_indications_extracted": 892,
    "average_indications_per_drug": 5.95,
    "analysis_completed_at": "2024-01-01T12:00:00"
  },
  "drug_results": [...],
  "top_indications": [
    {"indication": "Depression", "frequency": 45},
    {"indication": "Anxiety", "frequency": 38}
  ]
}
```

## Configuration

Modify `llama_config.jl` to customize:

- API endpoints and model settings
- Directory paths
- Processing parameters (timeouts, delays)
- Model parameters (temperature, top_p)
- Confidence thresholds

## Key Features

### Intelligent Extraction
- Analyzes publication titles, abstracts, and MeSH terms
- Uses carefully crafted prompts to focus on therapeutic indications
- Filters out side effects and contraindications
- Provides confidence scores for each extraction

### Robust Processing
- Handles API timeouts and retries
- Processes files incrementally with progress tracking
- Graceful error handling and logging
- Configurable delays to respect API rate limits

### Comprehensive Output
- Individual drug analysis files
- Summary statistics and reports
- Top indication frequency analysis
- Processing metadata and timestamps

### Flexible Execution Modes
- Full analysis of all drugs
- Test mode for quick validation
- Single drug analysis for focused work
- Resume capability (skip existing outputs)

## Performance Considerations

- **Processing Time**: Expect ~1-2 minutes per drug (depending on publication count)
- **API Calls**: One call per publication (~30-50 per drug on average)
- **Rate Limiting**: Built-in delays to avoid overwhelming the Ollama API
- **Memory Usage**: Minimal - processes one file at a time

## Troubleshooting

### HPC Environment Issues

1. **GPU resource allocation**
   ```bash
   # Check current job status
   myq
   
   # Request GPU resources if needed
   interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00
   ```

2. **Module loading issues**
   ```bash
   # Load Ollama module
   module load ollama
   
   # Check available modules
   module avail ollama
   ```

3. **SSH connection to GPU node**
   ```bash
   # Check GPU assignment
   myq | grep gpu
   
   # Test SSH connection
   ssh gpuXXXX hostname
   ```

4. **Ollama on GPU node**
   ```bash
   # SSH to GPU node and start Ollama
   ssh gpuXXXX
   ollama serve &
   ollama pull llama3.2
   ```

### Common Issues

1. **Cannot connect to Ollama API**
   ```bash
   # Check if Ollama is running
   curl http://localhost:11434/api/tags
   
   # Start Ollama if needed
   ollama serve
   ```

2. **Llama 3.2 model not found**
   ```bash
   ollama pull llama3.2
   ```

3. **Julia package issues**
   ```julia
   using Pkg
   Pkg.resolve()
   Pkg.instantiate()
   ```

4. **Permission errors**
   - Ensure write permissions to output directory
   - Check file paths in configuration

### Performance Tuning

- Adjust `TEMPERATURE` and `TOP_P` in config for different extraction behavior
- Modify `API_DELAY_SECONDS` to balance speed vs. API stability
- Set `MAX_FILES_TO_PROCESS` for batch processing
- Use `MIN_CONFIDENCE` to filter low-confidence extractions

## Integration with Existing Pipeline

This system is designed to complement, not replace, the existing drug analysis pipeline:

- **Input**: Uses the same JSON files produced by `pubmed_drug_indications.jl`
- **Output**: Creates separate analysis files with Llama-extracted indications
- **Standalone**: Does not modify existing pipeline or data structures
- **Comparative**: Results can be compared with existing DrugBank indications

## Future Enhancements

- Support for other LLM models (GPT, Claude, etc.)
- Batch processing optimizations
- Web interface for results visualization
- Integration with medical ontologies (UMLS, SNOMED)
- Automated result validation and quality scoring
