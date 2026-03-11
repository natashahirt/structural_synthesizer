# Vault Analysis

> ```julia
> using StructuralSizer
> opts = VaultOptions(lambda_bounds=(0.05, 0.15), thickness_bounds=(0.05u"m", 0.20u"m"))
> result = size_floor(Vault(), 8.0u"m", 0.5u"kPa", 2.0u"kPa"; options=opts)
> result.rise            # final arch rise (after elastic shortening)
> result.thrust_dead     # horizontal thrust per unit width
> is_adequate(result)    # stress + deflection + convergence
> ```

## Overview

The vault module implements Haile's analytical method for unreinforced parabolic
vaults using three-hinge arch theory with elastic shortening correction.  The
analysis computes stresses and thrusts for both symmetric (full-span) and
asymmetric (half-span live) loading, and iterates to find the equilibrium rise
that accounts for axial shortening of the arch.

**Source:** `StructuralSizer/src/slabs/codes/vault/haile_unreinforced.jl`

## Key Types

- `VaultAnalysisMethod` — abstract type for vault analysis method selection.

See also `Vault`, `HaileAnalytical`, `ShellFEA`,
`VaultResult`, and `VaultOptions` in [Slab Types & Options](../../types.md).

## Functions

```@docs
vault_stress_symmetric
vault_stress_asymmetric
solve_equilibrium_rise
parabolic_arc_length
get_vault_properties
vault_volume_per_area
```

## Implementation Details

### Three-Hinge Parabolic Arch Theory

The vault is modeled as a three-hinge parabolic arch under uniform distributed
load.  For a span ``L``, rise ``f``, and thickness ``t``:

**Symmetric loading** (dead + live on full span):
- Horizontal thrust: ``H = \frac{w L^2}{8 f}``
- Maximum compressive stress at crown: ``\sigma = H / (t \cdot b)``

where ``w`` is the total load per unit area and ``b`` is the tributary depth.

**Asymmetric loading** (dead on full span, live on half span):
- Produces bending moments in the arch due to the antisymmetric live load
  component
- `vault_stress_asymmetric` computes the maximum combined stress including both
  axial and flexural effects
- Often governs for moderate live-to-dead ratios

### Elastic Shortening Iteration

The `solve_equilibrium_rise` function iterates to find the equilibrium rise
considering axial shortening of the arch:

1. Compute thrust and arc length for current rise
2. Calculate axial shortening: ``\Delta L = \frac{H \cdot S}{E \cdot A}``
   where ``S`` is arc length and ``A = t \cdot b``
3. Reduce rise to account for shortening
4. Repeat until convergence (within `deflection_limit`)

The result reports `converged` status and iteration count in the
`convergence_check` field.

### Geometry Functions

- `parabolic_arc_length(span, rise)`: Arc length of the parabolic intrados,
  computed analytically
- `intrados(x, span, rise)`: Height of the inner surface at position ``x``
- `extrados(x, span, rise, thickness)`: Height of the outer surface
- `get_vault_properties(span, rise, thickness, trib_depth, rib_depth, rib_apex_rise)`:
  Returns arc length, shell volume, and rib volumes for material takeoff

### Vault Sizing Pipeline

The `_size_span_floor(::Vault, ...)` function:

1. Resolves rise from lambda (rise-to-span ratio) or explicit value
2. Optionally searches for minimum thickness via `_find_min_thickness`
3. Calls `solve_equilibrium_rise` for the final geometry
4. Evaluates symmetric and asymmetric stresses
5. Checks stress ratio, deflection, and convergence
6. Returns `VaultResult` with full geometry and check results

### NLP Optimization

The `VaultNLPProblem` (in `slabs/optimize/`) wraps the vault analysis for
continuous optimization of rise and/or thickness.  See
[Slab Optimization](../../optimize.md) for details.

## Options & Configuration

See `VaultOptions` in [Slab Types & Options](../../types.md) for full field documentation.

Rise specification (four mutually exclusive forms):

| Parameter | Description |
|:----------|:------------|
| `lambda_bounds` | Rise-to-span ratio bounds, e.g., `(0.05, 0.15)` |
| `rise_bounds` | Explicit rise bounds in length units |
| `lambda` | Fixed rise-to-span ratio |
| `rise` | Fixed rise value |

Additional options:

| Parameter | Default | Description |
|:----------|:--------|:------------|
| `thickness_bounds` | `(0.03m, 0.30m)` | Shell thickness bounds |
| `thickness` | `nothing` | Fixed thickness (skips optimization) |
| `allowable_stress` | ``0.25 f'_c`` | Maximum compressive stress |
| `deflection_limit` | ``L/360`` | Deflection limit |
| `check_asymmetric` | `true` | Include half-span live load case |
| `rib_depth` | `0.0` | Depth of stiffening ribs |
| `rib_apex_rise` | `0.0` | Rise of rib at apex |
| `finishing_load` | `0.0 kPa` | Additional finishing dead load |

## Limitations & Future Work

- **ShellFEA** analysis method is a placeholder—no FE validation is implemented.
- Only parabolic vault geometry is supported; catenary, circular, and pointed
  profiles require different analytical solutions.
- Reinforced vault design (with rebar or FRC) is not implemented.
- Lateral thrust from vaults is reported but must be resolved externally (by
  tie beams, buttresses, or the surrounding frame).
- Thermal effects and creep are not considered in the analysis.
