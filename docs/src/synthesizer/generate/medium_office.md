# Medium Office Generator

> ```julia
> skel = gen_medium_office(30ft, 30ft, 13ft, 3, 3, 5)
> skel = gen_medium_office(30ft, 30ft, 13ft, 3, 3, 5;
>     irregular = :trapezoid, offset = 3ft)
> length(skel.vertices)  # grid points
> length(skel.stories)   # 5 stories + roof
> ```

## Overview

`gen_medium_office` generates a rectangular grid building skeleton for a medium-rise office building. It creates a regular column grid with parametric bay sizes, story heights, and optional geometric irregularities. This is the primary building generator for DOE (Design of Experiments) parametric studies.

**Source:** `StructuralSynthesizer/src/generate/doe/medium_office.jl`

## Functions

```@docs
gen_medium_office
```

## Implementation Details

### Signature

```julia
gen_medium_office(x, y, floor_height, x_bays, y_bays, n_stories;
    irregular = :none, offset = 0.0u"m") → BuildingSkeleton
```

| Argument | Description |
|:---------|:------------|
| `x` | Bay width in X direction (e.g., `30ft`) |
| `y` | Bay width in Y direction |
| `floor_height` | Story height |
| `x_bays` | Number of bays in X |
| `y_bays` | Number of bays in Y |
| `n_stories` | Number of stories |
| `irregular` | Irregularity mode (keyword) |
| `offset` | Irregularity offset magnitude (keyword) |

### Generation Sequence

1. **Create vertices** — grid points at (i·x, j·y, k·floor_height) for all bay and story combinations
2. **Create beam edges** — horizontal edges connecting adjacent vertices within each story, classified as `:beams`
3. **Create column edges** — vertical edges connecting vertices across stories, classified as `:columns`
4. **Mark supports** — ground-level vertices are designated as supports (pinned or fixed)
5. **Detect faces** — `find_faces!` identifies floor, roof, and grade faces from the edge mesh
6. **Build stories** — `rebuild_stories!` groups elements by Z coordinate

### Irregular Modes

| Mode | Description |
|:-----|:------------|
| `:none` | Regular rectangular grid (default) |
| `:shift_x` | Shifts alternating bays in X by `offset` |
| `:shift_y` | Shifts alternating bays in Y by `offset` |
| `:zigzag` | Alternating X and Y shifts creating a zigzag plan |
| `:trapezoid` | Tapers the plan by offsetting vertices linearly, creating a trapezoidal footprint |

Irregularity modes are useful for studying the effect of plan geometry on structural performance and material consumption.

### DOE Integration

The generator is designed for parametric studies:

```julia
designs = []
for x_bay in [25ft, 30ft, 35ft], n_story in [3, 5, 8]
    skel = gen_medium_office(x_bay, x_bay, 13ft, 3, 3, n_story)
    struc = BuildingStructure(skel)
    push!(designs, design_building(struc, params))
end
```

## Options & Configuration

The generator produces a skeleton with default edge and face groups. After generation, the skeleton can be customized:
- Add bracing edges to `groups_edges[:braces]`
- Modify vertex positions for setbacks or irregular plans
- Add or remove faces for openings or atriums

## Limitations & Future Work

- Only rectangular grid plans are supported; radial, hexagonal, or free-form grids require manual skeleton construction.
- Bay sizes are uniform in each direction; variable bay widths require post-generation vertex modification.
- Additional building archetypes (residential tower, warehouse, parking structure) are planned.
