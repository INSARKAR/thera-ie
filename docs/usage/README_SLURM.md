# Llama Drug Indication Extractor - SLURM Integration

This system uses Llama 3.2 via Ollama to extract drug-indication pairings from PubMed publications on the Oscar HPC cluster.

## Quick Start

1. **Submit a test job** (processes 2 publications):
   ```bash
   ./submit_llama_job.sh -t
   ```

2. **Monitor the job**:
   ```bash
   ./monitor_llama_jobs.sh -s    # Check status
   ./monitor_llama_jobs.sh -l JOB_ID    # Live logs
   ```

3. **Check results**:
   ```bash
   ./monitor_llama_jobs.sh -r
   ```

## Usage Examples

### Test Mode (Quick validation)
```bash
# Test with Levothyroxine (default)
./submit_llama_job.sh -t

# Test with another drug
./submit_llama_job.sh -t Aspirin
```

### Full Extraction
```bash
# Full extraction for Levothyroxine
./submit_llama_job.sh -f Levothyroxine

# Full extraction for other drugs
./submit_llama_job.sh -f Metformin
./submit_llama_job.sh Aspirin    # -f is implied
```

### Monitoring Jobs
```bash
# Show job status
./monitor_llama_jobs.sh -s

# Follow live logs for specific job
./monitor_llama_jobs.sh -l 12345

# Show results summary
./monitor_llama_jobs.sh -r

# Show everything for a job
./monitor_llama_jobs.sh -a 12345
```

## File Structure

```
/users/isarkar/sarkarcode/thera/
├── llama_extraction.slurm              # Main SLURM job script
├── submit_llama_job.sh                 # Job submission helper
├── monitor_llama_jobs.sh               # Job monitoring helper
├── llama_drug_indication_extractor.jl  # Main extractor
├── quick_test_levothyroxine.jl         # Quick test script
├── phase1_drug_pubmed_refs/                   # Input drug files
├── llama_pubmed_extracted_indications/ # Output results
└── logs/                               # SLURM job logs
```

## SLURM Job Details

- **Partition**: gpu
- **Resources**: 1 GPU, 4 CPUs, 32GB RAM
- **Time limit**: 2 hours
- **Queue**: norm-gpu

## Output Files

### Test Mode
- `llama_pubmed_extracted_indications/levothyroxine_quick_test.json`

### Full Mode
- `llama_pubmed_extracted_indications/DRUGNAME_llama_extracted.json`
- `llama_pubmed_extracted_indications/extraction_summary.json` (if multiple drugs)

## Troubleshooting

### Common Issues

1. **Job fails immediately**:
   ```bash
   # Check error logs
   tail logs/llama_extraction_JOBID.err
   ```

2. **Drug not found**:
   ```bash
   # List available drugs
   ls phase1_drug_pubmed_refs/ | head -20
   ```

3. **Ollama connection issues**:
   - The job script automatically handles Ollama setup
   - Check logs for "Ollama server is ready" message

4. **No results generated**:
   - Check if publications have abstracts/titles
   - Verify Llama model responses in logs
   - Try test mode first to validate setup

### Manual Debugging

If needed, you can run components manually:

```bash
# Request interactive GPU session
interact -n 4 -m 32g -q gpu -g 1 -t 1:00:00

# SSH to assigned GPU node
ssh gpuXXXX

# Load modules and start Ollama
module load ollama
ollama serve &
sleep 10
ollama run llama3.2

# Run test
cd /users/isarkar/sarkarcode/thera
julia --project=. quick_test_levothyroxine.jl
```

## Environment Variables

The SLURM script supports these environment variables:

- `LLAMA_SINGLE_DRUG`: Drug name to process (default: Levothyroxine)
- `LLAMA_TEST_MODE`: true/false for test mode (default: false)
- `LLAMA_MAX_FILES`: Max files in test mode (default: 5)

## Performance Notes

- **Test mode**: ~2-5 minutes (2 publications)
- **Full mode**: ~30-120 minutes depending on publication count
- **Rate limiting**: 1-2 second delays between API calls
- **Memory usage**: ~2-8GB depending on model and data size

## Results Format

Each result file contains:
- `metadata`: Processing statistics and configuration
- `extracted_indications`: Array of indication objects with:
  - `indication`: Medical condition/disease name
  - `confidence`: Model confidence (0.0-1.0)
  - `pmid`: PubMed ID
  - `title`: Publication title
  - `source_text`: Title + abstract
  - `extracted_at`: Timestamp
