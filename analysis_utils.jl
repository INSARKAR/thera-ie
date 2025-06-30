#!/usr/bin/env julia

"""
DrugBank Data Analysis Utilities

Additional analysis functions for DrugBank XML data.
"""

include("drugbank_parser.jl")

"""
    filter_drugs_by_group(drugs::Vector{Drug}, group::String) -> Vector{Drug}

Filter drugs by a specific group (e.g., "approved", "experimental").
"""
function filter_drugs_by_group(drugs::Vector{Drug}, group::String)
    return filter(drug -> group in drug.groups, drugs)
end

"""
    filter_drugs_by_state(drugs::Vector{Drug}, state::String) -> Vector{Drug}

Filter drugs by physical state (e.g., "solid", "liquid").
"""
function filter_drugs_by_state(drugs::Vector{Drug}, state::String)
    return filter(drug -> drug.state == state, drugs)
end

"""
    search_drugs_by_indication(drugs::Vector{Drug}, keyword::String) -> Vector{Drug}

Search for drugs by indication keyword.
"""
function search_drugs_by_indication(drugs::Vector{Drug}, keyword::String)
    keyword_lower = lowercase(keyword)
    return filter(drug -> occursin(keyword_lower, lowercase(drug.indication)), drugs)
end

"""
    get_drugs_with_complete_pharmacokinetics(drugs::Vector{Drug}) -> Vector{Drug}

Get drugs that have complete pharmacokinetic information.
"""
function get_drugs_with_complete_pharmacokinetics(drugs::Vector{Drug})
    return filter(drugs) do drug
        !isempty(drug.absorption) && 
        !isempty(drug.metabolism) && 
        !isempty(drug.half_life) && 
        !isempty(drug.clearance)
    end
end

"""
    analyze_drug_categories(drugs::Vector{Drug})

Analyze drug categories and their frequencies.
"""
function analyze_drug_categories(drugs::Vector{Drug})
    category_counts = Dict{String, Int}()
    
    for drug in drugs
        for category in drug.categories
            if !isempty(category)
                category_counts[category] = get(category_counts, category, 0) + 1
            end
        end
    end
    
    println("Top Drug Categories:")
    sorted_categories = sort(collect(category_counts), by=x->x[2], rev=true)
    for (i, (category, count)) in enumerate(sorted_categories[1:min(20, length(sorted_categories))])
        println("$i. $category: $count drugs")
    end
    
    return category_counts
end

"""
    analyze_pharmacokinetic_completeness(drugs::Vector{Drug})

Analyze the completeness of pharmacokinetic data.
"""
function analyze_pharmacokinetic_completeness(drugs::Vector{Drug})
    pk_fields = [
        ("Absorption", :absorption),
        ("Metabolism", :metabolism),
        ("Half-life", :half_life),
        ("Protein Binding", :protein_binding),
        ("Route of Elimination", :route_of_elimination),
        ("Volume of Distribution", :volume_of_distribution),
        ("Clearance", :clearance)
    ]
    
    println("Pharmacokinetic Data Completeness:")
    println("==================================")
    
    total_drugs = length(drugs)
    
    for (field_name, field_symbol) in pk_fields
        complete_count = count(drug -> !isempty(getfield(drug, field_symbol)), drugs)
        percentage = round(complete_count / total_drugs * 100, digits=1)
        println("$field_name: $complete_count/$total_drugs ($percentage%)")
    end
    
    # Count drugs with all PK data
    complete_pk_drugs = get_drugs_with_complete_pharmacokinetics(drugs)
    pk_percentage = round(length(complete_pk_drugs) / total_drugs * 100, digits=1)
    println("\nComplete PK profile: $(length(complete_pk_drugs))/$total_drugs ($pk_percentage%)")
end

"""
    export_filtered_data(drugs::Vector{Drug}, filter_func::Function, filename::String)

Export filtered drug data to CSV.
"""
function export_filtered_data(drugs::Vector{Drug}, filter_func::Function, filename::String)
    filtered_drugs = filter(filter_func, drugs)
    export_to_csv(filtered_drugs, filename)
    println("Exported $(length(filtered_drugs)) filtered drugs to $filename")
end

