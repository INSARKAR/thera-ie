# SLURM-Enhanced PubMed Drug Analysis System

This enhanced version of the PubMed drug indications analysis pipeline uses SLURM for robust, large-scale processing on HPC systems. The system automatically handles job submission, monitoring, failure recovery, and result aggregation.

## Overview

The SLURM-enhanced system provides:

1. **Automated Job Management**: Splits drug processing into manageable chunks and submits SLURM jobs
2. **Failure Recovery**: Automatically detects failed jobs and resubmits remaining work
3. **Progress Monitoring**: Real-time monitoring of job status and processing progress
4. **Resource Optimization**: Configurable chunk sizes, time limits, and memory allocation
5. **Resume Capability**: Can resume processing from any point if interrupted

## Architecture

```
run_slurm_pubmed_analysis.sh (Orchestrator)
├── slurm_pubmed_drug_indications.jl (SLURM Manager)
├── pubmed_drug_indications.jl (Core Analysis)
├── SLURM Jobs (Parallel Processing)
│   ├── Chunk 1: Drugs 1-50
│   ├── Chunk 2: Drugs 51-100
│   └── ... (N chunks based on configuration)
└── Result Aggregation
    ├── Individual drug files (phase1_drug_pubmed_refs/)
    ├── Comprehensive summaries
    └── Publication databases
```

## Quick Start

### 1. Prerequisites

Ensure you have the required data files:
```bash
# Generate approved drugs dictionary
julia approved_drugs_extractor.jl

# Generate MeSH disease headings
julia mesh_t047_extractor.jl

# Verify files exist
ls -la approved_drugs_dict.jl mesh_t047_headings.jl
```

### 2. Start Analysis

```bash
# Start with default settings (50 drugs per job, 4-hour time limit)
./run_slurm_pubmed_analysis.sh start

# Start with custom settings
./run_slurm_pubmed_analysis.sh start --chunk-size 100 --time 8 --memory 16

# Start with auto-resume (automatically resubmit failed jobs)
./run_slurm_pubmed_analysis.sh start --auto-resume --max-retries 3
```

### 3. Monitor Progress

```bash
# Check processing status
./run_slurm_pubmed_analysis.sh status

# Monitor SLURM jobs
./run_slurm_pubmed_analysis.sh monitor

# Monitor with automatic resubmission of failed jobs
./run_slurm_pubmed_analysis.sh monitor --auto-resume
```

### 4. Resume if Needed

```bash
# Resume processing for remaining drugs
./run_slurm_pubmed_analysis.sh resume

# Resume with auto-monitoring
./run_slurm_pubmed_analysis.sh resume --auto-resume
```

### 5. Generate Final Summary

```bash
# Generate comprehensive summary after all jobs complete
./run_slurm_pubmed_analysis.sh summary
```

## Configuration Options

### Resource Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `--chunk-size` | 50 | Number of drugs processed per SLURM job |
| `--time` | 4 | SLURM job time limit (hours) |
| `--memory` | 8 | Memory allocation per job (GB) |
| `--partition` | batch | SLURM partition to use |
| `--account` | - | SLURM account (if required) |

### Processing Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `--auto-resume` | false | Automatically resubmit failed jobs |
| `--max-retries` | 3 | Maximum retry attempts for failed jobs |

### Recommended Configurations

#### Small Dataset (< 1000 drugs)
```bash
./run_slurm_pubmed_analysis.sh start --chunk-size 25 --time 2 --memory 4
```

#### Medium Dataset (1000-5000 drugs)
```bash
./run_slurm_pubmed_analysis.sh start --chunk-size 50 --time 4 --memory 8
```

#### Large Dataset (> 5000 drugs)
```bash
./run_slurm_pubmed_analysis.sh start --chunk-size 100 --time 8 --memory 16
```

#### High-Throughput with Auto-Recovery
```bash
./run_slurm_pubmed_analysis.sh start --chunk-size 75 --time 6 --memory 12 --auto-resume --max-retries 5
```

## File Structure

After running the analysis, you'll have:

### Input Files
```
approved_drugs_dict.jl          # Drug dictionary
mesh_t047_headings.jl          # MeSH disease terms
```

### Core Scripts
```
pubmed_drug_indications.jl             # Original analysis program
slurm_pubmed_drug_indications.jl       # SLURM-enhanced version
run_slurm_pubmed_analysis.sh          # Orchestration script
```

### SLURM Management
```
slurm_scripts/                 # Generated SLURM batch scripts
├── pubmed_chunk_1.sh
├── pubmed_chunk_2.sh
└── ...

slurm_outputs/                 # SLURM job outputs
├── pubmed_chunk_1_12345.out
├── pubmed_chunk_1_12345.err
└── ...

slurm_job_tracking.json       # Job tracking information
slurm_orchestrator_logs/      # Orchestrator logs
```

### Results
```
phase1_drug_pubmed_refs/             # Individual drug analysis files
├── Aspirin.json
├── Acetaminophen.json
└── ... (one file per drug)

drug_disease_associations.json        # Comprehensive results
drug_disease_associations.txt         # Human-readable summary
drug_disease_publications.json       # Detailed publication data
drug_disease_publications_index.txt  # Publication index
```

