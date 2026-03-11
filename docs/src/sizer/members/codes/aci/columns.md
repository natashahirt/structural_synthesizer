# ACI 318: Column Design

> ```julia
> using StructuralSizer
> col = RCColumnSection(b=16u"inch", h=16u"inch", bar_size=9, n_bars=8, cover=1.5u"inch")
> mat = NWC_4000()
> diagram = generate_PM_diagram(col, mat)
> ur = utilization_ratio(diagram, 200u"kip", 100u"kip*ft")
> ```

## Overview

This module implements ACI 318 provisions for reinforced concrete column design, including P-M interaction diagrams (§22.4), biaxial bending checks (§22.4), and slenderness effects (§6.6). It supports both rectangular and circular column cross-sections.

The central data structure is the `PMInteractionDiagram`, which stores the full interaction surface from pure compression to pure tension. Capacity checks interpolate on this diagram to determine whether a given (Pu, Mu) pair is within the capacity envelope.

Source: `StructuralSizer/src/members/codes/aci/columns/*.jl`

## Key Types

### P-M Interaction Diagram

```@docs
PMInteractionDiagram
```

`PMInteractionDiagram{S, M}` stores the interaction diagram for a section `S` with material `M`:

| Field | Description |
|:------|:------------|
| `section` | The column section (`RCColumnSection` or `RCCircularSection`) |
| `material` | Concrete material |
| `points` | Vector of `(ϕPn, ϕMn)` tuples forming the interaction curve |
| `control_points` | Dictionary mapping `ControlPointType` to indices |

```@docs
PMDiagramRect
```

Type alias: `PMInteractionDiagram{RCColumnSection}` — for rectangular columns.

```@docs
PMDiagramCircular
```

Type alias: `PMInteractionDiagram{RCCircularSection}` — for circular columns.

### Control Points

```@docs
ControlPointType
```

`@enum ControlPointType` identifies key points on the interaction diagram:

| Value | Description |
|:------|:------------|
| `PURE_COMPRESSION` | ϕPn_max = ϕ × 0.80 × P0 (tied) or ϕ × 0.85 × P0 (spiral) |
| `MAX_COMPRESSION` | Maximum unreduced compression capacity |
| `FS_ZERO` | Extreme tension fiber strain = 0 |
| `FS_HALF_FY` | Extreme tension steel at fy/2 |
| `BALANCED` | Simultaneous concrete crushing and steel yielding (εs = εy) |
| `TENSION_CONTROLLED` | εt = 0.005 (transition point for φ = 0.90) |
| `PURE_BENDING` | Pu = 0, maximum moment capacity |
| `PURE_TENSION` | ϕTn = ϕ × As_total × fy |
| `INTERMEDIATE` | Interpolated points between control points |

### Checker & Cache

```@docs
ACIColumnChecker
```

`ACIColumnChecker <: AbstractCapacityChecker` carries design parameters:

| Field | Description |
|:------|:------------|
| `include_slenderness` | Whether to apply slenderness magnification |
| `include_biaxial` | Whether to check biaxial bending |
| `α_biaxial` | Exponent for PCA load contour method |
| `fy_ksi` | Rebar yield strength (ksi) |
| `Es_ksi` | Steel elastic modulus (ksi) |
| `max_depth` | Maximum column dimension constraint |

```@docs
ACIColumnCapacityCache
```

`ACIColumnCapacityCache` stores precomputed interaction diagrams for each catalog section.

## Functions

### P-M Diagram Generation

```@docs
generate_PM_diagram
```

`generate_PM_diagram(section, mat; n_intermediate=20)` — generates the full P-M interaction diagram by strain compatibility analysis. The algorithm:

1. Compute strain profiles for each control point (c from 0 to ∞)
2. At each neutral axis depth `c`, compute bar strains from linear strain distribution
3. Sum bar forces and moments about the centroid
4. Apply strength reduction factor `φ` per §21.2.2 (varies from 0.65/0.75 to 0.90)
5. Add `n_intermediate` points between control points for smooth interpolation

### Capacity Checks

```@docs
check_PM_capacity
```

`check_PM_capacity(diagram, Pu, Mu)` — returns `true` if the (Pu, Mu) point lies inside the interaction diagram.

```@docs
capacity_at_axial
```

`capacity_at_axial(diagram, Pu)` — returns the moment capacity `ϕMn` at a given axial load level by interpolating on the diagram.

```@docs
capacity_at_moment
```

`capacity_at_moment(diagram, Mu)` — returns the axial capacity `ϕPn` at a given moment level.

```@docs
utilization_ratio
```

`utilization_ratio(diagram, Pu, Mu)` — returns a scalar utilization ratio (≤ 1.0 is adequate). Computed by finding the intersection of the load ray with the interaction curve.

### Biaxial Bending (ACI §22.4)

```@docs
bresler_reciprocal_load
```

`bresler_reciprocal_load(Pnx, Pny, P0)` — Bresler reciprocal load method:

`1/Pn = 1/Pnx + 1/Pny - 1/P0`

