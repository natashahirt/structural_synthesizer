# AISC 360-16: W Shapes

> ```julia
> using StructuralSizer
> w = get_w_section("W14X22")
> mat = A992()
> ϕMn = get_ϕMn(w, mat; Lb=12u"ft", Cb=1.0)
> ϕPn = get_ϕPn(w, mat, 12u"ft")
> println("ϕMn = $ϕMn, ϕPn = $ϕPn")
> ```

## Overview

This module implements AISC 360-16 capacity checks for doubly-symmetric I-shapes (W, S, M, HP sections). It covers flexure (Chapter F), compression (Chapter E), shear (Chapter G), torsion (AISC Design Guide 9), P-M interaction (Chapter H), slenderness classification (Table B4.1), and moment amplification (Appendix 8).

The `AISCChecker` type dispatches capacity calculations based on section type. For `ISymmSection`, the functions in this module are called.

Source: `StructuralSizer/src/members/codes/aisc/i_symm/*.jl`

## Key Types

```@docs
AISCChecker
```

`AISCChecker <: AbstractCapacityChecker` carries LRFD resistance factors and design preferences:

| Field | Default | Description |
|:------|:--------|:------------|
| `ϕ_b` | 0.9 | Flexure resistance factor |
| `ϕ_c` | 0.9 | Compression resistance factor |
| `ϕ_v` | 1.0 | Shear resistance factor (rolled shapes) |
| `ϕ_t` | 0.9 | Tension resistance factor |
| `deflection_limit` | `nothing` | L/Δ limit (e.g. 360.0 for L/360) |
| `max_depth` | `Inf` | Maximum section depth constraint |
| `prefer_penalty` | 1.0 | Penalty multiplier for non-preferred sections |

## Functions

### Flexure (AISC §F2, §F3, §F6)

```@docs
get_ϕMn
```

`get_ϕMn(s::ISymmSection, mat; Lb, Cb=1.0, axis=:strong, ϕ=0.9)` — returns the design flexural strength.

```@docs
get_Mn
```

`get_Mn(s::ISymmSection, mat; Lb, Cb=1.0, axis=:strong)` — returns the nominal flexural strength. For strong-axis bending, this is the minimum of:

1. **Yielding (F2-1):** `Mp = Fy × Zx`
2. **Lateral-torsional buckling (F2-2, F2-3, F2-4):** depends on `Lb` relative to `Lp` and `Lr`
3. **Flange local buckling (F3-1, F3-2):** for noncompact or slender flanges

For weak-axis bending (§F6): `Mp = min(Fy × Zy, 1.6 × Fy × Sy)` with FLB reductions for noncompact/slender flanges.

```@docs
get_Lp_Lr
```

`get_Lp_Lr(s, mat)` — limiting unbraced lengths for LTB:
- `Lp = 1.76 ry √(E/Fy)` (F2-5)
- `Lr` from Eq. F2-6 using `rts`, `J`, `Sx`, `ho`

```@docs
get_Fcr_LTB
```

`get_Fcr_LTB(s, mat, Lb; Cb)` — elastic LTB critical stress (F2-4):

`Fcr = Cb π²E / (Lb/rts)² × √(1 + 0.078 (J c)/(Sx ho) (Lb/rts)²)`

### Compression (AISC §E3, §E4, §E7)

```@docs
get_ϕPn
```

`get_ϕPn(s::ISymmSection, mat, L; axis=:weak, ϕ=0.90)` — design compressive strength.

```@docs
get_Pn
```

`get_Pn(s::ISymmSection, mat, L; axis=:weak)` — nominal compressive strength. Considers:
- Flexural buckling (E3) about the governing axis
- Flexural-torsional buckling (E4) for doubly-symmetric sections
- Local buckling reductions via Q factor (E7) for slender elements

Critical stress per E3-2/E3-3:
- `Fy/Fe ≤ 2.25`: `Fcr = 0.658^(Fy/Fe) × Fy`
- `Fy/Fe > 2.25`: `Fcr = 0.877 × Fe`

```@docs
get_Fe_flexural
```

`get_Fe_flexural(s, mat, L; axis)` — Euler buckling stress (E3-4): `Fe = π²E / (KL/r)²`

```@docs
get_Fe_torsional
```

