# API Schema

> ```julia
> # All input/output types are defined in:
> # StructuralSynthesizer/src/api/schema.jl
> ```

## Overview

The API schema defines the JSON input and output structures for the HTTP API. Input types are mutable structs (for JSON deserialization via StructTypes.jl), and output types are immutable structs (for serialization).

## Input Types

### APIInput

The top-level input object sent to `POST /design` and `POST /validate`.

| Field | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `units` | `String` | yes | Unit system: `"imperial"` or `"metric"` |
| `vertices` | `Vector{Vector{Float64}}` | yes | 3D vertex coordinates `[[x,y,z], ...]` |
| `edges` | `APIEdgeGroups` | yes | Edge connectivity by group |
| `supports` | `Vector{Int}` | yes | Vertex indices with support conditions |
| `stories_z` | `Vector{Float64}` | yes | Story elevation Z coordinates |
| `faces` | `APIFaceGroups` | no | Face definitions by group (auto-detected if omitted) |
| `params` | `APIParams` | yes | Design parameters |
| `geometry_hash` | `String` | no | Precomputed geometry hash for caching |

```@docs
APIInput
```

### APIEdgeGroups

| Field | Type | Description |
|:------|:-----|:------------|
| `beams` | `Vector{Vector{Int}}` | Beam edges as `[[v1, v2], ...]` (0-indexed vertex pairs) |
| `columns` | `Vector{Vector{Int}}` | Column edges |
| `braces` | `Vector{Vector{Int}}` | Brace edges (optional) |

```@docs
APIEdgeGroups
```

### APIFaceGroups

A dictionary mapping face group names to face vertex lists:

```json
{
  "floor": [[[0,1,2,3], [4,5,6,7]]],
  "roof": [[[8,9,10,11]]],
  "grade": [[[12,13,14,15]]]
}
```

### APIParams

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `unit_system` | `String` | `"imperial"` | `"imperial"` or `"metric"` |
| `loads` | `APILoads` | — | Gravity loading |
| `floor_type` | `String` | `"flat_plate"` | Floor system type |
| `floor_options` | `APIFloorOptions` | — | Floor-specific options |
| `materials` | `APIMaterials` | — | Material selections |
| `column_type` | `String` | `"rc"` | `"rc"` or `"steel"` |
| `beam_type` | `String` | `"rc"` | `"rc"` or `"steel"` |
| `fire_rating` | `Float64` | `0.0` | Fire resistance in hours |
| `optimize_for` | `String` | `"weight"` | `"weight"`, `"volume"`, `"cost"`, `"carbon"` |
| `size_foundations` | `Bool` | `true` | Whether to size foundations |
| `foundation_soil` | `String` | `"medium_sand"` | Soil type name |

```@docs
APIParams
```

### APILoads

| Field | Type | Unit | Description |
|:------|:-----|:-----|:------------|
| `floor_LL_psf` | `Float64` | psf | Floor live load |
| `roof_LL_psf` | `Float64` | psf | Roof live load |
| `grade_LL_psf` | `Float64` | psf | Grade live load |
| `floor_SDL_psf` | `Float64` | psf | Floor superimposed dead load |
| `roof_SDL_psf` | `Float64` | psf | Roof superimposed dead load |
| `wall_SDL_psf` | `Float64` | psf | Perimeter wall dead load |

```@docs
APILoads
```

### APIFloorOptions

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `method` | `String` | `"ddm"` | Analysis method: `"ddm"`, `"efm"`, `"fea"`, `"rule_of_thumb"` |
| `deflection_limit` | `Float64` | `240.0` | L/n deflection limit |
| `punching_strategy` | `String` | `"auto"` | `"auto"`, `"thicken"`, `"studs"`, `"drop_panel"` |

```@docs
APIFloorOptions
```

### APIMaterials

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `concrete` | `String` | `"fc4000"` | Concrete name (e.g., `"fc4000"`, `"fc5000"`) |
| `rebar` | `String` | `"gr60"` | Rebar grade |
| `steel` | `String` | `"A992"` | Structural steel grade |

```@docs
APIMaterials
```

## Output Types

### APIOutput

The top-level response from `POST /design`.

