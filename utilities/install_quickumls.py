#!/usr/bin/env python3

"""
Clean installation script for QuickUMLS
This will install QuickUMLS and its dependencies in a clean environment
"""

import subprocess
import sys
import os
import tempfile

def run_command(cmd, description=""):
    """Run a command and handle errors"""
    print(f"\n{'='*60}")
    print(f"Running: {description}")
    print(f"Command: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    print(f"{'='*60}")
    
    try:
        result = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, check=True)
        if result.stdout:
            print("STDOUT:")
            print(result.stdout)
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
        print(f"✓ {description} completed successfully")
        return result
    except subprocess.CalledProcessError as e:
        print(f"✗ {description} failed with exit code {e.returncode}")
        if e.stdout:
            print("STDOUT:")
            print(e.stdout)
        if e.stderr:
            print("STDERR:")
            print(e.stderr)
        return None

def main():
    print("=== QuickUMLS Clean Installation ===")
    print(f"Python version: {sys.version}")
    print(f"Python executable: {sys.executable}")
    print(f"Working directory: {os.getcwd()}")
    
    # Create a virtual environment for clean installation
    venv_path = "/oscar/home/isarkar/sarkarcode/thera-ie/quickumls_venv"
    
    print(f"\n1. Creating virtual environment at: {venv_path}")
    if os.path.exists(venv_path):
        print("Removing existing virtual environment...")
        run_command(f"rm -rf {venv_path}", "Remove existing venv")
    
    result = run_command([sys.executable, "-m", "venv", venv_path], "Create virtual environment")
    if not result:
        print("Failed to create virtual environment")
        return False
    
    # Paths for the virtual environment
    venv_python = f"{venv_path}/bin/python"
    venv_pip = f"{venv_path}/bin/pip"
    
    print(f"\n2. Upgrading pip in virtual environment")
    result = run_command([venv_pip, "install", "--upgrade", "pip"], "Upgrade pip")
    if not result:
        print("Failed to upgrade pip")
        return False
    
    print(f"\n3. Installing required dependencies")
    dependencies = [
        "wheel",
        "setuptools",
        "numpy", 
        "scipy",
        "scikit-learn",
        "nltk",
        "spacy",
        "unidecode",
        "leveldb"  # Important for QuickUMLS
    ]
    
    for dep in dependencies:
        result = run_command([venv_pip, "install", dep], f"Install {dep}")
        if not result:
            print(f"Warning: Failed to install {dep}, continuing...")
    
    print(f"\n4. Installing QuickUMLS")
    result = run_command([venv_pip, "install", "quickumls"], "Install QuickUMLS")
    if not result:
        print("Failed to install QuickUMLS")
        return False
    
    print(f"\n5. Testing QuickUMLS import")
    test_script = f"""
import sys
sys.path.insert(0, '{venv_path}/lib/python3.11/site-packages')

try:
    from quickumls import QuickUMLS
    print("✓ QuickUMLS imported successfully")
    
    # Try basic functionality test
    print("✓ QuickUMLS installation appears successful")
    
except ImportError as e:
    print(f"✗ QuickUMLS import failed: {{e}}")
    sys.exit(1)
except Exception as e:
    print(f"✗ QuickUMLS test failed: {{e}}")
    sys.exit(1)
"""
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(test_script)
        test_file = f.name
    
    try:
        result = run_command([venv_python, test_file], "Test QuickUMLS import")
        if result:
            print("\n" + "="*60)
            print("✓ QuickUMLS installation completed successfully!")
            print(f"Virtual environment: {venv_path}")
            print(f"Python executable: {venv_python}")
            print(f"To use: source {venv_path}/bin/activate")
            print("="*60)
            return True
        else:
            print("✗ QuickUMLS installation test failed")
            return False
    finally:
        os.unlink(test_file)

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)