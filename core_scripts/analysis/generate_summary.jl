using JSON3, Statistics

include("phase3_simple_string_evaluator.jl")

results = []
for file in readdir("phase3_simple_results")
    if endswith(file, "_simple_evaluation.json") && !contains(file, "summary")
        data = JSON3.read(read("phase3_simple_results/$file", String))
        push!(results, data)
    end
end

if !isempty(results)
    generate_summary_report(results)
    println("Summary report generated with $(length(results)) drugs")
else
    println("No results found")
end