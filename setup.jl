#!/usr/bin/env julia

"""
Setup script for DrugBank XML Parser

This script installs the required Julia packages for the DrugBank parser.
"""

using Pkg

println("Setting up DrugBank XML Parser...")
println("=================================")

# Activate the project environment
Pkg.activate(".")

# Install required packages
required_packages = ["EzXML", "DataFrames", "CSV", "JSON", "URIs"]

println("Installing required packages:")
for package in required_packages
    println("  - $package")
end

try
    Pkg.add(required_packages)
    println("\n✓ All packages installed successfully!")
    
    # Test imports
    println("\nTesting package imports...")
    using EzXML
    using DataFrames
    using CSV
    using JSON
    using URIs
    println("✓ All packages imported successfully!")
    
    println("\nSetup completed! You can now run the parser with:")
    println("  julia drugbank_parser.jl")
    println("\nOr try the example with:")
    println("  julia example_usage.jl")
    
catch e
    println("\n✗ Error during setup: $e")
    println("Please try installing the packages manually:")
    println("  julia -e 'using Pkg; Pkg.add([\"EzXML\", \"DataFrames\", \"CSV\", \"JSON\"])'")
    exit(1)
end