| Field | Type | Description |
|:------|:-----|:------------|
| `status` | `String` | `"ok"` or `"error"` |
| `compute_time_s` | `Float64` | Wall-clock design time in seconds |
| `summary` | `APISummary` | Design summary |
| `slabs` | `Vector{APISlabResult}` | Per-slab results |
| `columns` | `Vector{APIColumnResult}` | Per-column results |
| `beams` | `Vector{APIBeamResult}` | Per-beam results |
| `foundations` | `Vector{APIFoundationResult}` | Per-foundation results |
| `geometry_hash` | `String` | Geometry hash for caching |
| `visualization` | `APIVisualization` | Visualization data (optional) |

```@docs
APIOutput
```

### APISummary

| Field | Type | Description |
|:------|:-----|:------------|
| `all_pass` | `Bool` | All elements pass code checks |
| `concrete_volume_ft3` | `Float64` | Total concrete volume |
| `steel_weight_lb` | `Float64` | Total structural steel weight |
| `rebar_weight_lb` | `Float64` | Total rebar weight |
| `embodied_carbon_kgCO2e` | `Float64` | Total embodied carbon |
| `critical_ratio` | `Float64` | Governing D/C ratio |
| `critical_element` | `String` | Element with highest D/C |

```@docs
APISummary
```

### APISlabResult

| Field | Type | Description |
|:------|:-----|:------------|
| `id` | `Int` | Slab index |
| `thickness_in` | `Float64` | Slab thickness in inches |
| `converged` | `Bool` | Design converged |
| `failure_reason` | `String` | Failure description (empty if ok) |
| `failing_check` | `String` | Which check failed |
| `iterations` | `Int` | Design iterations used |
| `deflection_ok` | `Bool` | Deflection within limit |
| `deflection_ratio` | `Float64` | Actual L/n ratio |
| `punching_ok` | `Bool` | Punching shear adequate |
| `punching_max_ratio` | `Float64` | Maximum punching D/C |

```@docs
APISlabResult
```

### APIColumnResult

| Field | Type | Description |
|:------|:-----|:------------|
| `id` | `Int` | Column index |
| `section` | `String` | Section designation |
| `c1_in` | `Float64` | Depth dimension |
| `c2_in` | `Float64` | Width dimension |
| `shape` | `String` | `"rectangular"` or `"circular"` |
| `axial_ratio` | `Float64` | Pu / ϕPn |
| `interaction_ratio` | `Float64` | P-M interaction ratio |
| `ok` | `Bool` | Passes all checks |

```@docs
APIColumnResult
```

### APIBeamResult

| Field | Type | Description |
|:------|:-----|:------------|
| `id` | `Int` | Beam index |
| `section` | `String` | Section designation |
| `flexure_ratio` | `Float64` | Mu / ϕMn |
| `shear_ratio` | `Float64` | Vu / ϕVn |
| `ok` | `Bool` | Passes all checks |

```@docs
APIBeamResult
```

### APIFoundationResult

| Field | Type | Description |
|:------|:-----|:------------|
| `id` | `Int` | Foundation index |
| `length_ft` | `Float64` | Footing length |
| `width_ft` | `Float64` | Footing width |
| `depth_ft` | `Float64` | Footing depth |
| `bearing_ratio` | `Float64` | Bearing pressure / capacity |
| `ok` | `Bool` | Passes all checks |

```@docs
APIFoundationResult
```

### APIVisualization

| Field | Type | Description |
|:------|:-----|:------------|
| `nodes` | `Vector{APIVisualizationNode}` | Node positions and displacements |
| `frame_elements` | `Vector{APIVisualizationFrameElement}` | Frame element data with section geometry |
| `sized_slabs` | `Vector{APISizedSlab}` | Slab boundary and thickness |
| `deflected_slab_meshes` | `Vector{APIDeflectedSlabMesh}` | Deflected slab surface meshes |
| `suggested_scale_factor` | `Float64` | Suggested displacement magnification |
| `max_displacement_ft` | `Float64` | Maximum displacement in the model |

```@docs
APIVisualization
APIVisualizationNode
APIVisualizationFrameElement
APISizedSlab
APIDeflectedSlabMesh
```

### APIError

| Field | Type | Description |
|:------|:-----|:------------|
| `status` | `String` | `"error"` |
| `error` | `String` | Error type |
| `message` | `String` | Human-readable message |
| `traceback` | `String` | Stack trace (debug mode only) |

```@docs
APIError
```

## Limitations & Future Work

- All dimensions in the output are imperial (ft, in, lb); metric output is planned.
- Visualization data is optional and controlled by the `SS_ENABLE_VISUALIZATION` environment variable.
- The schema is versioned implicitly; explicit API versioning (`/v1/design`) is planned.
