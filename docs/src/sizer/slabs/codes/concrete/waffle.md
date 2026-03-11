# Waffle Slab Design

> ```julia
> using StructuralSizer
> panel = IsoParametricPanel(corners)
> grid  = WaffleRibGrid(panel, 5, 5; solid_head=0.2)
> mods  = modules(grid)   # vector of RibModule cells
> ```

## Overview

The waffle slab module provides geometry generation for waffle (ribbed) slabs on
arbitrary quadrilateral and convex polygonal panels.  Rib lines are generated in
parametric space and mapped to physical coordinates via isoparametric (bilinear)
or Wachspress barycentric transformations.

The module separates geometry from structural design: rib layout, void-former
geometry, and cell enumeration are computed here; structural sizing dispatches
through the general concrete sizing pipeline using ACI 318-11 §9.8 provisions.

**Source:** `StructuralSizer/src/slabs/codes/concrete/waffle/`

## Key Types

- `IsoParametricPanel` — quadrilateral panel defined by four corner vertices, mapped via bilinear shape functions.
- `WaffleRibGrid` — rib layout on an `IsoParametricPanel`, storing rib lines in ξ and η parametric directions plus `RibModule` cells.
- `RibModule` — a single cell between rib lines, with centroid, area, corner coordinates, and `is_solid` flag for solid head zones.
- `WachspressPanel{N}` — general convex N-gon panel using Wachspress barycentric coordinates.
- `WachspressGrid` — rib layout on a `WachspressPanel`, analogous to `WaffleRibGrid` for N-gons.

## Functions

### Isoparametric Geometry

- `shape_functions(ξ, η)` — bilinear shape functions for a quad element.
- `physical_coords(panel, ξ, η)` — map parametric coordinates to physical (x, y).
- `parametric_coords(panel, x, y)` — inverse map via Newton–Raphson iteration.
- `jacobian(panel, ξ, η)` — 2×2 Jacobian matrix of the isoparametric mapping.
- `jacobian_det(panel, ξ, η)` — determinant of the Jacobian (must be positive).
- `panel_area(panel)` — compute the physical area of the panel by integration.
- `min_jacobian_det(panel)` — minimum Jacobian determinant over the panel (quality check).
- `ensure_ccw(pts)` — reorder corner points to counter-clockwise orientation.

### Rib Layout

- `rib_lines_ξ(grid)` — rib polylines in the ξ direction.
- `rib_lines_η(grid)` — rib polylines in the η direction.
- `modules(grid)` — vector of `RibModule` cells between rib lines.
- `grid_summary(grid)` — summary statistics (cell count, area, solid fraction).
- `is_in_solid_head(grid, ξ, η)` — check whether a parametric point falls in a solid head zone.

### Wachspress Coordinates

- `wachspress_weights(panel, x, y)` — Wachspress barycentric weights for a point inside a convex polygon.
- `mean_value_weights(panel, x, y)` — mean value coordinate weights (Floater 2003) as fallback.
- `mean_value_parametric(panel, x, y)` — parametric coordinates via mean value interpolation.
- `is_convex_polygon(pts)` — check whether a polygon is convex.
- `auto_params(panel)` — automatically select parameterization method based on polygon vertex count.

## Implementation Details

### Isoparametric Mapping

For quadrilateral panels, the standard bilinear shape functions map from the
unit square ``[\xi, \eta] \in [0,1]^2`` to physical coordinates:

```math
\mathbf{x}(\xi, \eta) = \sum_{i=1}^{4} N_i(\xi, \eta) \, \mathbf{x}_i
```

where ``N_i`` are the four bilinear shape functions (Hughes 2000, §3.2).  The
Jacobian determinant is checked for positivity to ensure the mapping is
non-degenerate.

Inverse mapping ``(x, y) \to (\xi, \eta)`` uses Newton–Raphson iteration with
a configurable tolerance and maximum iterations.

### Wachspress Barycentric Coordinates

For general convex N-gons, the `WachspressPanel` type uses Wachspress (1975)
barycentric coordinates.  These generalize bilinear coordinates to polygons with
arbitrary vertex count:

```math
w_i = \frac{A_{i-1,i,i+1}}{\prod_{j \neq i} A_{P,j,j+1}}
```

where ``A_{i,j,k}`` is the signed area of triangle ``(i, j, k)`` and ``P`` is
the evaluation point.  Normalized weights give the barycentric coordinates.

For quads, the Wachspress weights reduce to the standard bilinear map; for
pentagons, hexagons, etc., they provide the natural generalization.

Mean value coordinates (Floater 2003) are also implemented as a fallback for
points near polygon edges where Wachspress weights can become singular.

### Rib Layout Generation

Rib lines are generated at uniform parametric intervals in ``\xi`` and ``\eta``
directions.  Each rib line is traced through the parametric domain and mapped to
a polyline in physical space (default 20 sample points per line).

**Solid head zones** at column locations are specified by the `solid_head`
parameter (fraction of the parametric domain from each corner).  Cells within
the solid head region are marked `is_solid = true` in the `RibModule` output.

Cell geometry (centroid, area, corners) is computed from the physical coordinates
of the module boundary.  The shoelace formula gives the physical area of each
4-vertex cell.

### Structural Sizing

Waffle slab sizing uses `min_thickness(::Waffle, ln)` which returns ``l_n/22``
per ACI 318-11 §9.8.  The `_size_span_floor(::Waffle, ...)` function in
`sizing.jl` computes the CIP slab result from the minimum depth.

## Options & Configuration

The `WaffleRibGrid` constructor accepts:

| Parameter | Type | Description |
|:----------|:-----|:------------|
| `panel` | `IsoParametricPanel` | Physical panel geometry |
| `nξ` | `Int` | Number of rib divisions in ξ direction |
| `nη` | `Int` | Number of rib divisions in η direction |
| `solid_head` | `Float64` | Solid zone fraction at corners (0–0.5) |

For Wachspress panels, `WachspressGrid` provides an identical interface but
accepts `WachspressPanel{N}` for N-gon support.

## Limitations & Future Work

- Structural design for waffle ribs (rib flexure, shear at rib-slab junction)
  is not yet implemented—only the minimum depth heuristic is provided.
- Void former volume computation for material takeoff is planned but not
  implemented.
- The module assumes uniform rib spacing; tapered or variable-spacing ribs
  require manual polyline input.
- Non-convex panels are not supported by `WachspressPanel`; irregular panels
  should be decomposed into convex sub-panels.
