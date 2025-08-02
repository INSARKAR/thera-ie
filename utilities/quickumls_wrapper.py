#!/usr/bin/env python
"""
QuickUMLS Wrapper for THERA-IE

This script provides a command-line interface to QuickUMLS for Julia integration.
Handles the libiconv issue and provides CUI mappings for medical terms.
"""

import os
import sys
import json
import argparse

# Set up environment for libiconv
libiconv_path = "/oscar/rt/9.2/software/0.20-generic/0.20.1/opt/spack/linux-rhel9-x86_64_v3/gcc-11.3.1/libiconv-1.17-jwjcds2nmpz7gpstqq22vty7jxldvpec/lib/libiconv.so.2"

# Preload libiconv
import ctypes
ctypes.CDLL(libiconv_path, mode=ctypes.RTLD_GLOBAL)

def initialize_quickumls():
    """Initialize QuickUMLS matcher"""
    try:
        from quickumls import QuickUMLS
        
        # Use the existing QuickUMLS index
        index_path = '/users/isarkar/sarkarcode/_data/quickumls/quickumls_index'
        
        if not os.path.exists(index_path):
            print(json.dumps({"error": f"QuickUMLS index not found at {index_path}"}))
            sys.exit(1)
        
        matcher = QuickUMLS(index_path, threshold=0.7, window=5)
        return matcher
        
    except Exception as e:
        print(json.dumps({"error": f"QuickUMLS initialization failed: {str(e)}"}))
        sys.exit(1)

def query_quickumls(matcher, term):
    """Query QuickUMLS for CUI mappings"""
    try:
        matches = matcher.match(term, best_match=True, ignore_syntax=False)
        
        results = []
        for match in matches:
            for concept in match:
                cui = concept.get('cui', '')
                # Handle preferred name (could be string or index)
                preferred = concept.get('preferred', '')
                if isinstance(preferred, (int, float)):
                    # If it's an index, get the term from the match
                    preferred_name = concept.get('term', str(preferred))
                else:
                    preferred_name = str(preferred)
                
                similarity = concept.get('similarity', 0.0)
                semtypes = list(concept.get('semtypes', []))
                
                results.append({
                    "cui": cui,
                    "preferred_name": preferred_name,
                    "similarity": similarity,
                    "semtypes": semtypes,
                    "method": "quickumls"
                })
        
        # Sort by similarity and return top 3
        results.sort(key=lambda x: x['similarity'], reverse=True)
        return results[:3]
        
    except Exception as e:
        return [{"error": f"QuickUMLS query failed: {str(e)}"}]

def batch_query_quickumls(matcher, terms):
    """Query QuickUMLS for multiple terms efficiently"""
    try:
        batch_results = {}
        
        for term in terms:
            results = query_quickumls(matcher, term)
            batch_results[term] = results
            
        return batch_results
        
    except Exception as e:
        return {"error": f"Batch QuickUMLS query failed: {str(e)}"}

def main():
    parser = argparse.ArgumentParser(description='QuickUMLS Wrapper for CUI mapping')
    parser.add_argument('--term', help='Single medical term to map to CUI')
    parser.add_argument('--batch-file', help='File containing terms (one per line)')
    parser.add_argument('--batch-terms', nargs='+', help='Multiple terms as arguments')
    parser.add_argument('--output', default='json', choices=['json', 'simple'], 
                       help='Output format')
    
    args = parser.parse_args()
    
    # Initialize QuickUMLS
    matcher = initialize_quickumls()
    
    # Determine input mode
    if args.batch_file:
        # Read terms from file
        with open(args.batch_file, 'r') as f:
            terms = [line.strip() for line in f if line.strip()]
        batch_results = batch_query_quickumls(matcher, terms)
        print(json.dumps(batch_results, indent=2))
        
    elif args.batch_terms:
        # Process multiple terms from command line
        batch_results = batch_query_quickumls(matcher, args.batch_terms)
        print(json.dumps(batch_results, indent=2))
        
    elif args.term:
        # Single term mode (backward compatibility)
        results = query_quickumls(matcher, args.term)
        
        if args.output == 'json':
            print(json.dumps(results, indent=2))
        else:
            for result in results:
                if "error" not in result:
                    print(f"CUI: {result['cui']}")
                    print(f"Preferred: {result['preferred_name']}")
                    print(f"Similarity: {result['similarity']:.3f}")
                    print("---")
    else:
        print("Error: Must provide either --term, --batch-file, or --batch-terms")
        sys.exit(1)

if __name__ == "__main__":
    main()