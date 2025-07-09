#!/bin/bash
#SBATCH --job-name=umls_database_build
#SBATCH --partition=batch
#SBATCH --time=6:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --output=logs/umls_database_build_%j.out
#SBATCH --error=logs/umls_database_build_%j.err

# Load Julia module
module load julia

echo "🏗️  Starting UMLS SQLite Database Build"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Start time: $(date)"

# Navigate to project directory
cd /oscar/home/isarkar/sarkarcode/thera

# Run database builder
echo "📚 Building UMLS SQLite database..."
julia scripts/analysis/build_umls_sqlite.jl

echo "✅ UMLS database build completed at $(date)"

# Show database size
if [ -f "/oscar/data/ursa/umls/2025AA/umls_medical.db" ]; then
    echo "📊 Final database size: $(du -h /oscar/data/ursa/umls/2025AA/umls_medical.db)"
else
    echo "❌ Database file not found"
fi