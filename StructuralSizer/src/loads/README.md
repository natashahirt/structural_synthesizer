# Loads Module

## Current Scope — Gravity Only

The loads infrastructure handles **gravity loads** (dead, live, superimposed dead)
through three components:

| File | Purpose |
|:-----|:--------|
| `combinations.jl` | `LoadCombination` struct, ASCE 7-22 presets, `factored_pressure` / `envelope_pressure` |
| `gravity.jl` | `GravityLoads` struct with occupancy presets (`office_loads`, `residential_loads`, …) |
| `pattern_loading.jl` | ACI 318 pattern load utilities (checkerboard, adjacent spans) |

`LoadCombination` already carries fields for all ASCE 7 load types
(D, L, Lr, S, R, **W**, **E**), but the W and E factors are currently inert —
no lateral load source exists yet to multiply them against.

---

## Expanding to Lateral Loads (Wind / Seismic)

When the implementation moves beyond gravity, here is the minimal path:

### 1. Define lateral load inputs

Create a `LateralLoads` struct (or extend a broader `BuildingLoads` wrapper):

```julia
struct LateralLoads{P}
    wind_pressure::P           # e.g. 20.0psf on windward face (MWFRS)
    seismic_base_shear::P      # or a per-story distribution
end
```

Wire this into `DesignParameters` alongside `GravityLoads`.

### 2. Apply lateral forces to the Asap model

In `StructuralSynthesizer/src/analyze/asap/utils.jl`, add a function
(e.g. `_apply_lateral_loads!`) that places **nodal lateral forces** at each
floor-diaphragm level. This is where `combo.W` and `combo.E` first get real
values to multiply.

The existing `sync_asap!` pipeline would call this after
`_create_cell_tributary_loads!`.

### 3. Use the keyword-argument `factored_pressure` at lateral call sites

The full overload already exists:

```julia
factored_pressure(combo; D=dead, L=live, W=wind_demand)
envelope_pressure(combos; D=dead, L=live, W=wind)
```

No changes to `combinations.jl` are needed.

### 4. Column / beam sizing picks up lateral demands automatically

Columns are sized from Asap member forces. Once lateral loads are in the
model, demands increase and columns size up through the existing
`sync_asap! → size → sync_asap!` pipeline loop. No sizing logic changes.

### 5. Slab unbalanced moments (wind-governed punching)

If frame sway creates unbalanced moments at slab-column joints, feed them
into the punching shear check via the existing `Mux` / `Muy` inputs in
`codes/aci/punching.jl`.

### 6. Multi-case analysis

Wind introduces **directional** load cases (+X, −X, +Y, −Y) that can't be
enveloped as a single scalar the way gravity combos can. You'll need:

- Separate Asap solves per lateral direction
- Per-member demand envelopes (max Pu, max Mu, max Vu across all cases)
- Sign-aware combination (0.9D + 1.0W can produce net uplift)

### What already works and doesn't need changes

- `LoadCombination` struct — has W, E fields ✅
- `factored_pressure` / `envelope_pressure` — full-keyword versions exist ✅
- `DesignParameters.load_combinations` — accepts any combo vector ✅
- `design_building` pipeline — stages are composable ✅
- Snapshot / restore — unaffected by lateral loads ✅

The hardest part will be computing the wind pressures themselves
(MWFRS per ASCE 7 Chapter 27/28), not wiring them into the existing
infrastructure.
