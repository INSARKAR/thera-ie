#!/usr/bin/env julia

"""
Phase 2 Step 4: Zero Indications Monitor

This script monitors and debugs Phase 2 Step 4 results by identifying files with 0 indications
and providing detailed analysis for troubleshooting parsing issues.

Usage:
    julia phase2_step4_monitor_zero_indications.jl [--remove-zeros]

Options:
    --remove-zeros    Remove files with 0 indications (use with caution)

Author: Thera Pipeline
Date: 2025-07-23
"""

using JSON3
using Dates

# Configuration
const RESULTS_DIR = "phase2_indications_llama_pubmed"
const LOG_FILE = "logs/zero_indications_monitor.log"

function log_message(message::String)
    """Log message to both console and file"""
    timestamp = now()
    log_entry = "[$timestamp] $message"
    println(log_entry)
    
    # Ensure logs directory exists
    if !isdir("logs")
        mkdir("logs")
    end
    
    open(LOG_FILE, "a") do file
        println(file, log_entry)
    end
end

function classify_zero_indication_file(filepath::String)
    """Classify why a file has 0 indications: legitimate vs parsing issue"""
    try
        data = JSON3.read(read(filepath, String))
        
        if !haskey(data, :raw_llama_response)
            return :no_response, "No raw_llama_response found"
        end
        
        response = data.raw_llama_response
        
        # Check for legitimate "no indications" responses
        no_indication_phrases = [
            r"can't provide.*list.*medical conditions"i,
            r"couldn't find.*information"i,
            r"no.*indications.*found"i,
            r"not.*real medication"i,
            r"don't have.*information"i,
            r"unable to.*identify.*conditions"i
        ]
        
        for phrase in no_indication_phrases
            if occursin(phrase, response)
                return :legitimate_no_indications, "LLM legitimately found no therapeutic indications"
            end
        end
        
        # Check for structured responses that failed parsing
        indication_markers = [
            r"Indication\s+\d+:"i,
            r"\b\d+\.\s*\n"i,
            r"INDICATION:"i
        ]
        
        has_structure = any(pattern -> occursin(pattern, response), indication_markers)
        has_confidence = occursin(r"CONFIDENCE:"i, response)
        has_pmids = occursin(r"PMIDS:"i, response)
        
        if has_structure || has_confidence || has_pmids
            return :parsing_issue, "LLM provided structured response but parsing failed"
        end
        
        # Check for informal indication mentions
        if occursin(r"treat|therapy|treatment|condition|disease|indication"i, response)
            return :informal_response, "LLM mentioned treatments but not in structured format"
        end
        
        return :unclear, "Response type unclear - needs manual inspection"
        
    catch e
        return :error, "Error reading file: $e"
    end
end

function analyze_parsing_issue(filepath::String)
    """Detailed analysis of files with parsing issues"""
    try
        data = JSON3.read(read(filepath, String))
        response = data.raw_llama_response
        
        println("\n" * "="^60)
        println("🔧 PARSING ISSUE ANALYSIS: $(basename(filepath))")
        println("="^60)
        
        # Basic info
        println("📊 Drug: $(get(data.metadata, :drug_name, "Unknown"))")
        println("📚 Publications: $(get(data.metadata, :total_publications_analyzed, 0))")
        
        # Test parsing manually
        println("\n🧪 Manual Parsing Test:")
        
        # Test both splitting patterns
        sections_indication = split(response, r"Indication\s+\d+:"i)
        sections_numbered = split(response, r"\b\d+\.\s*\n")
        
        println("  • 'Indication X:' pattern found $(length(sections_indication)-1) sections")
        println("  • 'X.' pattern found $(length(sections_numbered)-1) sections")
        
        sections = length(sections_indication) > length(sections_numbered) ? sections_indication : sections_numbered
        
        if length(sections) > 1
            println("  • Using $(length(sections)-1) sections for analysis")
            
            for (i, section) in enumerate(sections[2:end])
                println("\n  📋 Section $i:")
                lines = split(section, '\n')
                indication_name = ""
                confidence = 0.0
                pmids = String[]
                
                for line in lines
                    line = strip(line)
                    if isempty(line) continue end
                    
                    if startswith(uppercase(line), "INDICATION:")
                        indication_name = strip(replace(line, r"^INDICATION:\s*"i => ""))
                        println("    → INDICATION: \"$indication_name\"")
                    elseif startswith(uppercase(line), "CONFIDENCE:")
                        confidence_text = strip(replace(line, r"^CONFIDENCE:\s*"i => ""))
                        try
                            confidence = parse(Float64, confidence_text)
                            println("    → CONFIDENCE: $confidence")
                        catch
                            println("    → CONFIDENCE: \"$confidence_text\" (parse failed)")
                        end
                    elseif startswith(uppercase(line), "PMIDS:")
                        pmids_text = strip(replace(line, r"^PMIDS:\s*"i => ""))
                        if !isempty(pmids_text)
                            pmids = [strip(pmid) for pmid in split(pmids_text, ",") if !isempty(strip(pmid))]
                            println("    → PMIDS: $pmids")
                        end
                    elseif isempty(indication_name) && !startswith(uppercase(line), r"INDICATION:|EVIDENCE:|CONFIDENCE:|PMIDS:|REASONING:")
                        indication_name = line
                        println("    → INDICATION (inferred): \"$indication_name\"")
                    end
                end
                
                # Check if this would be a valid indication
                if !isempty(indication_name) && confidence > 0
                    println("    ✅ Would extract: \"$indication_name\" (conf: $confidence)")
                else
                    println("    ❌ Would not extract (name: \"$indication_name\", conf: $confidence)")
                end
            end
        else
            println("  ❌ No sections found - response not properly structured")
        end
        
        # Show problematic response
        println("\n📋 Full Response:")
        println("\"$response\"")
        
        return true
        
    catch e
        println("❌ Error analyzing parsing issue: $e")
        return false
    end
