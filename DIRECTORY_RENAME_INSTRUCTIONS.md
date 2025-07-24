# Directory Rename Instructions

## Current Status:
✅ All hardcoded paths in scripts have been updated from `thera` to `thera-ie`
✅ 103 path references successfully updated in .jl, .sh, and .slurm files
✅ Current changes committed to git

## Required Steps to Complete Rename:

### Step 1: Exit this directory and rename
```bash
# Exit the current session/directory
cd /users/isarkar/sarkarcode

# Rename the directory
mv thera thera-ie

# Enter the renamed directory
cd thera-ie
```

### Step 2: Update git remote (if needed)
```bash
# Check current remote
git remote -v

# If the remote references "thera", you may want to update the repository name on GitHub
# Go to https://github.com/INSARKAR/thera/settings and rename to "thera-ie"
# Then update the remote:
# git remote set-url origin https://github.com/INSARKAR/thera-ie.git
```

### Step 3: Verify everything works
```bash
# Test a script to ensure paths work
julia final_scripts/phase0/phase0_step5_environment_setup.jl

# Check git status
git status
```

## What Was Updated:
- All `.jl` Julia script files
- All `.sh` shell script files  
- All `.slurm` batch job files
- Total: 103 path references updated

## Files that now expect thera-ie directory:
- All final_scripts/ phase0, phase1, phase2 scripts
- All scripts/ extraction and analysis scripts
- All SLURM job files

The rename must be completed for the scripts to function properly since they now reference the `thera-ie` path.