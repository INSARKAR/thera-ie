# Biomedical Data Extraction Pipeline

A comprehensive Julia pipeline for extracting and analyzing biomedical data from DrugBank and PubMed databases with disease association analysis.

## Overview

This pipeline extracts approved drugs from DrugBank, searches PubMed for related publications, and analyzes disease associations using MeSH (Medical Subject Headings) classifications. It provides a complete workflow from drug data extraction to disease association discovery.

## Pipeline Components

### 1. Drug Data Extraction
- **`approved_drugs_extractor.jl`** - Extracts approved drugs from DrugBank XML with full extraction functionality
- **`pubmed_query_generator.jl`** - Generates intelligent PubMed search queries

### 2. Publication Search  
- **`pubmed_drug_search.jl`** - Searches PubMed for drug-related publications using Entrez API

### 3. Disease Classification
- **`mesh_t047_extractor.jl`** - Extracts MeSH T047 disease classifications from MeSH descriptor files

### 4. Disease Association Analysis
- **`pubmed_disease_analyzer.jl`** - Analyzes drug-disease associations through MeSH descriptor matching

## Features

- **Complete XML Parsing**: Parse DrugBank XML files efficiently with EzXML.jl
- **Quality Filtering**: Extract only approved drugs with meaningful indications  
- **Automated PubMed Search**: Intelligent query generation and publication retrieval
- **Disease Classification**: Semantic type T047 (diseases/syndromes) extraction
- **Association Analysis**: Maps drugs to disease conditions via MeSH descriptors
- **Multiple Formats**: JSON, CSV, and Julia-native outputs
- **Progress Tracking**: Real-time progress reporting for large datasets
- **Error Handling**: Robust error recovery and validation

## Requirements

### System Requirements
- Julia 1.6+
- Internet connection for PubMed API access
- Sufficient memory for large XML files (DrugBank ~1GB uncompressed)

### Julia Packages
```julia
using Pkg
Pkg.add([
    "EzXML",        # XML parsing
    "HTTP",         # PubMed API requests  
    "JSON3",        # JSON processing
    "CSV",          # CSV file handling
    "DataFrames",   # Data manipulation
    "Dates"         # Timestamp handling
])
```

### Required Data Files
- **DrugBank XML**: Full database export (requires free DrugBank account)
  - Download from: https://go.drugbank.com/releases/latest
  - File: `drugbank_full_database.xml` (~1GB)
- **MeSH Descriptor File**: Annual MeSH vocabulary release
  - Download from: https://www.nlm.nih.gov/mesh/filelist.html  
  - File: `d2025.bin` (binary format, ~100MB)

## Data Sources

- **DrugBank**: Comprehensive drug database with 14,000+ entries
- **PubMed**: NCBI's biomedical literature database (30+ million citations)
- **MeSH**: Medical Subject Headings vocabulary (28,000+ terms)

## Pipeline Architecture

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   DrugBank XML      │    │   MeSH Descriptors  │    │   PubMed Database   │
│   (Drug Data)       │    │   (Disease Terms)   │    │   (Publications)    │
└──────────┬──────────┘    └──────────┬──────────┘    └──────────┬──────────┘
           │                          │                          │
           ▼                          ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ approved_drugs_     │    │ mesh_t047_          │    │ pubmed_drug_        │
│ extractor.jl        │    │ extractor.jl        │    │ search.jl           │
└──────────┬──────────┘    └──────────┬──────────┘    └──────────┬──────────┘
           │                          │                          │
           ▼                          ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ Approved Drugs      │    │ Disease             │    │ Publication         │
│ Dictionary          │    │ Classifications     │    │ Results             │
│ (2,915 drugs)       │    │ (3,197 diseases)    │    │ (PMIDs + metadata)  │
└──────────┬──────────┘    └──────────┬──────────┘    └──────────┬──────────┘
           │                          │                          │
           └──────────┬───────────────┴──────────────────────────┘
                      ▼
           ┌─────────────────────┐
           │ pubmed_disease_     │
           │ analyzer.jl         │
           └──────────┬──────────┘
                      ▼
           ┌─────────────────────┐
           │ Drug-Disease        │
           │ Associations        │
           │ (Evidence-based)    │
           └─────────────────────┘