end

function scan_for_zero_indications()
    """Scan results directory for files with 0 indications and classify issues"""
    
    if !isdir(RESULTS_DIR)
        log_message("❌ Results directory not found: $RESULTS_DIR")
        return
    end
    
    log_message("🔍 Scanning for files with 0 indications...")
    
    json_files = filter(f -> endswith(f, ".json"), readdir(RESULTS_DIR))
    total_files = length(json_files)
    
    # Classification categories
    legitimate_no_indications = String[]
    parsing_issues = String[]
    informal_responses = String[]
    unclear_responses = String[]
    analysis_errors = String[]
    
    println("📁 Found $total_files result files")
    
    for (i, filename) in enumerate(json_files)
        filepath = joinpath(RESULTS_DIR, filename)
        
        # Progress indicator
        if i % 100 == 0 || i == total_files
            print("\\r📊 Progress: $i/$total_files files scanned")
        end
        
        try
            data = JSON3.read(read(filepath, String))
            
            # Check for 0 indications
            total_indications = get(data.metadata, :total_indications_found, -1)
            
            if total_indications == 0
                classification, reason = classify_zero_indication_file(filepath)
                
                if classification == :legitimate_no_indications
                    push!(legitimate_no_indications, filepath)
                elseif classification == :parsing_issue
                    push!(parsing_issues, filepath)
                elseif classification == :informal_response
                    push!(informal_responses, filepath)
                elseif classification == :unclear
                    push!(unclear_responses, filepath)
                else
                    push!(analysis_errors, "$filename: $reason")
                end
            end
            
        catch e
            push!(analysis_errors, "$filename: $e")
        end
    end
    
    println("\\n")  # New line after progress indicator
    
    total_zeros = length(legitimate_no_indications) + length(parsing_issues) + length(informal_responses) + length(unclear_responses)
    
    # Summary report
    println("\\n" * "="^60)
    println("📊 ZERO INDICATIONS CLASSIFICATION REPORT")
    println("="^60)
    println("📅 Timestamp: $(now())")
    println("📁 Directory: $RESULTS_DIR")
    println("📈 Total files: $total_files")
    println("❌ Zero indication files: $total_zeros")
    
    success_rate = round((total_files - total_zeros) / total_files * 100, digits=1)
    println("📊 Success Rate: $success_rate%")
    
    println("\\n🏷️  Classification Breakdown:")
    println("  ✅ Legitimate no indications: $(length(legitimate_no_indications))")
    println("  🔧 Parsing issues (fixable): $(length(parsing_issues))")
    println("  💬 Informal responses: $(length(informal_responses))")
    println("  ❓ Unclear responses: $(length(unclear_responses))")
    println("  ⚠️  Analysis errors: $(length(analysis_errors))")
    
    # Show details for each category
    if !isempty(legitimate_no_indications)
        println("\\n✅ LEGITIMATE NO INDICATIONS ($(length(legitimate_no_indications))) - Leave these alone:")
        for filepath in legitimate_no_indications[1:min(5, length(legitimate_no_indications))]
            drug_name = replace(basename(filepath), "_pubmed_llama_indications.json" => "")
            println("  • $drug_name")
        end
        if length(legitimate_no_indications) > 5
            println("  • ... and $(length(legitimate_no_indications) - 5) more")
        end
    end
    
    if !isempty(parsing_issues)
        println("\\n🔧 PARSING ISSUES ($(length(parsing_issues))) - These need debugging:")
        for filepath in parsing_issues
            drug_name = replace(basename(filepath), "_pubmed_llama_indications.json" => "")
            println("  • $drug_name")
        end
        
        println("\\n🔍 DETAILED PARSING ANALYSIS:")
        for filepath in parsing_issues[1:min(2, length(parsing_issues))]
            analyze_parsing_issue(filepath)
        end
    end
    
    if !isempty(informal_responses)
        println("\\n💬 INFORMAL RESPONSES ($(length(informal_responses))) - LLM mentioned treatments informally:")
        for filepath in informal_responses[1:min(3, length(informal_responses))]
            drug_name = replace(basename(filepath), "_pubmed_llama_indications.json" => "")
            println("  • $drug_name")
        end
    end
    
    if !isempty(unclear_responses)
        println("\\n❓ UNCLEAR RESPONSES ($(length(unclear_responses))) - Need manual inspection:")
        for filepath in unclear_responses
            drug_name = replace(basename(filepath), "_pubmed_llama_indications.json" => "")
            println("  • $drug_name")
        end
    end
    
    if !isempty(analysis_errors)
        println("\\n🚨 ANALYSIS ERRORS:")
        for error in analysis_errors
            println("  • $error")
        end
    end
    
    # Log summary
    log_message("📊 Classification complete: $total_files total, $(length(parsing_issues)) parsing issues need attention")
end

function main()
    """Main execution function"""
    
    println("🔍 Phase 2 Step 4: Zero Indications Debug Monitor")
    println("📋 This script classifies 0-indication files and identifies parsing issues")
    println()
    
    # Run the classification scan
    scan_for_zero_indications()
    
    println("\\n📋 Analysis complete. Check $LOG_FILE for detailed logs.")
    println("\\n💡 Summary:")
    println("  • Files with legitimate no indications should be left alone")
    println("  • Files with parsing issues may need code fixes")
    println("  • Files with informal responses might benefit from prompt refinement")
end

# Run main function if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end