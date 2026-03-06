# Structural Synthesizer

End-to-end building generation and structural design workflow.

## Quick Start

```julia
using StructuralSynthesizer

# Generate a medium office building
skel = gen_medium_office(54.0u"ft", 42.0u"ft", 10.0u"ft", 3, 3, 1)
struc = BuildingStructure(skel)

# Design the building
params = DesignParameters(name = "example", max_iterations = 3)
design = design_building(struc, params)
```

## Packages

| Package | Purpose |
|---------|---------|
| **StructuralSynthesizer** | Building generation, design workflow, visualization |
| **StructuralSizer** | Materials, sections, code checks, optimization |
| **Asap** | FEM analysis, units |

## Documentation

- [User Guide](@ref) — Capabilities, types, workflows
- [API Reference](@ref) — Function and type documentation