"""
    generate_drug_summary_report(drugs::Vector{Drug}, output_file::String="drug_summary_report.txt")

Generate a comprehensive summary report of the drug data.
"""
function generate_drug_summary_report(drugs::Vector{Drug}, output_file::String="drug_summary_report.txt")
    open(output_file, "w") do file
        redirect_stdout(file) do
            println("DrugBank Data Summary Report")
            println("============================")
            println("Generated on: $(now())")
            println("Total drugs analyzed: $(length(drugs))")
            println()
            
            # Basic statistics
            analyze_drugs(drugs)
            println()
            
            # Category analysis
            analyze_drug_categories(drugs)
            println()
            
            # Pharmacokinetic completeness
            analyze_pharmacokinetic_completeness(drugs)
            println()
            
            # Group analysis
            approved_drugs = filter_drugs_by_group(drugs, "approved")
            experimental_drugs = filter_drugs_by_group(drugs, "experimental")
            withdrawn_drugs = filter_drugs_by_group(drugs, "withdrawn")
            
            println("Drug Status Analysis:")
            println("====================")
            println("Approved drugs: $(length(approved_drugs))")
            println("Experimental drugs: $(length(experimental_drugs))")
            println("Withdrawn drugs: $(length(withdrawn_drugs))")
            println()
            
            # State analysis
            solid_drugs = filter_drugs_by_state(drugs, "solid")
            liquid_drugs = filter_drugs_by_state(drugs, "liquid")
            
            println("Physical State Analysis:")
            println("========================")
            println("Solid drugs: $(length(solid_drugs))")
            println("Liquid drugs: $(length(liquid_drugs))")
            println()
            
            # Sample indications analysis
            cancer_drugs = search_drugs_by_indication(drugs, "cancer")
            diabetes_drugs = search_drugs_by_indication(drugs, "diabetes")
            hypertension_drugs = search_drugs_by_indication(drugs, "hypertension")
            
            println("Indication Analysis (Sample):")
            println("=============================")
            println("Cancer-related drugs: $(length(cancer_drugs))")
            println("Diabetes-related drugs: $(length(diabetes_drugs))")
            println("Hypertension-related drugs: $(length(hypertension_drugs))")
        end
    end
    
    println("Summary report saved to: $output_file")
end

"""
    interactive_analysis_menu(drugs::Vector{Drug})

Interactive menu for analyzing drug data.
"""
function interactive_analysis_menu(drugs::Vector{Drug})
    while true
        println("\n=== DrugBank Data Analysis Menu ===")
        println("1. Filter by drug group")
        println("2. Filter by physical state")
        println("3. Search by indication")
        println("4. Analyze drug categories")
        println("5. Analyze pharmacokinetic completeness")
        println("6. Generate summary report")
        println("7. Export filtered data")
        println("8. Exit")
        print("\nSelect an option (1-8): ")
        
        choice = readline()
        
        try
            if choice == "1"
                print("Enter drug group (e.g., approved, experimental): ")
                group = readline()
                filtered = filter_drugs_by_group(drugs, group)
                println("Found $(length(filtered)) drugs in group '$group'")
                if length(filtered) > 0
                    for (i, drug) in enumerate(filtered[1:min(5, length(filtered))])
                        println("  $i. $(drug.name) ($(drug.drugbank_id))")
                    end
                    if length(filtered) > 5
                        println("  ... and $(length(filtered) - 5) more")
                    end
                end
                
            elseif choice == "2"
                print("Enter physical state (e.g., solid, liquid): ")
                state = readline()
                filtered = filter_drugs_by_state(drugs, state)
                println("Found $(length(filtered)) drugs in state '$state'")
                
            elseif choice == "3"
                print("Enter indication keyword: ")
                keyword = readline()
                filtered = search_drugs_by_indication(drugs, keyword)
                println("Found $(length(filtered)) drugs with indication containing '$keyword'")
                
            elseif choice == "4"
                analyze_drug_categories(drugs)
                
            elseif choice == "5"
                analyze_pharmacokinetic_completeness(drugs)
                
            elseif choice == "6"
                print("Enter output filename (default: drug_summary_report.txt): ")
                filename = readline()
                if isempty(filename)
                    filename = "drug_summary_report.txt"
                end
                generate_drug_summary_report(drugs, filename)
                
            elseif choice == "7"
                println("Export filtered data - choose filter:")
                println("  a. Approved drugs")
                println("  b. Drugs with complete PK data")
                println("  c. Solid drugs")
                print("Select filter (a/b/c): ")
                filter_choice = readline()
                
                if filter_choice == "a"
                    export_filtered_data(drugs, d -> "approved" in d.groups, "approved_drugs.csv")
                elseif filter_choice == "b"
                    export_filtered_data(drugs, d -> !isempty(d.absorption) && !isempty(d.metabolism) && !isempty(d.half_life), "complete_pk_drugs.csv")
                elseif filter_choice == "c"
                    export_filtered_data(drugs, d -> d.state == "solid", "solid_drugs.csv")
                else
                    println("Invalid filter choice")
                end
                
            elseif choice == "8"
                println("Exiting analysis menu...")
                break
                
            else
                println("Invalid choice. Please select 1-8.")
            end
            
        catch e
            println("Error: $e")
        end
    end
end

"""
    main_analysis()

Main function for running interactive analysis.
"""
function main_analysis()
    xml_file_path = "../_data/drugbank/drugbank-20250628.xml"
    
    println("Loading DrugBank data...")
    drugs = parse_drugbank_xml(xml_file_path)
    
    println("Data loaded successfully!")
    interactive_analysis_menu(drugs)
end

# Run the analysis if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main_analysis()
end
