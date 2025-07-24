# Excluded Drugs from Phase 1 PubMed Dataset

The following 11 drugs were excluded from the Phase 1 PubMed extraction dataset due to technical issues with PubmedBookArticle entries that are not compatible with the standard journal article extraction pipeline.

## Excluded Drugs (11 total, 41 publications)

1. **Coagulation Factor IX Human** - 1 publication
2. **Dotatate gallium Ga-68** - 1 publication  
3. **Exagamglogene autotemcel** - 29 publications
4. **Florbetaben F-18** - 1 publication
5. **Fluoroestradiol F-18** - 1 publication
6. **Human Rho(D) immune globulin** - 1 publication
7. **Human varicella-zoster immune globulin** - 1 publication
8. **Technetium Tc-99m red blood cells** - 1 publication
9. **Technetium Tc-99m tilmanocept** - 3 publications
10. **Vibrio cholerae CVD 103-HgR strain live antigen** - 1 publication
11. **Von Willebrand factor human** - 1 publication

## Technical Reason for Exclusion

These drugs consistently returned empty `publications_analyzed` arrays despite showing publications found in PubMed searches. Investigation revealed that their associated publications are stored as `PubmedBookArticle` entries (medical reference books, guidelines, etc.) rather than standard `PubmedArticle` journal articles.

The extraction pipeline is designed for journal articles with standard XML structure including titles, abstracts, and MeSH descriptors. PubmedBookArticle entries have different XML structures that are not compatible with the current extraction logic.

## Dataset Impact

- **Excluded**: 11 drugs (0.4% of total approved drugs)
- **Excluded publications**: 41 (negligible impact on 5M+ publication dataset)
- **Final dataset completeness**: 99.6% of approved drugs successfully processed

## Drug Categories

The excluded drugs are primarily:
- **Radiopharmaceuticals** (Technetium compounds, Gallium compounds, Fluorine compounds)
- **Blood products** (Coagulation factors, immune globulins)
- **Specialized biologics** (Gene therapy, vaccines)

These specialized medical products are more likely to be referenced in medical handbooks and reference materials (PubmedBookArticle) rather than primary research literature (PubmedArticle).

## Future Enhancement

The PubMed extraction pipeline has been updated to exclude PubmedBookArticle entries from future searches to prevent similar issues.