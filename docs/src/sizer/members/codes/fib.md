# fib MC2010: FRC Shear

> ```julia
> using StructuralSizer
> using Unitful
> VRd = frc_shear_capacity(bw=300u"mm", d=500u"mm", fc′=40u"MPa",
>     fR1=4.0u"MPa", fR3=3.5u"MPa", ρ_l=0.015, σ_cp=0.0u"MPa", γ_c=1.5)
> ```

## Overview

This module implements the shear capacity calculation for fiber-reinforced concrete (FRC) members per the fib Model Code 2010 (§7.7.3.2.2). FRC includes steel or synthetic fibers that provide post-cracking tensile resistance, contributing to shear capacity without conventional stirrups.

The implementation is primarily used with `PixelFrameSection` members, where FRC materials provide the shear resistance through fiber bridging across diagonal cracks.

Source: `StructuralSizer/src/members/codes/fib/frc_shear.jl`

## Functions

```@docs
frc_shear_capacity
```

Two methods are available:

### Generic Method

`frc_shear_capacity(; bw, d, fc′, fR1, fR3, ρ_l, σ_cp, γ_c)` — computes the design shear resistance per fib MC2010 §7.7.3.2.2:

| Parameter | Description |
|:----------|:------------|
| `bw` | Web width |
| `d` | Effective depth |
| `fc′` | Characteristic compressive strength |
| `fR1` | Residual flexural tensile strength at CMOD = 0.5 mm |
| `fR3` | Residual flexural tensile strength at CMOD = 2.5 mm |
| `ρ_l` | Longitudinal reinforcement ratio |
| `σ_cp` | Average compressive stress from prestress or axial load |
| `γ_c` | Partial safety factor for concrete (typically 1.5) |

### PixelFrame Method

`frc_shear_capacity(s::PixelFrameSection; E_s, γ_c, shear_ratio)` — convenience method that extracts material properties (`fR1`, `fR3`, `fc′`) from the section's `FiberReinforcedConcrete` material and computes the effective reinforcement ratio from the tendon area and section geometry.

## Implementation Details

### fib MC2010 §7.7.3.2.2 — FRC Shear Resistance

The shear resistance of FRC members without conventional shear reinforcement is:

```math
V_{Rd,F} = \left[\frac{0.18}{\gamma_c} k \left(100 \rho_1 \left(1 + 7.5 \frac{f_{Ftuk}}{f_{ctk}}\right) f_{ck}\right)^{1/3} + 0.15 \sigma_{cp}\right] b_w d
```

where:

- \(k = 1 + \sqrt{200/d} \le 2.0\) — size effect factor (d in mm)
- \(\rho_1 = A_s/(b_w d) \le 0.02\) — longitudinal reinforcement ratio
- \(f_{Ftuk} = f_{R3}/3\) — characteristic ultimate residual tensile strength
- \(f_{ctk} = 0.7 \times 0.3 \times f_{ck}^{2/3}\) — characteristic tensile strength (for \(f_{ck}\) in MPa)
- \(f_{ck}\) — characteristic compressive strength

The minimum shear resistance is:

```math
V_{Rd,F,\min} = \left(0.035 k^{3/2} \sqrt{f_{ck}} + 0.15 \sigma_{cp}\right) b_w d
```

The fiber contribution enters through the term `7.5 fFtuk/fctk`, which amplifies the effective longitudinal reinforcement ratio. This captures the fiber bridging effect that provides post-cracking tensile resistance across diagonal shear cracks.

### Residual Strengths fR1 and fR3

The residual flexural tensile strengths are measured from standardized three-point bending tests on notched beams (EN 14651):

- `fR1` at CMOD = 0.5 mm — serviceability residual strength
- `fR3` at CMOD = 2.5 mm — ultimate residual strength (used for shear)

Higher fiber dosages produce higher `fR` values. The implementation accepts these directly or derives them from fiber dosage using empirical correlations stored in the `FiberReinforcedConcrete` material type.

## Options & Configuration

The main configurable parameter is `γ_c` (partial safety factor):
- `γ_c = 1.5` for persistent and transient design situations (default)
- `γ_c = 1.2` for accidental design situations

The `shear_ratio` parameter in the PixelFrame method scales the shear contribution for sections where only a fraction of the web carries shear.

## Limitations & Future Work

- Only Level I approximation (simplified) is implemented per §7.7.3.2.2. Level II (variable angle truss model) and Level III (detailed approaches) are not implemented.
- No consideration of combined torsion + shear for FRC members.
- The fiber contribution model assumes steel fibers; synthetic macro-fiber performance may differ.
- No fatigue or cyclic loading provisions for FRC shear.
- Punching shear for FRC slabs is not implemented.