```

- Julia 1.6 or higher
- Required packages:
  - EzXML.jl (for XML parsing)
  - DataFrames.jl (for data manipulation)
  - CSV.jl (for CSV export)
  - JSON.jl (for JSON output)
  - Dates.jl (for timestamps)
  - URIs.jl (for URL encoding)

## Installation

1. Clone or download this repository
2. Navigate to the project directory
3. Install the required packages:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Alternatively, you can install the packages manually:

```julia
using Pkg
Pkg.add(["EzXML", "DataFrames", "CSV", "JSON", "URIs"])
```

## Usage

### Basic Usage

To parse the DrugBank XML file with default settings:

```julia
julia drugbank_parser.jl
```

This will:
- Parse the XML file located at `../_data/drugbank/drugbank-20250628.xml`
- Generate a CSV file with all extracted drug information
- Display basic statistics about the parsed data

### Using the Parser as a Module

You can also use the parser programmatically:

```julia
include("drugbank_parser.jl")

# Parse the XML file
drugs = parse_drugbank_xml("path/to/your/drugbank.xml")

# Convert to DataFrame
df = drugs_to_dataframe(drugs)

# Export to CSV
export_to_csv(drugs, "output.csv")

# Analyze the data
analyze_drugs(drugs)
```

### Running the Example

To test the parser with sample data:

```julia
julia example_usage.jl
```

This will create a small sample XML file and demonstrate the parsing functionality.

### Extracting Approved Drugs Dictionary

To extract only approved drugs and create a dictionary mapping drug names to indications:

```julia
julia approved_drugs_extractor.jl
```

This will:
- Extract only drugs marked as "approved" from the DrugBank XML
- **Filter out drugs without valid indication data** (empty, "Not Available", etc.)
- Create a dictionary with drug names as keys and indications as values
- Generate three output files:
  - `approved_drugs_dict.jl` (Julia dictionary file)
  - `approved_drugs_dict.json` (JSON format)
  - `approved_drugs_list.csv` (CSV format)
- **Provide extraction statistics and stop**

**Note**: The program focuses on extraction only. It provides essential statistics about the extracted data and generates the output files without additional analysis or interactive features.

Only drugs with meaningful indication data are included. Drugs with empty indications or generic placeholders like "Not Available" are automatically excluded.

You can then use the dictionary in other Julia programs:

```julia
include("approved_drugs_dict.jl")
indication = APPROVED_DRUGS_DICT["Aspirin"]
println(indication)
```

### Generating PubMed Search Queries

To generate comprehensive PubMed search queries for all approved drugs:

```julia
julia pubmed_query_generator.jl
```

This will:
- Read the approved drugs dictionary (generated by `approved_drugs_extractor.jl`)
- Generate 5 types of search queries for each drug:
  - **Basic drug search** (MeSH terms and all fields)
  - **Drug + indication search** (combines drug name with indication keywords)
  - **Clinical trials search** (focuses on clinical trial publications)
  - **Mechanism of action search** (targets pharmacology and mechanism studies)
  - **Safety/adverse effects search** (finds safety and toxicity studies)
- Generate three output files:
  - `pubmed_queries.txt` (formatted, human-readable queries)
  - `pubmed_queries.json` (structured JSON data)
  - `pubmed_urls.txt` (direct clickable PubMed URLs)

**Output Statistics**:
- Processes 2,915+ approved drugs
- Generates 14,575+ total search queries
- Creates direct URLs for immediate PubMed searching
- Extracts and analyzes indication keywords

You can copy the queries from the text file or click the URLs to go directly to PubMed searches.

## Quick Start

### Prerequisites
```julia
using Pkg
Pkg.add(["HTTP", "JSON3", "CSV", "DataFrames", "EzXML"])
```

### Complete Pipeline Execution

#### Step 1: Extract Approved Drugs
```bash
# Show existing dataset info
julia approved_drugs_extractor.jl

# Extract from DrugBank XML (requires DrugBank account and XML file)
julia approved_drugs_extractor.jl drugbank_full_database.xml

# Show help for extraction options
julia approved_drugs_extractor.jl --help
```

#### Step 2: Generate PubMed Queries  
```bash
julia pubmed_query_generator.jl
```

#### Step 3: Search PubMed for Publications
```bash
julia pubmed_drug_search.jl
```

#### Step 4: Extract Disease Classifications
```bash
# Extract MeSH T047 diseases from MeSH descriptor file
julia mesh_t047_extractor.jl d2025.bin
```

#### Step 5: Analyze Disease Associations
```bash
julia pubmed_disease_analyzer.jl
```

## Pipeline Output Files

### Drug Data (Step 1)
- `approved_drugs_dict.jl` - Julia dictionary format
- `approved_drugs_dict.json` - JSON format  
- `approved_drugs_list.csv` - CSV format

### PubMed Queries (Step 2)
- `pubmed_queries.json` - Generated search queries with URLs

### Publication Results (Step 3)
- `pubmed_search_results.json` - Raw search results with PMIDs
- `pubmed_search_results.txt` - Human-readable summary

### Disease Classifications (Step 4)
- `mesh_t047_headings.jl` - Julia Set of T047 diseases (3,197 diseases)
- `mesh_t047_headings.txt` - Plain text disease list

### Disease Associations (Step 5)
- `drug_disease_associations.json` - Detailed associations with PMIDs
- `drug_disease_associations.txt` - Human-readable summary

## Example Results

```
Drug-Disease Association Analysis
Generated on: 2025-06-30T09:32:25.976
Total drugs analyzed: 10
==================================================

