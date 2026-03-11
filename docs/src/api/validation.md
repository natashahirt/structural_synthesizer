# Input Validation

> ```julia
> result = validate_input(api_input)
> result.ok      # true if valid
> result.errors  # Vector{String} of error messages
> ```

## Overview

Input validation checks the `APIInput` for structural and logical consistency before running the design pipeline. It catches common errors — missing vertices, dangling edge references, unsupported floor types — and returns descriptive error messages.

**Source:** `StructuralSynthesizer/src/api/validation.jl`

## Functions

```@docs
validate_input
```

## Implementation Details

### Validation Checks

`validate_input(input::APIInput)` performs the following checks and returns `(ok::Bool, errors::Vector{String})`:

| Check | Description | Error Message |
|:------|:------------|:-------------|
| Units | `input.units` is `"imperial"` or `"metric"` | `"Invalid unit system: ..."` |
| Vertices non-empty | At least one vertex is defined | `"No vertices provided"` |
| Vertex dimensions | Each vertex has exactly 3 coordinates | `"Vertex N has M coordinates, expected 3"` |
| Edge vertex refs | All edge vertex indices reference valid vertices | `"Edge [v1, v2] references invalid vertex"` |
| Edge non-degenerate | No self-loops (v1 ≠ v2) | `"Edge [v, v] is degenerate"` |
| Supports exist | Support vertex indices reference valid vertices | `"Support index N is out of range"` |
| Supports non-empty | At least one support is defined | `"No supports provided"` |
| Stories Z valid | `stories_z` is non-empty and sorted | `"stories_z must be sorted ascending"` |
| Floor type valid | `params.floor_type` is a recognized type | `"Unknown floor type: ..."` |
| Column type valid | `params.column_type` is `"rc"` or `"steel"` | `"Unknown column type: ..."` |
| Beam type valid | `params.beam_type` is `"rc"` or `"steel"` | `"Unknown beam type: ..."` |
| Material names | `params.materials.*` are recognized presets | `"Unknown concrete: ..."` |
| Loads positive | All load values are non-negative | `"floor_LL_psf must be non-negative"` |
| Fire rating range | `fire_rating` is between 0 and 4 hours | `"fire_rating must be 0–4 hours"` |
| Optimization target | `optimize_for` is recognized | `"Unknown optimization target: ..."` |

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
