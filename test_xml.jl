#!/usr/bin/env julia

"""
Test XML parsing functionality
"""

using EzXML

function test_xml_parsing()
    # Create a simple test XML
    test_xml = """<?xml version="1.0" encoding="UTF-8"?>
<drugbank>
  <drug>
    <drugbank-id primary="true">DB00001</drugbank-id>
    <name>Test Drug</name>
    <description>A test drug</description>
    <state>solid</state>
    <groups>
      <group>approved</group>
    </groups>
  </drug>
</drugbank>"""
    
    println("Testing XML parsing...")
    
    try
        # Test parsing
        doc = parsexml(test_xml)
        root = doc.root
        println("✓ XML parsing successful")
        println("Root element: $(nodename(root))")
        
        # Test element iteration
        for child in eachelement(root)
            println("Child element: $(nodename(child))")
            
            for grandchild in eachelement(child)
                println("  Grandchild: $(nodename(grandchild)) = $(nodecontent(grandchild))")
                
                # Test attributes
                if nodename(grandchild) == "drugbank-id"
                    if haskey(grandchild, "primary")
                        println("    Attribute 'primary': $(grandchild["primary"])")
                    end
                end
            end
        end
        
        return true
        
    catch e
        println("✗ XML parsing failed: $e")
        return false
    end
end

# Run the test
if abspath(PROGRAM_FILE) == @__FILE__
    test_xml_parsing()
end