DRUG-DISEASE ASSOCIATIONS
=========================

1. Abacavir
   FDA Indication: Abacavir is indicated in combination with other anti-retroviral agents...
   Publications found: 2532
   Publications analyzed: 6
   Disease associations found: 5

   Associated diseases (MeSH T047):
   - HIV Infections (4 publications)
     Example: [18536095] Abacavir hypersensitivity.
   - Drug Hypersensitivity (2 publications)
     Example: [18536095] Abacavir hypersensitivity.
   - Cardiovascular Diseases (1 publications)
     Example: [27260856] Abacavir and cardiovascular disease: A critical look...

OVERALL STATISTICS:
--------------------
Total publications analyzed: 77
Total unique disease associations: 25
Average disease associations per drug: 2.5
```

## Data Structure

The parser extracts the following information for each drug:

| Field | Description |
|-------|-------------|
| drugbank_id | Primary DrugBank identifier |
| name | Drug name |
| description | Drug description |
| cas_number | Chemical Abstracts Service number |
| unii | Unique Ingredient Identifier |
| state | Physical state (solid, liquid, gas) |
| groups | Drug groups (approved, experimental, etc.) |
| categories | Therapeutic categories |
| indication | Medical indications |
| pharmacodynamics | Pharmacodynamic properties |
| mechanism_of_action | Mechanism of action |
| toxicity | Toxicity information |
| metabolism | Metabolism details |
| absorption | Absorption properties |
| half_life | Half-life information |
| protein_binding | Protein binding data |
| route_of_elimination | Elimination route |
| volume_of_distribution | Volume of distribution |
| clearance | Clearance rate |

## File Structure

```
├── drugbank_parser.jl          # Main parser module
├── approved_drugs_extractor.jl  # Approved drugs dictionary creator
├── pubmed_query_generator.jl    # PubMed search query generator
├── example_usage.jl            # Example usage script
├── example_dictionary_usage.jl # Dictionary usage examples
├── analysis_utils.jl           # Additional analysis utilities
├── Project.toml               # Julia project dependencies
├── README.md                  # This file
├── drugbank_drugs.csv         # Output CSV file (generated)
├── approved_drugs_dict.jl     # Approved drugs dictionary (generated)
├── approved_drugs_dict.json   # Approved drugs JSON (generated)
├── approved_drugs_list.csv    # Approved drugs CSV (generated)
├── pubmed_queries.txt         # PubMed search queries (generated)
├── pubmed_queries.json        # PubMed queries JSON (generated)
└── pubmed_urls.txt            # Direct PubMed URLs (generated)
```

## Configuration

You can modify the file paths in the `main()` function of `drugbank_parser.jl`:

```julia
xml_file_path = "../_data/drugbank/drugbank-20250628.xml"  # Input XML file
xsd_file_path = "../_data/drugbank/drugbank.xsd"           # XSD schema (optional)
output_csv_path = "drugbank_drugs.csv"                     # Output CSV file
```

## Performance Notes

- The parser includes progress tracking for large files
- Memory usage is optimized by processing drugs sequentially
- Parsing time depends on file size and system resources
- For the full DrugBank dataset (~15,000 drugs), expect 1-5 minutes processing time

## Error Handling

The parser includes robust error handling:
- File existence validation
- Individual drug parsing errors are logged but don't stop the entire process
- Malformed XML elements are skipped with warnings
- Empty or missing fields are handled gracefully

## Troubleshooting

### Common Issues

1. **XML file not found**: Ensure the file path is correct and the file exists
2. **Package not found**: Run `Pkg.instantiate()` to install dependencies
3. **Memory issues**: For very large files, consider processing in chunks
4. **Parsing errors**: Check XML file validity and schema compliance

### Getting Help

If you encounter issues:
1. Check that all dependencies are installed
2. Verify the XML file is valid and accessible
3. Review the error messages for specific issues
4. Try the example script first to ensure basic functionality

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## Acknowledgments

- DrugBank for providing the comprehensive drug database
- The Julia EzXML.jl package maintainers
- The Julia DataFrames.jl and CSV.jl communities
