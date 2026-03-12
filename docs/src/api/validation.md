# Input Validation

> ```julia
> result = validate_input(api_input)
> result.ok      # true if valid
> result.errors  # Vector{String} of error messages
> ```

## Overview

Input validation checks the `APIInput` for basic structural and logical consistency before running the design pipeline (units present, indices in range, etc.). It returns a `ValidationResult` containing `.ok::Bool` and `.errors::Vector{String}`.

**Source:** `StructuralSynthesizer/src/api/validation.jl`

## Functions

```@docs
validate_input
```

## Implementation Details

### Validation Checks

`validate_input(input::APIInput)` performs the following checks and returns a `ValidationResult` with `.ok::Bool` and `.errors::Vector{String}`:

| Check | Description | Error Message |
|:------|:------------|:-------------|
| Units | `input.units` is present and parses via `parse_unit` | `"Missing required field \"units\". Specify coordinate units: \"feet\", \"inches\", \"meters\", or \"mm\"."` or `ArgumentError(...)` string from `parse_unit` |
| Vertices | At least 4 vertices required; each vertex has exactly 3 coordinates | `"Need at least 4 vertices (got N)."` and/or `"Vertex i has k coordinates (expected 3)."` |
| Edges | At least one edge (beams/columns/braces); each edge has 2 valid **1-based** vertex indices and is non-degenerate | `"No edges provided (need at least beams, columns, or braces)."` / `"Edge i has k vertex indices (expected 2)."` / `"Edge i: vertex index v out of range [1, N]."` / `"Edge i: degenerate edge (both indices = v)."` |
| Supports | At least one support; each index references a valid **1-based** vertex | `"No support vertices specified."` / `"Support i: vertex index v out of range [1, N]."` |
| Stories Z | Only validated if provided (non-empty); needs at least 2 elevations | `"If provided, need at least 2 story elevations (got N)."` |
| Faces | If provided, each face polyline has ≥ 3 vertices and each vertex has 3 coordinates | `"Face \"category\"[j] has N vertices (need ≥ 3)."` / `"Face \"category\"[j] vertex k has n coords (expected 3)."` |
| Fire rating | `fire_rating` is one of 0, 1, 1.5, 2, 3, 4 | `"Invalid fire_rating r. Must be one of: 0, 1, 1.5, 2, 3, 4."` |
| Optimization target | `optimize_for` is `"weight"`, `"carbon"`, or `"cost"` | `"Invalid optimize_for \"...\". Must be: weight, carbon, or cost."` |
| Material names | `params.materials.concrete`, `.rebar`, `.steel` are present in the resolver maps (`NWC_3000/4000/5000/6000`, `Rebar_40/60/75/80`, `A992`) | `"Unknown concrete \"...\". Options: ..."` / `"Unknown rebar \"...\". Options: ..."` / `"Unknown steel \"...\". Options: ..."` |

### Validation Response

The validation result is used in two places:

1. **`POST /validate`** — returns the validation result directly as JSON
2. **`POST /design`** — validates first; if invalid, returns an `APIError` without running the pipeline

### Early Return

Validation is designed for fast rejection: checks are ordered from cheapest to most expensive. If any check fails, subsequent checks may still run to collect all errors in a single response.

## Options & Configuration

Validation rules are hardcoded to match the supported API schema. Adding new floor types, material presets, or optimization targets requires updating both `json_to_params` and `validate_input`.

## Limitations & Future Work

- Geometric validity (e.g., non-intersecting edges, planar faces) is not checked during validation; it is handled during skeleton construction.
- Custom material definitions are not validated; they pass validation but may fail during `json_to_params`.
- Schema versioning would allow different validation rules for different API versions.

## References

- `StructuralSynthesizer/src/api/validation.jl`
