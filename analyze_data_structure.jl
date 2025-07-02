#!/usr/bin/env julia

using JSON3

# Load and examine the Levothyroxine data structure
data = JSON3.read(read("drug_pubmed_refs/Levothyroxine.json", String))

println("=== Levothyroxine Data Structure Analysis ===")
println("Top level keys: ", keys(data))
println("Metadata: ", data.metadata)
println()
println("Result type: ", typeof(data.result))
println("Result keys: ", keys(data.result))

# Check what's in the result
result = data.result
for key in keys(result)
    value = result[key]
    println("Key '$key': ", typeof(value))
    if isa(value, AbstractArray)
        println("  Array length: ", length(value))
        if !isempty(value)
            println("  First element type: ", typeof(value[1]))
            if haskey(value[1], "pmid") || haskey(value[1], :pmid)
                println("  First PMID: ", get(value[1], "pmid", get(value[1], :pmid, "unknown")))
            end
        end
    end
end
