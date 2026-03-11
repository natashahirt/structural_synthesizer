# Slab Validation

> ```julia
> panels = validate_and_split_slab(cell_indices, get_centroid, get_boundary)
> grid = build_cell_grid(cell_indices, get_centroid)
> rects = decompose_to_rectangles(cell_indices, get_centroid)
> groups = group_by_connectivity(cell_indices, get_neighbors)
> ```

## Overview

Slab validation ensures that cell groups form valid slab geometries for structural analysis. The DDM (ACI 318-11 §13.6) and EFM (ACI 318-11 §13.7) require rectangular panel layouts. Non-rectangular groupings (L-shapes, T-shapes) are decomposed into rectangular sub-panels, and disconnected groups are split into separate slabs.

**Source:** `StructuralSynthesizer/src/geometry/slab_validation.jl`

## Key Types

```@docs
CellGrid
```

## Functions

```@docs
validate_and_split_slab
decompose_to_rectangles
group_by_connectivity
build_cell_grid
```

## Implementation Details

### validate_and_split_slab

`validate_and_split_slab(cell_indices, get_centroid_fn, get_boundary_fn)` is the main entry point:

1. **Connectivity check** — `group_by_connectivity` ensures all cells are connected. Disconnected groups become separate slabs.
2. **Rectangularity check** — for each connected group, checks whether cells form a rectangular grid.
3. **Decomposition** — non-rectangular groups are decomposed into rectangular sub-panels via `decompose_to_rectangles`.
4. Returns a `Vector{Vector{Int}}` of cell index groups, each forming a valid rectangular slab.

### decompose_to_rectangles

`decompose_to_rectangles(cell_indices, get_centroid_fn)` breaks L-shapes, T-shapes, and other non-rectangular cell groups into the minimum number of rectangular panels:

1. Builds a `CellGrid` from cell centroid positions
2. Identifies the largest rectangular sub-grid
3. Recursively decomposes the remainder
4. Returns rectangular panels suitable for DDM/EFM analysis

### group_by_connectivity

`group_by_connectivity(cell_indices, get_neighbors_fn)` performs a flood-fill traversal to identify connected components among the given cell indices. Two cells are connected if they share an edge (not just a corner).

### CellGrid

`CellGrid` provides a structured 2D grid representation of cells:

| Field | Description |
|:------|:------------|
| `grid` | 2D array mapping (row, col) to cell index |
| `cell_positions` | Map from cell index to (row, col) position |
| `row_coords` | Sorted Y coordinates of grid rows |
| `col_coords` | Sorted X coordinates of grid columns |

The grid is constructed by snapping cell centroids to a regular grid with tolerance for floating-point positions.

### Usage in Slab Analysis

The DDM and EFM analysis methods require rectangular panels:
- **DDM** (ACI 318-11 §13.6) — needs regular column grid with defined column and middle strips
- **EFM** (ACI 318-11 §13.7) — needs frame lines along principal directions with clear span definitions

Slab validation ensures that irregular building layouts (L-shaped floors, setbacks) are properly decomposed before analysis.

## Limitations & Future Work

- Decomposition minimizes the number of rectangular panels but does not optimize for structural efficiency (e.g., minimizing moment transfer at panel boundaries).
- Cells must have centroids that align to a regular grid within tolerance; highly irregular cell shapes may fail grid construction.
