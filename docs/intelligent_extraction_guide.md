# Intelligent Drug-Disease Extraction Guide

This guide explains how to use the new intelligent drug-disease extraction system, which efficiently identifies and verifies drug indications by processing the minimum necessary publications.

## How It Works

The intelligent extraction system works in two phases:

1. **Identification Phase**:
   - Analyzes a subset of publications to identify all potential drug-disease pairs
   - Uses Llama 3.2 to extract disease mentions from titles and abstracts
   - Creates a list of unique diseases to verify

2. **Verification Phase**:
   - For each identified disease, processes publications until finding sufficient evidence
   - Stops processing once a disease is confirmed as an indication (with high confidence)
   - Only processes enough publications to make a determination, not all publications

This approach is more efficient than processing all publications for all drugs, especially for well-documented indications where evidence is abundant.

## Running the Extraction

### Local Test Run

Before running on SLURM, you can test locally with:

```bash
# Make sure Ollama is running locally
cd /users/isarkar/sarkarcode/thera
module load ollama
ollama serve &
sleep 10
ollama pull llama3.2

# Run test script
julia scripts/extraction/test_intelligent_extractor.jl
```

### SLURM Execution

There are several ways to run the extraction on SLURM:

1. **Single Drug Extraction**:
   ```bash
   # From the project root directory
   sbatch scripts/extraction/intelligent_extraction.slurm Levothyroxine
   ```

2. **Multiple Drug Extraction**:
   ```bash
   # Multiple drugs as command-line arguments
   scripts/extraction/submit_intelligent_extractions.sh Levothyroxine Ibuprofen Metformin
   ```

3. **Batch Extraction from File**:
   ```bash
   # Create a file with one drug name per line
   echo "Levothyroxine" > drug_list.txt
   echo "Ibuprofen" >> drug_list.txt
   echo "Metformin" >> drug_list.txt
   
   # Submit jobs for all drugs in the file
   scripts/extraction/submit_intelligent_extractions.sh --list drug_list.txt
   ```

## Monitoring Extraction Jobs

You can monitor the extraction jobs using standard SLURM commands:

```bash
# View all your running jobs
squeue -u $USER

# Check output logs in real-time
tail -f /users/isarkar/sarkarcode/thera/logs/intelligent_extraction_*.out

# Check for any errors
tail -f /users/isarkar/sarkarcode/thera/logs/intelligent_extraction_*.err
```

## Results

Extraction results are saved in the `/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/` directory with filenames like `{DrugName}_intelligent_extraction.json`.

Each result file contains:

1. **Metadata**: Overall statistics about the extraction
2. **Disease Pairs**: List of all disease pairs with their verification status
3. **Evidence**: Publications that support each drug-disease relationship

## Performance Considerations

- **Processing Time**: The intelligent extractor is typically faster than processing all publications
- **Memory Usage**: The extractor uses minimal memory as it processes publications one at a time
- **GPU Requirements**: Requires GPU access for efficient Llama 3.2 inference
- **Checkpointing**: Currently does not implement checkpointing, but this could be added

## Troubleshooting

If you encounter issues:

1. **Ollama Connection Issues**:
   ```bash
   # Check if Ollama is running
   curl -s http://localhost:11434/api/tags
   
   # Restart Ollama if needed
   pkill ollama
   ollama serve &
   ```

2. **Missing Publications**:
   Ensure the drug publication files exist at `/users/isarkar/sarkarcode/thera/drug_pubmed_refs/{DrugName}.json`

3. **SLURM Job Failures**:
   Check the job logs in `/users/isarkar/sarkarcode/thera/logs/` for specific error messages
