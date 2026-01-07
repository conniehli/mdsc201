#!/bin/bash
#SBATCH --job-name=nanopore_meta
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

#######################################
# User-configurable parameters
#######################################
test
FASTQ=""
SAMPLE_NAME=""
OUTDIR="results"
THREADS=$SLURM_CPUS_PER_TASK

# Kraken2 options
BUILD_DB=false
DB_DIR=""
DB_NAME="kraken2_db"
KRAKEN_LIBS="bacteria viral"

#######################################
# Usage
#######################################

usage() {
  echo "Usage:"
  echo "  sbatch $0 -i reads.fastq.gz -s sample_name [-o outdir] [--build-db] [--db path]"
  echo
  echo "Required:"
  echo "  -i FILE        Input Nanopore FASTQ (.fastq or .fastq.gz)"
  echo "  -s NAME        Sample name (used in output files)"
  echo
  echo "Optional:"
  echo "  -o DIR         Output directory (default: results)"
  echo "  --build-db     Build a Kraken2 database"
  echo "  --db DIR       Use an existing Kraken2 database"
  exit 1
}

#######################################
# Parse arguments
#######################################

while [[ $# -gt 0 ]]; do
  case $1 in
    -i) FASTQ="$2"; shift 2 ;;
    -s) SAMPLE_NAME="$2"; shift 2 ;;
    -o) OUTDIR="$2"; shift 2 ;;
    --build-db) BUILD_DB=true; shift ;;
    --db) DB_DIR="$2"; shift 2 ;;
    *) usage ;;
  esac
done

#######################################
# Input checks
#######################################

if [[ -z "$FASTQ" || -z "$SAMPLE_NAME" ]]; then
  echo "ERROR: FASTQ file and sample name are required."
  usage
fi
mkdir -p "$OUTDIR" logs

#######################################
# Activate Conda environment
#######################################

CONDA_BASE="/work/TALC/mdsc201_2026w/miniconda3"
if [[ ! -f "$CONDA_BASE/etc/profile.d/conda.sh" ]]; then
  echo "ERROR: Shared Conda installation not found at $CONDA_BASE"
  exit 1
fi
source "$CONDA_BASE/etc/profile.d/conda.sh"
conda activate mdsc201_np_kraken
echo "Activated Conda environment (shared): mdsc201_np_kraken"

#######################################
# Step 1: QC with NanoQC
#######################################

echo "Running NanoQC for sample: $SAMPLE_NAME"

QC_DIR="$OUTDIR/nanoqc/$SAMPLE_NAME"
mkdir -p "$QC_DIR"

nanoQC "$FASTQ" -o "$QC_DIR"

#######################################
# Step 2: Build Kraken2 database (optional)
#######################################

if [[ "$BUILD_DB" == true ]]; then
  echo "Building Kraken2 database..."
  DB_DIR="$OUTDIR/$DB_NAME"
  mkdir -p "$DB_DIR"
  kraken2-build --download-taxonomy --db "$DB_DIR"
  for lib in $KRAKEN_LIBS; do
    kraken2-build --download-library "$lib" --db "$DB_DIR"
  done
  kraken2-build --build --threads "$THREADS" --db "$DB_DIR"
fi

# Validate Kraken2 database

if [[ -z "$DB_DIR" ]]; then
  echo "ERROR: No Kraken2 database specified."
  exit 1
fi
if [[ ! -f "$DB_DIR/hash.k2d" ]]; then
  echo "ERROR: Kraken2 database not found or not built."
  exit 1
fi

#######################################
# Step 3: Kraken2 classification
#######################################

echo "Running Kraken2 classification..."

K2_OUTDIR="$OUTDIR/kraken2"
mkdir -p "$K2_OUTDIR"

k2 classify \
  --db "$DB_DIR" \
  --threads "$THREADS" \
  --report "$K2_OUTDIR/${SAMPLE_NAME}_kraken2_report.txt" \
  --output "$K2_OUTDIR/${SAMPLE_NAME}_kraken2_classifications.txt" \
  "$FASTQ"

echo "Pipeline complete."
