# PixelFrame Implementation Status

Implementation of PixelFrame FRC + external post-tensioning (EPT) section sizing,
based on the Wongsittikan (2024) thesis and the original `Pixelframe.jl` package.

Reference: `reference/Wongsittikan-pitipatw-smbt-arch-2024-thesis (1).pdf`

---

## ✅ Fully Implemented

### Geometry (`pixelframe_geometry.jl`, `pixelframe_section.jl`)
- Y-section (3-arm, 120° spacing) — beams
- X2-section (2-arm, 180° spacing) — slabs, thin members, columns
- X4-section (4-arm, 90° spacing) — columns, biaxial members
- `Asap.CompoundSection` / `SolidSection` representation with accurate polygon geometry
- `make_pixelframe_section` dispatcher for all three layups
- Section properties: area, centroid, moment of inertia via `Asap.jl`

### Axial Capacity (`axial.jl`)
- ACI 318-19 §22.4: `Po = 0.85 f'c Ag`
- 0.8 × Po reduction factor (ACI 318-19 Table 22.4.2.1)
- ϕ = 0.65 for compression-controlled members

### Flexural Capacity (`flexure.jl`)
- ACI 318-19 §22.4 rectangular stress block with β₁
- Polygon clipping (`Asap.sutherland_hodgman`) for non-rectangular compression zone
- Tendon stress at ultimate (`fps`) via strain compatibility
- ϕ factor per ACI 318-19 Table 21.2.2 (tension/compression/transition)

### Shear Capacity (`frc_shear.jl` in `codes/fib/`)
- fib MC2010 §7.7-5 FRC shear model
- Linear `fFtuk` model using fR1 and fR3
- Corrected `k = min(1 + √(200/d), 2)` size-effect factor
- `V_Rd,Fmin` floor value

### Deflection — Simplified (`deflection.jl`, `PFSimplified`)
- Cracking moment `Mcr` — ACI 318-19 §24.2.3.5
- Decompression moment `Mdec` for EPT beams
- Cracked moment of inertia `Icr` via `Asap.depth_from_area` + `OffsetSection`
- Effective moment of inertia `Ie` — modified Branson's equation for EPT (Ng & Tan 2006):
  `Ie = k³ Ig + (1 − k³) Icr` where `k = (Mcr − Mdec) / (Ma − Mdec)`
- Immediate deflection under uniform load: `Δ = 5wL⁴ / (384 Ec Ie)`
- Serviceability check against ACI 318-19 Table 24.2.2 limits (L/240, L/360, etc.)
- Default method — fast, non-iterative, suitable for design-level sizing

### Deflection — Full Ng & Tan (`deflection.jl`, `PFThirdPointLoad` / `PFSinglePointLoad`)
- Full iterative model from Ng & Tan (2006) Part I with 4 deflection regimes:
  - `LINEAR_ELASTIC_UNCRACKED`: Ma ≤ Mcr — iterate on fps only
  - `LINEAR_ELASTIC_CRACKED`: Mcr < Ma ≤ Mecl — nested fps + Icr loops
  - `NONLINEAR_CRACKED`: Mecl < Ma ≤ My — same nested loops
  - Beyond My → returns Inf (failure)
- Element properties computation (`pf_element_properties`): Ω, K1, K2, Mcr, Mecl, My
- Cracked bond reduction factor Ωc — 4-branch formula (Eq. 21)
- Concrete strain from Hognestad parabola (quadratic solver)
- Eccentricity and tendon depth updates (second-order effects)
- Load pattern dispatch:
  - `PFThirdPointLoad()` — two-point loading at L/3
  - `PFSinglePointLoad()` — single midspan load at L/2
- `pf_deflection_curve` — moment-deflection curves for research validation
- Toggle via `method` keyword: `pf_deflection(s, L, M; method=PFThirdPointLoad())`

### Material Model (`materials/frc.jl`, `materials/types.jl`)
- `FiberReinforcedConcrete` type with fR1, fR3, dosage, fiber_ecc
- Regression functions `fc′_dosage2fR1` and `fc′_dosage2fR3`

### Embodied Carbon (`carbon.jl`)
- `pf_carbon_per_meter`: concrete + fiber + steel tendon contributions
- `fiber_ecc = 1.4 kgCO₂e/kg` default

### Catalog & Optimization (`pixelframe_catalog.jl`, `checker.jl`, `options.jl`, `api.jl`)
- `generate_pixelframe_catalog`: Cartesian sweep of L_px × t × L_c × λ × f'c × dosage × A_s × f_pe × d_ps
- `PixelFrameChecker` — `AbstractCapacityChecker` with cached capacities
- `PixelFrameBeamOptions` / `PixelFrameColumnOptions` for MIP optimization
- `MinCarbon` / `MinWeight` / `MinCost` objectives
- Minimum bounding-box constraint (`min_depth_mm`, `min_width_mm`) for punching shear

### Per-Pixel Material Variation (`pixel_design.jl`)
- `PixelFrameDesign` struct: governing section + `Vector{FiberReinforcedConcrete}` per pixel
- `validate_pixel_divisibility`: error if span is not a multiple of pixel length (default 500 mm)
- `assign_pixel_materials`: post-MIP relaxation — for each pixel position, selects the
  lowest-carbon material that satisfies the local demand while keeping geometry/tendon fixed
- Symmetric enforcement: pairs of symmetric pixel positions use the stronger material
- `pixel_volumes`: per-material volume computation from pixel design
- `pixel_carbon`: total embodied carbon summing per-pixel contributions
- `build_pixel_design`: convenience function combining validation + assignment
- `pixel_length` field on `PixelFrameBeamOptions` / `PixelFrameColumnOptions` (default 500 mm, Unitful)
- `MemberBase.pixel_design` field in `StructuralSynthesizer` for per-member storage

### Tendon Deviation Axial Force (`tendon_deviation.jl`)
- `TendonDeviationResult` struct: θ, P_horizontal, V_max, N_friction, N_additional, μ_s
- `pf_tendon_deviation_force(design, V_max; d_ps_support, f_ps, μ_s)`:
  Computes the additional clamping force needed at deviator points for
  friction-based shear transfer between pixels.
- Tendon angle θ from eccentricity change over pixel length
- Horizontal PT component: `A_ps × f_ps × cos(θ)`
- Friction-required normal force: `V_max / μ_s` (default μ_s = 0.3)
- Additional force: `N_friction − P_horizontal` (negative = PT alone suffices)
- Stored in `PixelFrameDesign.tendon_deviation` (mutable field)
- Reference: Wongsittikan (2024) — `designPixelframe.jl`, lines 474–536

---

## Intentional Differences from Original `Pixelframe.jl`

| Item | Original | Our Implementation | Reason |
|------|----------|--------------------|--------|
| Shear `k` factor | `min(√(200/d), 2)` (typo from thesis) | `min(1 + √(200/d), 2)` | Correct per fib MC2010 §7.7-5 |
| `V_Rd,Fmin` floor | Not implemented | Implemented | Enhancement per fib MC2010 |
| Unit handling | Bare `Float64` in mm/N/MPa | `Unitful.jl` quantities | Safer, catches dimension errors at compile time |
| Geometry engine | Custom polygon math | `Asap.jl` `CompoundSection` | Reuses validated structural analysis library |
| Quadratic solver | `PolynomialRoots.roots` | Analytical quadratic formula | No extra dependency; exact same result |
| Per-pixel assignment | Greedy search (midspan out) | Post-MIP carbon-sorted relaxation | MIP guarantees global optimality for governing section; per-pixel is a fast post-step |
