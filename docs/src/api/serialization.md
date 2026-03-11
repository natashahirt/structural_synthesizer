# JSON Serialization

> ```julia
> skeleton = json_to_skeleton(api_input)
> params   = json_to_params(api_input.params)
> output   = design_to_json(design; geometry_hash = hash)
> hash     = compute_geometry_hash(api_input)
> ```

## Overview

The serialization module converts between JSON API types and internal Julia types. Deserialization (`json_to_*`) handles unit conversion and type mapping from JSON strings to Julia objects. Serialization (`design_to_json`) converts the `BuildingDesign` back to JSON-safe output types.

**Source:** `StructuralSynthesizer/src/api/deserialize.jl`, `serialize.jl`

## Functions

```@docs
json_to_skeleton
json_to_params
design_to_json
compute_geometry_hash
```

## Implementation Details

### json_to_skeleton

`json_to_skeleton(input::APIInput) → BuildingSkeleton` performs:

1. **Unit conversion** — vertex coordinates from input units (imperial ft or metric m) to internal units
2. **Vertex creation** — `Meshes.Point` objects from coordinate arrays
3. **Edge creation** — skeleton edges from `APIEdgeGroups`, classified into `:beams`, `:columns`, `:braces`
4. **Support marking** — vertices listed in `input.supports` are marked as restrained
5. **Story setup** — `stories_z` defines story elevations
6. **Face detection** — if `input.faces` is provided, faces are created directly; otherwise `find_faces!` detects them automatically from the edge mesh

### json_to_params

`json_to_params(params::APIParams) → DesignParameters` maps JSON string identifiers to Julia types:

| JSON String | Julia Type |
|:------------|:-----------|
| `"flat_plate"` | `FlatPlate` |
| `"flat_slab"` | `FlatSlab` |
| `"one_way"` | `OneWay` |
| `"composite_deck"` | `CompositeDeck` |
| `"vault"` | `Vault` |
| `"clt"` | `CLT` |
| `"rc"` | RC material options |
| `"steel"` | Steel material options |
| `"fc4000"` | `Concrete(fc = 4000psi)` |
| `"fc5000"` | `Concrete(fc = 5000psi)` |
| `"A992"` | `A992_Steel()` |
| `"gr60"` | `GR60_Rebar()` |
| `"weight"` | `MinWeight()` |
| `"carbon"` | `MinCarbon()` |
| `"ddm"` | `DDM()` |
| `"efm"` | `EFM()` |
| `"fea"` | `FEA()` |

### design_to_json

`design_to_json(design::BuildingDesign; geometry_hash) → APIOutput` converts the design to JSON-safe output:

1. **Summary** — extracts material quantities, embodied carbon, pass/fail status
2. **Slabs** — converts each `SlabDesignResult` to `APISlabResult` with imperial dimensions
3. **Columns** — converts each `ColumnDesignResult` to `APIColumnResult`
4. **Beams** — converts each `BeamDesignResult` to `APIBeamResult`
5. **Foundations** — converts each `FoundationDesignResult` to `APIFoundationResult`
6. **Visualization** — if enabled, generates `APIVisualization` with node positions, frame elements, slab meshes, and deflected shapes
7. **Metadata** — `compute_time_s`, `geometry_hash`, status

### compute_geometry_hash

`compute_geometry_hash(input::APIInput) → String` computes a SHA-256 hash of the geometry-defining fields:
- `vertices`
- `edges` (beams, columns, braces)
- `supports`
- `stories_z`
- `faces` (if provided)

The hash is used to detect when two requests share the same geometry, enabling skeleton reuse and skipping the `json_to_skeleton` and `find_faces!` steps.

## Limitations & Future Work

- Unit conversion assumes all input is in consistent units; mixing units within a single input is not supported.
- Custom material definitions beyond the preset names require extending the `json_to_params` mapping.
- Serialization of visualization data is the most expensive part; it can be disabled via `SS_ENABLE_VISUALIZATION=false`.
