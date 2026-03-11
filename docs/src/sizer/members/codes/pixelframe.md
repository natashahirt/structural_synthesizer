# PixelFrame Design

> ```julia
> using StructuralSizer
> sec = generate_pixelframe_catalog(fc_values=[40.0], A_s_values=[226.0], d_ps_values=[150.0])[1]
> Mu = pf_flexural_capacity(sec; E_s=200_000.0, f_py=1615.0)
> Pu = pf_axial_capacity(sec; E_s=200_000.0)
> carbon = pf_carbon_per_meter(sec)
> ```

## Overview

The PixelFrame module implements a novel structural system using pixel-based cross-sections with variable material assignment. PixelFrame members use fiber-reinforced concrete (FRC) with post-tensioning tendons, enabling optimized material distribution across the cross-section.

The module covers axial capacity, flexural capacity, deflection analysis (with multiple methods and cracking regimes), tendon deviation forces, embodied carbon estimation, and per-pixel material optimization.

Source: `StructuralSizer/src/members/codes/pixelframe/*.jl`

## Key Types

### Design Types

```@docs
PixelFrameDesign
```

`PixelFrameDesign` is a mutable struct representing a fully designed PixelFrame member:

| Field | Description |
|:------|:------------|
| `section` | The `PixelFrameSection` geometry and material |
| `pixel_length` | Length of each pixel along the member |
| `n_pixels` | Number of pixels along the span |
| `pixel_materials` | Per-pixel material assignments |
| `tendon_deviation` | Tendon deviation force result |

### Deflection Regime

```@docs
DeflectionRegime
```

`@enum DeflectionRegime` classifies the section behavior under load:

| Value | Description |
|:------|:------------|
| `UNCRACKED` | Section is fully uncracked |
| `CRACKED` | Section is cracked |
| `LINEAR_ELASTIC_UNCRACKED` | Linear elastic, no cracking |
| `LINEAR_ELASTIC_CRACKED` | Linear elastic after cracking |
| `NONLINEAR_CRACKED` | Nonlinear behavior post-cracking |

### Checker & Cache

```@docs
PixelFrameChecker
```

`PixelFrameChecker <: AbstractCapacityChecker` for optimization:

| Field | Description |
|:------|:------------|
| `E_s_MPa` | Tendon elastic modulus (MPa) |
| `f_py_MPa` | Tendon yield strength (MPa) |
| `γ_c` | Partial safety factor for concrete |
| `min_depth_mm` | Minimum section depth (mm) |
| `min_width_mm` | Minimum section width (mm) |

```@docs
PixelFrameCapacityCache
```

Stores precomputed capacities: `Pu`, `Mu`, `Vu`, `depth_mm`, `width_mm`, `obj_coeffs`.

## Functions

### Axial Capacity

```@docs
pf_axial_capacity
```

`pf_axial_capacity(s::PixelFrameSection; E_s, ϕ_compression)` — axial capacity of the PixelFrame section considering the concrete compressive strength and prestress contribution.

### Flexural Capacity

```@docs
pf_flexural_capacity
```

`pf_flexural_capacity(s::PixelFrameSection; E_s, f_py, Ω, max_iter)` — flexural capacity using strain compatibility analysis. The tendon stress increment is computed iteratively, accounting for the nonlinear stress-strain relationship of prestressing steel. FRC tensile contribution (from `fR1`, `fR3`) is included in the tension zone.

### Deflection

```@docs
pf_deflection
```

`pf_deflection(s, L, w_or_M; method, E_s, f_py, support)` — deflection calculation with multiple methods:

- `PFSimplified` — simplified elastic calculation using effective moment of inertia
- `PFThirdPointLoad` — third-point loading configuration
- `PFSinglePointLoad` — single midspan point load

The calculation identifies the governing `DeflectionRegime` and uses the appropriate stiffness for that regime.

### Tendon Deviation

```@docs
pf_tendon_deviation_force
```

`pf_tendon_deviation_force(design, V_max; d_ps_support, f_ps, μ_s)` — computes the transverse force from tendon deviation at harping points. This is critical for PixelFrame members where the tendon profile creates uplift forces at deviation points.

### Embodied Carbon

```@docs
pf_carbon_per_meter
```

`pf_carbon_per_meter(s::PixelFrameSection)` — embodied carbon per meter of member length (kgCO₂/m). Sums the concrete, fiber, and tendon contributions based on pixel volumes and material ECC (embodied carbon coefficients).

```@docs
pf_concrete_ecc
```

`pf_concrete_ecc(fc′)` — returns the embodied carbon coefficient for concrete as a function of compressive strength. Higher-strength concretes have higher ECC due to increased cement content.

### Per-Pixel Design

```@docs
pixel_volumes
```

`pixel_volumes(design::PixelFrameDesign)` — computes the volume of concrete in each pixel, used for carbon and cost calculations.

```@docs
assign_pixel_materials
```

`assign_pixel_materials(governing, n_pixels, pixel_demands, material_pool, checker; symmetric)` — assigns materials to individual pixels based on local demands. Pixels with higher demands get higher-strength materials; pixels with lower demands can use weaker (lower-carbon) materials. The `symmetric` flag enforces material symmetry about midspan.

## Implementation Details

### Flexural Capacity Algorithm

The flexural capacity calculation uses an iterative strain compatibility approach:

1. Assume a neutral axis depth `c`
2. Compute concrete compressive force using Whitney stress block
3. Compute tendon stress from strain compatibility: `fps = fpe + Δfps` where `Δfps` depends on the tendon strain increment
4. Add FRC tensile contribution from fibers in the tension zone: `Tf = fFtu × Af_tension`
5. Iterate on `c` until force equilibrium is achieved
6. Compute `Mn = ΣF × arm`

The FRC tensile strength in the tension zone uses `fFtu = fR3/3` from the fib Model Code 2010.

### Deflection Regimes

The deflection calculation transitions between regimes based on the applied moment relative to cracking moment:

- `Ma < Mcr`: uncracked (`Ie = Ig`)
- `Ma ≥ Mcr`: cracked, using Bischoff-type effective moment of inertia
- For high loads: nonlinear cracked behavior with reduced stiffness

### Carbon Optimization

The per-pixel material assignment enables embodied carbon optimization by using only as much material strength as each pixel needs. Interior pixels under low stress can use lower-strength (lower-carbon) concrete, while critical pixels use higher-strength mixes. This is a form of functionally graded material (FGM) design.

## Options & Configuration

```julia
checker = PixelFrameChecker(
    E_s_MPa = 200_000.0,
    f_py_MPa = 1615.0,
    γ_c = 1.5,
    min_depth_mm = 200.0,
    min_width_mm = 200.0
)
```

PixelFrame sections use SI units (mm, MPa) throughout, unlike the US-customary units in the AISC and ACI modules.

## Limitations & Future Work

- Only `:Y`, `:X2`, and `:X4` layup types are implemented; other topologies are under development.
- Long-term creep and shrinkage effects on FRC are not modeled.
- Fire resistance of PixelFrame sections is not addressed.
- Connection design (pixel-to-pixel, member-to-member) is not included.
- Fatigue under cyclic loading is not considered.
- The carbon optimization uses a greedy per-pixel assignment; a global optimization (e.g., MIP over pixel materials) could yield better results.
