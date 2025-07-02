#!/bin/bash

# Monitor fresh Levothyroxine extraction job

JOB_ID="11922456"
LOG_FILE="/users/isarkar/sarkarcode/thera/logs/fresh_extraction_${JOB_ID}.out"
OUTPUT_FILE="/users/isarkar/sarkarcode/thera/llama_pubmed_extracted_indications/Levothyroxine_fresh_extraction.json"

echo "=== Monitoring Fresh Levothyroxine Extraction ==="
echo "Job ID: $JOB_ID"
echo "Time: $(date)"

# Check job status
echo ""
echo "Job Status:"
squeue -j $JOB_ID 2>/dev/null || echo "Job not in queue (may have completed)"

# Check recent progress from log
echo ""
echo "Recent Progress (last 10 lines):"
if [ -f "$LOG_FILE" ]; then
    tail -10 "$LOG_FILE" | grep -E "(Processing publication|✓ Extracted|Progress:|===)" || echo "No progress messages found"
else
    echo "Log file not found: $LOG_FILE"
fi

# Count API calls as a progress indicator
echo ""
echo "API Activity:"
if [ -f "$LOG_FILE" ]; then
    api_calls=$(grep -c "POST.*api/generate" "$LOG_FILE" 2>/dev/null || echo "0")
    echo "Total API calls made: $api_calls"
    echo "Estimated publications processed: $api_calls/5847 ($(echo "scale=1; $api_calls*100/5847" | bc -l)%)"
else
    echo "Cannot count API calls - log file not found"
fi

# Check if output file exists
echo ""
echo "Output Status:"
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Output file exists: $OUTPUT_FILE"
    echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    echo "Last modified: $(stat -c %y "$OUTPUT_FILE")"
else
    echo "⏳ Output file not yet created: $OUTPUT_FILE"
fi

echo ""
echo "To continue monitoring:"
echo "  watch -n 30 'bash scripts/monitoring/monitor_fresh_extraction.sh'"
echo "  tail -f $LOG_FILE"
