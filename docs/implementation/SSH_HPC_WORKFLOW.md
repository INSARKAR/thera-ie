# SSH-Based HPC Workflow for Llama Drug Indication Extraction

## O/users/isarkar/sarkarcode/thera/
├── hpc_setup_and_run.jl              # Main HPC orchestration script
├── run_complete_hpc_analysis.sh      # Complete workflow wrapper
├── llama_drug_indication_extractor.jl # Core analysis logic
├── test_ssh_setup.jl                 # SSH connectivity test
├── drug_pubmed_refs/                 # Input data directory
└── llama_pubmed_extracted_indications/      # Output results directory

The HPC setup now includes full SSH automation to run the Llama analysis on allocated GPU nodes. The system automatically:

1. **Detects Environment**: Determines if you're on a login node or GPU node
2. **GPU Allocation**: Finds your allocated GPU node from SLURM
3. **SSH Setup**: Establishes and tests SSH connection to the GPU node
4. **Remote Execution**: Copies analysis scripts to GPU node and runs them
5. **Result Retrieval**: Copies results back to the login node
6. **Cleanup**: Removes temporary files from GPU node

## Quick Start

### Option 1: Complete Automated Workflow (Recommended)

```bash
# For testing (3 files only)
./run_complete_hpc_analysis.sh --test

# For single drug analysis
./run_complete_hpc_analysis.sh --drug Aspirin

# For full analysis (all drugs)
./run_complete_hpc_analysis.sh
```

### Option 2: Manual Session Management

```bash
# 1. Request GPU resources
interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00

# 2. Once in GPU session, run analysis
julia hpc_setup_and_run.jl --test    # Test mode
julia hpc_setup_and_run.jl --drug Aspirin  # Single drug
julia hpc_setup_and_run.jl           # Full analysis
```

## How SSH Automation Works

### 1. Environment Detection
- Checks if running in SLURM job (`$SLURM_JOB_ID`)
- Determines hostname to detect login vs GPU node
- Uses `myq` command to find allocated GPU node

### 2. SSH Connection Setup
- Tests SSH connectivity with timeout
- Verifies Julia and Ollama availability on GPU node
- Sets up environment variables for remote execution

### 3. Remote Analysis Execution
- Creates unique working directory on GPU node: `/tmp/thera_analysis_$SLURM_JOB_ID`
- Copies analysis scripts and data via `scp`
- Starts Ollama server on GPU node remotely
- Executes Julia analysis script on GPU node
- Monitors execution and captures output

### 4. Result Retrieval
- Copies extracted results back to login node
- Preserves directory structure
- Cleans up temporary files on GPU node

## File Structure

```
/users/isarkar/sarkarcode/thera/
├── hpc_setup_and_run.jl              # Main HPC orchestration script
├── run_complete_hpc_analysis.sh      # Complete workflow wrapper
├── llama_drug_indication_extractor.jl # Core analysis logic
├── test_ssh_setup.jl                 # SSH connectivity test
├── drug_pubmed_refs/                 # Input data directory
└── drug_llama_indications/           # Output results directory
```

## Command Reference

### Testing Commands
```bash
# Test SSH setup only
julia test_ssh_setup.jl

# Check system status
julia hpc_setup_and_run.jl --status

# Test analysis with 3 files
julia hpc_setup_and_run.jl --test
```

### Production Commands
```bash
# Full analysis of all drugs
julia hpc_setup_and_run.jl

# Single drug analysis
julia hpc_setup_and_run.jl --drug "Drug Name"
```

## Environment Variables

The system automatically sets these variables for SSH execution:

- `LLAMA_GPU_NODE`: Hostname of allocated GPU node
- `LLAMA_TEST_MODE`: "true" if running in test mode
- `LLAMA_MAX_FILES`: Number of files to process in test mode
- `LLAMA_SINGLE_DRUG`: Drug name for single-drug analysis

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH manually
ssh gpu001 hostname

# Check SSH keys
ls -la ~/.ssh/

# Test with verbose output
ssh -v gpu001 hostname
```

### GPU Allocation Issues
```bash
# Check current jobs
myq

# Check available GPU nodes
sinfo -p gpu

# Request interactive session manually
interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00
```

### Ollama Issues on GPU Node
```bash
# SSH to GPU node and test manually
ssh gpu001
module load ollama
ollama serve &
ollama list
```

## Output Files

Results are saved in `llama_pubmed_extracted_indications/` with the following structure:

```
llama_pubmed_extracted_indications/
├── DrugName1_llama_extracted.json
├── DrugName2_llama_extracted.json
├── analysis_summary.json
└── processing_log.txt
```

Each output file contains:
- Drug name and metadata
- Extracted drug-indication pairs
- Confidence scores
- Processing timestamps
- Model information (Llama 3.2)

## Performance Notes

- **Test Mode**: Processes 3 files (~2-3 minutes)
- **Single Drug**: Processes 1 drug file (~1-2 minutes) 
- **Full Analysis**: Processes all drug files (~30-60 minutes depending on data size)
- **SSH Overhead**: Minimal (~5-10 seconds for setup and file transfer)

## Next Steps

1. **Run Test**: Start with `./run_complete_hpc_analysis.sh --test`
2. **Verify Results**: Check `drug_llama_indications/` directory
3. **Production Run**: Execute full analysis when ready
4. **Monitor Progress**: Use `julia hpc_setup_and_run.jl --status` to check system state