## Monitoring and Troubleshooting

### Check Job Status

```bash
# Via orchestrator
./run_slurm_pubmed_analysis.sh status

# Via SLURM commands
squeue -u $USER
sacct -u $USER --starttime=today
```

### View Job Outputs

```bash
# Check SLURM outputs
ls -la slurm_outputs/

# View specific job output
tail -f slurm_outputs/pubmed_chunk_1_12345.out

# Check for errors
grep -r "ERROR\|Failed\|Exception" slurm_outputs/
```

### Monitor Progress

```bash
# Check how many drugs have been processed
ls phase1_drug_pubmed_refs/*.json | wc -l

# View orchestrator logs
tail -f slurm_orchestrator_logs/orchestrator_*.log

# Real-time processing status
watch -n 30 './run_slurm_pubmed_analysis.sh status'
```

### Handle Failed Jobs

```bash
# Check for failed jobs
sacct -u $USER --state=FAILED --starttime=today

# Resubmit remaining work
./run_slurm_pubmed_analysis.sh resume

# Auto-monitor and resubmit
./run_slurm_pubmed_analysis.sh monitor --auto-resume
```

## Advanced Usage

### Manual SLURM Job Management

```bash
# Submit jobs manually
julia slurm_pubmed_drug_indications.jl --submit-remaining --chunk-size 75

# Monitor manually
julia slurm_pubmed_drug_indications.jl --monitor

# Check status manually
julia slurm_pubmed_drug_indications.jl --status
```

### Custom SLURM Configuration

Create a custom script with specific SLURM directives:

```bash
# Edit the generated SLURM scripts before submission
ls slurm_scripts/pubmed_chunk_*.sh

# Add custom SLURM directives
#SBATCH --constraint=highmem
#SBATCH --exclusive
#SBATCH --qos=high
```

### Cleanup and Maintenance

```bash
# Clean up old job files
./run_slurm_pubmed_analysis.sh cleanup

# Remove failed job outputs
rm slurm_outputs/*_FAILED_*

# Archive completed work
tar -czf pubmed_analysis_$(date +%Y%m%d).tar.gz phase1_drug_pubmed_refs/ *.json *.txt
```

## Performance Tuning

### Optimal Chunk Sizes

- **Small chunks (25-50 drugs)**: Better fault tolerance, more overhead
- **Large chunks (100-200 drugs)**: Less overhead, longer recovery time if failed
- **Balanced (50-75 drugs)**: Good balance of throughput and reliability

### Memory Requirements

- **Basic analysis**: 4-8 GB per job
- **Large datasets**: 8-16 GB per job
- **Memory-intensive**: 16-32 GB per job

### Time Limits

- **Conservative**: 2-4 hours per chunk
- **Standard**: 4-8 hours per chunk
- **Extended**: 8-12 hours per chunk

## Expected Runtime

For the complete FDA approved drug dataset (~1000-2000 drugs):

| Configuration | Jobs | Time per Job | Total Wall Time | Parallel Time |
|---------------|------|--------------|-----------------|---------------|
| 50 drugs/job, 4h | 20-40 | 2-4 hours | 40-160 hours | 4-8 hours |
| 100 drugs/job, 8h | 10-20 | 4-8 hours | 40-160 hours | 8-16 hours |
| 25 drugs/job, 2h | 40-80 | 1-2 hours | 40-160 hours | 2-4 hours |

*Parallel time assumes sufficient SLURM resources for concurrent execution*

## Output Analysis

### Individual Drug Files

Each drug produces a JSON file with:
- Drug name and FDA indication
- PubMed search results
- Publication details (PMID, title, abstract)
- MeSH disease associations
- Processing metadata

### Comprehensive Summaries

- **drug_disease_associations.json**: Complete results with metadata
- **drug_disease_associations.txt**: Human-readable summary
- **drug_disease_publications.json**: Detailed publication database

### Quality Metrics

The system tracks:
- Successful PubMed searches
- Publications analyzed
- Disease associations found
- Processing time per drug
- Error rates and failure modes

## Troubleshooting

### Common Issues

1. **SLURM submission failures**: Check partition availability and resource limits
2. **Out of memory errors**: Increase `--memory` parameter
3. **Time limit exceeded**: Increase `--time` parameter or reduce `--chunk-size`
4. **Network timeouts**: Enable auto-resume for automatic recovery

### Error Recovery

The system automatically handles:
- Network timeouts during PubMed API calls
- Temporary SLURM system issues
- Individual job failures
- Partial result corruption

### Support

For issues or questions:
1. Check SLURM job outputs in `slurm_outputs/`
2. Review orchestrator logs in `slurm_orchestrator_logs/`
3. Use `--status` to check processing progress
4. Use `--monitor` to track job execution

## Integration with Existing Workflow

This SLURM system seamlessly integrates with your existing drug analysis workflow:

1. **Llama Extraction**: Run this first for broad drug-indication analysis
2. **PubMed Analysis**: Use this SLURM system for comprehensive literature mining
3. **Data Integration**: Combine results for complete drug-indication profiles

The systems share compatible data formats and can be run independently or in sequence.
