#!/bin/bash
#SBATCH --job-name=add_hierarchy
#SBATCH --partition=batch
#SBATCH --time=2:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --output=logs/add_hierarchy_%j.out
#SBATCH --error=logs/add_hierarchy_%j.err

# Load Julia module
module load julia

echo "🌳 Adding Hierarchy to UMLS Database"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Start time: $(date)"

# Navigate to project directory
cd /oscar/home/isarkar/sarkarcode/thera

# Run hierarchy addition with parallel processing
echo "📚 Adding hierarchy with $(nproc) CPUs..."
julia -t 8 scripts/analysis/add_hierarchy_to_database.jl

echo "✅ Hierarchy addition completed at $(date)"

# Show final database info
if [ -f "/oscar/data/ursa/umls/2025AA/umls_medical.db" ]; then
    echo "📊 Final database size: $(du -h /oscar/data/ursa/umls/2025AA/umls_medical.db)"
else
    echo "❌ Database file not found"
fi