# Tributary Cache

> ```julia
> key = tributary_cache_key(:two_way, axis)
> cached = get_cached_column_tributary(struc, key, col_idx)
> isnothing(cached) && cache_column_tributary!(struc, key, col_idx, result)
> ```

## Overview

The `TributaryCache` avoids recomputing Voronoi tributary areas and strip geometries during iterative design. Since tributary polygons depend only on geometry (not on section sizes or loads), they can be computed once and reused across multiple sizing iterations. The cache is keyed by spanning behavior and tributary axis.

## Key Types

```@docs
TributaryCache
TributaryCacheKey
CellTributaryResult
ColumnTributaryResult
```

## Functions

See the accessor and cache management functions below.

## Implementation Details

### TributaryCacheKey

A `TributaryCacheKey` is a `(behavior::Symbol, axis_hash::UInt64)` pair that uniquely identifies a tributary computation configuration:
- `behavior` — `:one_way`, `:two_way`, or `:beamless` (determines how loads are distributed)
- `axis_hash` — hash of the tributary axis direction vector

### CellTributaryResult

Stores the tributary computation results for a single cell:
- `edge_tributaries::Vector{TributaryPolygon}` — tributary polygons along each cell edge (for beam load collection)
- `strip_geometry::Union{PanelStripGeometry, Nothing}` — column strip / middle strip split for DDM/EFM (ACI 318-11 §13.6.4)

### ColumnTributaryResult

Stores the tributary area results for a single column vertex:
- `total_area` — total tributary area (for initial column sizing)
- `by_cell::Dict{Int, AreaQuantity}` — tributary area contribution from each adjacent cell
- `polygons::Dict{Int, Vector{NTuple{2, LengthQuantity}}}` — Voronoi polygon vertices per cell

### Cache Structure

The `TributaryCache` contains two top-level dictionaries:

| Field | Key | Value | Description |
|:------|:----|:------|:------------|
| `edge` | `TributaryCacheKey` | `Dict{Int, CellTributaryResult}` | Cell index → edge tributaries |
| `vertex` | `Int` | `Dict{Int, ColumnTributaryResult}` | Vertex index → column tributaries |

Plus `edge_computed` and `vertex_computed` sets tracking which keys have been fully computed.

### When Caches Are Invalidated

Caches are invalidated by `clear_geometry_caches!` when the skeleton geometry changes (e.g., vertex positions modified). During normal design iterations where only section sizes change, caches remain valid and are reused.

## Limitations & Future Work

- The cache assumes static geometry; dynamic remeshing during design would require cache invalidation hooks.
- Cache keys use axis hashing, which has a theoretical (extremely unlikely) collision risk for different axis directions.