`get_Fe_torsional(s, mat, Lz)` — torsional/flexural-torsional buckling stress (E4-4).

### Shear (AISC §G2)

```@docs
get_ϕVn
```

`get_ϕVn(s::ISymmSection, mat; axis=:strong, ϕ=nothing)` — design shear strength. Default `ϕ = 1.0` for rolled shapes per G2.1(a).

```@docs
get_Vn
```

`get_Vn(s::ISymmSection, mat; axis=:strong)` — nominal shear strength: `Vn = 0.6 Fy Aw Cv1` (G2-1).

```@docs
get_Cv1
```

`get_Cv1(s, mat; kv=5.34, rolled=true)` — web shear coefficient per G2.1. For rolled shapes with `h/tw ≤ 2.24√(E/Fy)`, `Cv1 = 1.0`.

### Torsion (AISC Design Guide 9)

```@docs
design_w_torsion
```

`design_w_torsion(s, mat, Tu, Vu, Mu, L; load_type)` — full torsion design check per DG9. Returns torsional stresses and interaction check.

```@docs
torsional_stresses_ksi
```

Computes normal and shear stresses from pure torsion, warping torsion, and bending using DG9 Eqs. 4.1, 4.2a, 4.3a.

```@docs
check_torsion_yielding
```

`check_torsion_yielding(σ_b, σ_w, τ_b, τ_t, τ_ws, Fy; φ=0.90)` — von Mises interaction per DG9 §4.7.1.

### Slenderness Classification (Table B4.1)

```@docs
get_slenderness
```

`get_slenderness(s::ISymmSection, mat)` — classifies flange and web as compact, noncompact, or slender for flexure per Table B4.1b. Returns slenderness ratios and limit values:
- Flange (Case 10): `λp = 0.38√(E/Fy)`, `λr = 1.0√(E/Fy)`
- Web (Case 15): `λp = 3.76√(E/Fy)`, `λr = 5.70√(E/Fy)`

```@docs
get_compression_factors
```

`get_compression_factors(s, mat)` — computes the Q factor (Qs × Qa) for compression per Table B4.1a / §E7.

```@docs
is_compact
```

`is_compact(s, mat)` — returns `true` if both flange and web are compact for flexure.

### P-M Interaction (AISC §H1)

See [AISC — Generic](generic.md) for `check_PM_interaction` and `check_PMxMy_interaction`, which apply to all section types including W shapes.

## Implementation Details

### Flexure Algorithm

The flexure calculation first checks LTB against `Lp` and `Lr` (F2-5, F2-6), then checks FLB against Table B4.1b limits. The governing `Mn` is the minimum of all applicable limit states, capped by `Mp`.

For the elastic LTB critical stress (F2-4), the constant `c = 1.0` for doubly-symmetric I-shapes. The `rts` parameter is precomputed and stored on the section, following AISC Commentary Eq. C-F2-15.

### Compression Algorithm

Compression considers both flexural buckling (E3) about the weak axis (governing for most W shapes) and flexural-torsional buckling (E4). For sections with slender elements, the Q-factor approach (E7) reduces the effective area. The implementation uses iterative convergence for Qa when web effective width depends on Fcr.

### Torsion

W shapes are open sections with low torsional rigidity. The implementation follows DG9 Case 1 (distributed torque) and Case 3 (concentrated torque), computing warping and St. Venant torsional stresses at critical locations along the member length. The normalized warping function `Wno` and warping statical moment `Sw1` are computed from DG9 Appendix C equations.

## Options & Configuration

The `AISCChecker` constructor accepts all fields as keyword arguments:

```julia
checker = AISCChecker(ϕ_b=0.9, ϕ_c=0.9, ϕ_v=1.0, deflection_limit=360.0, max_depth=24.0)
```

Set `deflection_limit` to `nothing` to skip deflection checks. The `prefer_penalty` multiplies the objective coefficient for non-preferred sections (> 1.0 penalizes them in optimization).

## Limitations & Future Work

- Singly-symmetric I-shapes (channels, WT) are not supported — only doubly-symmetric.
- Web local buckling under flexure (§F4/F5 for noncompact/slender webs) is not implemented for the general case.
- Built-up I-sections with different `ϕ_v` are not distinguished from rolled shapes.
- No composite beam design (AISC §I).
