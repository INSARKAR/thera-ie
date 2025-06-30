# Approved Drugs Dictionary
# Generated on: 2025-06-28T21:11:31.378
# Total drugs: 2
# Note: Only includes approved drugs with valid indication data

const APPROVED_DRUGS_DICT = Dict{String, String}(
    "Cetuximab" => "For the treatment of EGFR-expressing, metastatic colorectal carcinoma.",
    "Lepirudin" => "For the treatment of heparin-induced thrombocytopenia"
)

# Usage example:
# include("approved_drugs_dict.jl")
# indication = APPROVED_DRUGS_DICT["Aspirin"]
# println(indication)
