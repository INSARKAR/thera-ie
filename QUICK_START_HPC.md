# Non-Interactive HPC Usage Guide

## Quick Reference

### From within a GPU session:
```bash
# Check if you're in a GPU session
echo $SLURM_JOB_ID

# Load Ollama and run full analysis
module load ollama
julia hpc_setup_and_run.jl

# Test mode (3 files)
julia hpc_setup_and_run.jl --test

# Single drug
julia hpc_setup_and_run.jl --drug Acetophenazine

# Check status
julia hpc_setup_and_run.jl --status
```

### Automatic GPU request (if not in session):
```bash
# This handles GPU request automatically
./run_with_gpu.sh

# With options
./run_with_gpu.sh --test
./run_with_gpu.sh --drug Acetophenazine
```

## Manual Steps (if needed)

1. **Request GPU resources:**
   ```bash
   interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00
   ```

2. **Load Ollama module:**
   ```bash
   module load ollama
   ```

3. **Run analysis:**
   ```bash
   julia hpc_setup_and_run.jl
   ```

## Command Options

- `julia hpc_setup_and_run.jl` - Full analysis (all drugs)
- `julia hpc_setup_and_run.jl --test` - Test mode (3 files)
- `julia hpc_setup_and_run.jl --drug DrugName` - Single drug analysis
- `julia hpc_setup_and_run.jl --status` - Check system status only
- `julia hpc_setup_and_run.jl --help` - Show help

## What the script does automatically:

1. ✅ Checks for GPU session (SLURM_JOB_ID)
2. ✅ Loads Ollama module
3. ✅ Starts Ollama server
4. ✅ Detects GPU node assignment
5. ✅ Sets up SSH connection to GPU
6. ✅ Tests Llama 3.2 model availability
7. ✅ Runs drug indication extraction
8. ✅ Saves results and generates summary

## Expected Output Structure

```
llama_extracted_indications/
├── Acetophenazine_llama_extracted.json
├── Clopidogrel_llama_extracted.json
├── ...
└── extraction_summary.json
```

## Troubleshooting

- **Not in GPU session**: Use `./run_with_gpu.sh` or manually request GPU
- **Ollama module not found**: Check `module avail ollama`
- **SSH issues**: Check GPU node assignment with `myq`
- **Model not found**: Script will automatically download llama3.2