where `Pnx` = nominal axial capacity at eccentricity `ex` only, `Pny` at `ey` only, `P0` = pure axial capacity. Valid when `Pn/P0 ≥ 0.1`.

```@docs
pca_load_contour
```

`pca_load_contour(Mux, Muy, φMnox, φMnoy, Pu, φPn, φP0; β=0.65)` — PCA load contour method:

`(Mux/φMnox)^α + (Muy/φMnoy)^α ≤ 1.0`

where `α ≈ 1.5` for typical columns (the `β` parameter maps to `α` via `log 0.5 / log β`).

```@docs
check_biaxial_capacity
```

`check_biaxial_capacity(diagram_x, diagram_y, Pu, Mux, Muy; method=:contour, α=1.5)` — biaxial check using either `:bresler` or `:contour` method. Requires separate P-M diagrams for each axis.

### Slenderness (ACI §6.6)

```@docs
slenderness_ratio
```

`slenderness_ratio(section, geometry)` — computes `kLu/r` per §10.10.1.2 (ACI 318-14) / §6.6.4 (ACI 318-19). Uses `r = 0.3h` for rectangular sections and `r = 0.25D` for circular sections.

```@docs
magnification_factor_nonsway
```

`magnification_factor_nonsway(Pu, Pc; Cm=1.0)` — moment magnification factor for nonsway frames (§10.10.6.3 / §6.6.4.5):

`δns = Cm / (1 - Pu/(0.75 Pc)) ≥ 1.0`

where `Pc = π²EI/(kLu)²` is the Euler buckling load using the effective stiffness `EI`.

```@docs
magnify_moment_nonsway
```

`magnify_moment_nonsway(section, mat, geometry, Pu, M1, M2; βdns, transverse_load)` — complete nonsway moment magnification. Computes `EI` per §6.6.4.4.4:

`EI = (0.2 Ec Ig + Es Ise) / (1 + βdns)` or `EI = 0.4 Ec Ig / (1 + βdns)`

Then computes `Pc`, `Cm`, and `δns`.

### Sway Properties

```@docs
SwayStoryProperties
```

`SwayStoryProperties` stores story-level data for sway magnification:

| Field | Description |
|:------|:------------|
| `ΣPu` | Total factored vertical load in the story |
| `ΣPc` | Total Euler buckling load for all columns in the story |
| `Vus` | Story shear |
| `Δo` | First-order interstory drift |
| `lc` | Story height |

```@docs
stability_index
```

`stability_index(story)` — stability index Q per §10.10.5.2 / §6.6.4.4.1:

`Q = ΣPu × Δo / (Vus × lc)`

If `Q ≤ 0.05`, the story is classified as nonsway.

## Implementation Details

### Strain Compatibility

The P-M diagram is generated using a full strain compatibility analysis at each neutral axis depth `c`. The concrete compressive force uses the Whitney stress block (`a = β₁ c`), and each bar's stress is determined from its strain (assuming elastic-perfectly-plastic steel behavior):

`εsi = εcu × (c - di) / c`

where `εcu = 0.003`, `di` is the distance from the extreme compression fiber to bar `i`. Forces are summed and moments taken about the plastic centroid.

### Strength Reduction Factor φ

The φ factor varies linearly between the compression-controlled value (0.65 for tied, 0.75 for spiral) and the tension-controlled value (0.90) based on the extreme tension steel strain:

- `εt ≤ εy`: φ = 0.65 (tied) or 0.75 (spiral) — compression controlled
- `εy < εt < 0.005`: linear interpolation — transition zone
- `εt ≥ 0.005`: φ = 0.90 — tension controlled

### Maximum Compression Cap

ACI limits the maximum axial load to prevent pure compression failure:
- Tied columns: `ϕPn_max = ϕ × 0.80 × (0.85 fc′(Ag - Ast) + fy Ast)`
- Spiral columns: `ϕPn_max = ϕ × 0.85 × (0.85 fc′(Ag - Ast) + fy Ast)`

### Biaxial Method Selection

The PCA load contour method (`:contour`) is generally preferred for design because it uses the moment interaction directly. The Bresler reciprocal load method (`:bresler`) is simpler but less accurate for low axial loads (`Pn/P0 < 0.1`).

## Options & Configuration

```julia
checker = ACIColumnChecker(
    include_slenderness = true,
    include_biaxial = true,
    α_biaxial = 1.5,
    fy_ksi = 60.0,
    Es_ksi = 29000.0,
    max_depth = 36.0
)
```

When `include_slenderness = false`, the checker skips moment magnification (appropriate when second-order effects are captured in the analysis). When `include_biaxial = false`, only uniaxial P-M checks are performed.

## Limitations & Future Work

- Walls (high aspect ratio columns) are not specifically addressed; the same P-M approach is used.
- Second-order analysis (§6.7/§6.8) is handled in the structural analysis module, not here.
- Confinement effects (spirals, ties) are reflected in φ factors but not in material stress-strain curves.
- No design for development length or lap splices.
- The sway magnification currently uses the simplified stability index method; the direct analysis method (§6.6.4) is not fully implemented.
