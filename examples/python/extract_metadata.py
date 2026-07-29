#!/usr/bin/env python3
"""
OpenSKP — Extract Metadata Example

Extracts all metadata from a SketchUp file including
layers, materials, component hierarchy, and dynamic properties.
"""

import json
from openskp import SkpFile
from openskp.export import json_export

# Parse the SKP file
skp = SkpFile.open("model.skp")
model = skp.parse()
scene = skp.build_scene()

# Get full metadata as a dictionary, including the resolved scene hierarchy
metadata = json_export.to_dict(model, scene=scene)

# Save to JSON file
with open("metadata.json", "w") as f:
    json.dump(metadata, f, indent=2)

print(f"Metadata exported with {len(metadata['definitions'])} definitions")

# Access specific metadata
print("\n--- Scene Hierarchy ---")
def print_hierarchy(node, indent=0):
    prefix = "  " * indent
    name = node.get("name", "unnamed")
    layer = node.get("layer", "")
    print(f"{prefix}- {name} [{layer}]")
    for child in node.get("children", []):
        print_hierarchy(child, indent + 1)

print_hierarchy(metadata["scene_hierarchy"])
