# Frame Lines

> ```julia
> fl = FrameLine(:x, columns, trib_width, get_pos, get_width)
> n_spans(fl)               # number of spans
> is_end_span(fl, 1)        # true if span 1 is at the frame end
> perp = perpendicular(:x)  # returns :y
> ```

## Overview

A `FrameLine` represents an ordered sequence of spans along a beam line in one principal direction. Frame lines are the primary input to the Equivalent Frame Method (EFM) per ACI 318-11 §13.7, where each frame line is analyzed as a continuous beam with equivalent column stiffnesses.

Frame lines are extracted from the building skeleton by identifying collinear beam edges and their supporting columns along a given direction.

**Source:** `StructuralSynthesizer/src/geometry/frame_lines.jl`

## Key Types

```@docs
FrameLine
```

## Functions

```@docs
perpendicular
direction_vector
n_spans
n_joints
is_end_span
get_span_supports
```

## Implementation Details

### FrameLine Structure

`FrameLine{T,C}` stores:

| Field | Type | Description |
|:------|:-----|:------------|
| `direction` | `Symbol` | `:x` or `:y` — principal direction |
| `columns` | `Vector{C}` | Column objects along the frame line |
| `tributary_width` | `T` | Tributary width perpendicular to the frame line |
| `span_lengths` | `Vector{T}` | Clear span between column faces |
| `joint_positions` | `Vector{T}` | Positions of column centerlines along the frame line |
| `column_projections` | `Vector{T}` | Column dimension projected onto the frame direction |

### Direction Helpers

- `perpendicular(dir::Symbol)` — returns the orthogonal direction (`:x` → `:y`, `:y` → `:x`)
- `direction_vector(dir::Symbol)` — returns the unit vector `(1,0)` for `:x` or `(0,1)` for `:y`

### Span Queries

- `n_spans(fl)` — number of spans (= number of columns - 1)
- `n_joints(fl)` — number of column joints (= number of columns)
- `is_end_span(fl, span_idx)` — `true` if the span is the first or last span of the frame
- `get_span_supports(fl, span_idx)` — returns the columns at each end of the specified span

### Usage in EFM

The EFM (ACI 318-11 §13.7) uses frame lines to build equivalent frame models:

1. Each frame line becomes a continuous beam
2. Column stiffnesses are computed from actual column dimensions and story heights
3. Equivalent column stiffness accounts for torsional members per §13.7.5
4. Moment distribution uses pattern loading per §13.7.6 when applicable
5. Column and middle strip moments are distributed per §13.6.4

## Limitations & Future Work

- Frame lines must be aligned with principal axes (`:x` or `:y`); skewed frame lines are not supported.
- Frame lines are constructed from collinear beam edges; curved or irregular grid lines require manual specification.
