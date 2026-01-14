# StructuralSizer slabs: adding a new slab / floor type

This folder defines the **slab/floor type system** (`types.jl`) and the **sizing implementations** (`codes/`).

## Do-not-forget (span + units)

- **Span meaning is type-dependent**
  - Many slab types size off the **short span**, but ACI-style **two-way / flat plate / flat slab / PT / waffle** minimum thickness rules use the **long span**.
  - The StructuralSynthesizer side handles this via a small helper (`_sizing_span`) so callers pass the correct span into `size_floor`.
  - When adding a new slab type, document whether `span` means *short*, *long*, or something else (e.g. vault chord length).

- **Units**
  - `size_floor(ft, span, sdl, live; ...)` should accept Unitful inputs.
  - Results should keep units consistent:
    - `self_weight` should be convertible to the same units as the input `sdl`
    - if `volume_per_area` is stored, it should be a **length** (since \(m^3/m^2=m\)) and use the same length unit as thickness/span where practical.

- **Vault geometry constraint**
  - Vault sizing/loads assume a **single rectangular face** in the synthesizer pipeline; non-rectangular faces should error early.

## Quick checklist (do not forget)

- **1) Add the type**
  - Add a new `struct` under the correct hierarchy in `src/slabs/types.jl`
    - Concrete: subtype `AbstractConcreteSlab`
    - Steel: subtype `AbstractSteelFloor`
    - Timber: subtype `AbstractTimberFloor`

- **2) Add symbol ↔ type mapping**
  - Add an entry to `FLOOR_TYPE_MAP` in `src/slabs/types.jl`
  - `FLOOR_SYMBOL_MAP` is derived from `FLOOR_TYPE_MAP` (so you usually only edit the one map).

- **3) Export it**
  - Add the type to the exports in `src/StructuralSizer.jl` (under “Floor System Types”).
  - If you added a new result struct, export that too (under “Floor Result Types”).

- **4) Implement sizing**
  - Create a sizing file in `src/slabs/codes/<category>/` (or reuse an existing one).
  - Add an `include("your_file.jl")` to the appropriate aggregator:
    - Concrete: `src/slabs/codes/concrete/_concrete.jl`
    - Steel: `src/slabs/codes/steel/_steel.jl`
    - Timber: `src/slabs/codes/timber/_timber.jl`
    - Vault: `src/slabs/codes/vault/_vault.jl`
    - Custom: `src/slabs/codes/custom/_custom.jl`
  - Implement a method returning an `AbstractFloorResult`:

```julia
function size_floor(::MyNewSlab, span::L, sdl::F, live::F; material=..., kwargs...) where {L, F}
    # compute thickness/depth, volumes, self weight, etc.
    return CIPSlabResult(thickness, volume_per_area, self_weight)
end
```

- **5) Ensure “interfaces” are consistent (especially for new result types)**
  - If you introduce a new `struct <: AbstractFloorResult`, ensure these functions work:
    - `self_weight(::YourResult)` (default works if field is named `self_weight`)
    - `total_depth(::YourResult)` (add a method if needed)
    - `volume_per_area(::YourResult)` (add a method if needed)
    - `materials(::YourResult)` and `_volume_impl(::YourResult, ::Val{:mat})` if multi-material
  - If the slab changes load transfer behavior, specialize:
    - `load_distribution(::MyNewSlab)`
  - If the slab adds non-gravity effects (e.g. thrust), specialize:
    - `has_structural_effects(::MyNewSlab) = true`
    - `structural_effects(::YourResult)` (and optionally `apply_effects!`)

- **6) Add a test**
  - Add a new test file under `test/` and include it from `test/runtests.jl`.
  - Minimum: smoke-test `size_floor(...)` returns the expected result type and reasonable values.

## Where things are wired together

- **Type definitions + mapping**: `src/slabs/types.jl`
- **Sizing dispatch entry point**: `src/slabs/codes/_codes.jl` (fallback errors if missing)
- **Slabs module include**: `src/slabs/_slabs.jl` (includes `types.jl`, `codes/_codes.jl`, and `tributary/_tributary.jl`)

