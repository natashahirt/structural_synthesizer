# Design Types & Parameters

> ```julia
> using StructuralSynthesizer
> params = DesignParameters(
>     loads = GravityLoads(floor_LL = 50.0psf, roof_LL = 20.0psf),
>     materials = MaterialOptions(concrete = NWC_4000, steel = A992_Steel),
>     floor = FlatPlateOptions(method = DDM()),
> )
> modified = with(params; fire_rating = 2.0)
> ```

## Overview

Design types define the inputs to and outputs from the structural design pipeline. `DesignParameters` encapsulates all user-configurable options — loads, materials, floor system, member types, fire rating, and optimization objective. `BuildingDesign` wraps the structure with all design results, summary statistics, and metadata.

## Key Types

```@docs
DesignParameters
MaterialOptions
FoundationParameters
DisplayUnits
BuildingDesign
SlabDesignResult
ColumnDesignResult
BeamDesignResult
FoundationDesignResult
PunchingDesignResult
StripReinforcementDesign
DesignSummary
```

## Functions

```@docs
with
compare_designs
```

## Implementation Details

### DesignParameters

`DesignParameters` is the master configuration struct with the following fields:

| Field | Type | Description |
|:------|:-----|:------------|
| `name` | `String` | Design name / identifier |
| `description` | `String` | Optional description |
| `loads` | `GravityLoads` | Floor, roof, and grade loading |
| `materials` | `MaterialOptions` | Material selections for concrete, rebar, steel, timber |
| `fire_rating` | `Float64` | Required fire resistance in hours (drives ACI 216.1 checks) |
| `fire_protection` | `FireProtection` | Fire protection coating type for steel members (ignored for concrete) |
| `columns` | `Union{ColumnOptions, Nothing}` | Member sizing options for columns (`nothing` → defaults by material/type) |
| `beams` | `Union{BeamOptions, Nothing}` | Member sizing options for beams (`nothing` → defaults by material/type) |
| `floor` | `Union{AbstractFloorOptions, Nothing}` | Floor system options (`nothing` → defaults to `FlatPlateOptions()`) |
| `tributary_axis` | `Union{Nothing, Symbol, NTuple{2,Float64}}` | Override tributary partitioning (default: `nothing` = auto) |
| `foundation_options` | `Union{FoundationParameters, Nothing}` | Foundation sizing parameters (`nothing` → skip foundation sizing) |
| `collinear_grouping` | `Bool` | When `true`, detect collinear members sharing a node with aligned direction and assign a shared group\_id before sizing (default `false`) |
| `deflection_limit` | `Symbol` | Deflection limit (`:L_240`, `:L_360`, `:L_480`) |
| `optimize_for` | `Symbol` | Optimization objective: `:weight`, `:carbon`, `:cost` |
| `load_combinations` | `Vector{LoadCombination}` | Load combinations per ASCE 7 §2.3.1 |
| `pattern_loading` | `Symbol` | Pattern loading mode (currently `:none` by default; see `generate_load_patterns`) |
| `diaphragm_mode` | `Symbol` | Diaphragm stiffness model |
| `diaphragm_E` | `Union{typeof(1.0u"Pa"), Nothing}` | Diaphragm elastic modulus (when `diaphragm_mode` is enabled) |
| `diaphragm_ν` | `Float64` | Diaphragm Poisson’s ratio |
| `default_frame_E` | `typeof(1.0u"Pa")` | Default frame elastic modulus (pre-sizing) |
| `default_frame_G` | `typeof(1.0u"Pa")` | Default frame shear modulus (pre-sizing) |
| `default_frame_ρ` | `typeof(1.0u"kg/m^3")` | Default frame density (pre-sizing) |
| `column_I_factor`, `beam_I_factor` | `Float64` | Stiffness reduction factors per ACI 318-11 §10.10.4.1 |
| `max_iterations` | `Int` | Maximum design iterations |
| `display_units` | `DisplayUnits` | Imperial or metric formatting |

### MaterialOptions

Groups material selections:
- `concrete` — `Concrete` material for RC members
- `rebar` — `RebarSteel` material
- `steel` — `StructuralSteel` for steel members
- `timber` — `Timber` material
- `slab`, `column`, `beam` — per-element material overrides

### FoundationParameters

| Field | Description |
|:------|:------------|
| `soil` | Soil type and bearing capacity |
| `options` | Foundation type options |
| `concrete` | Foundation concrete |
| `rebar` | Foundation rebar |
| `pier_width` | Minimum pier width |
| `min_depth` | Minimum footing depth |
| `group_tolerance` | Demand similarity for grouping (default 0.15) |

### BuildingDesign

`BuildingDesign{T,A,P}` is the complete output of `design_building`:

| Field | Description |
|:------|:------------|
| `structure` | The `BuildingStructure` (snapshot of designed state) |
| `params` | `DesignParameters` used |
| `slabs` | `Dict{Int, SlabDesignResult}` |
| `columns` | `Dict{Int, ColumnDesignResult}` |
| `beams` | `Dict{Int, BeamDesignResult}` |
| `foundations` | `Dict{Int, FoundationDesignResult}` |
| `summary` | `DesignSummary` |
| `asap_model` | Solved Asap model |
| `created` | Timestamp |
| `compute_time_s` | Wall-clock time |

### DesignSummary

| Field | Description |
|:------|:------------|
| `concrete_volume` | Total concrete volume |
| `steel_weight` | Total structural steel weight |
| `rebar_weight` | Total rebar weight |
| `timber_volume` | Total timber volume |
| `embodied_carbon` | Total kgCO₂e |
| `cost_estimate` | Estimated cost |
| `all_checks_pass` | `Bool` — all members adequate |
| `critical_element` | Element with highest demand/capacity ratio |
| `critical_ratio` | Governing demand/capacity ratio |

### `with` Helper

The `with(params; kwargs...)` function creates a modified copy of `DesignParameters` with specified fields changed, leaving all other fields unchanged. This is useful for parameter studies:

```julia
base = DesignParameters(loads = office_loads)
study = [with(base; fire_rating = r) for r in [1.0, 1.5, 2.0]]
```

## Options & Configuration

### DisplayUnits

`DisplayUnits` controls how results are formatted in reports and summaries. Two presets are available:
- `imperial` — feet, inches, kips, psi
- `metric` — meters, millimeters, kN, MPa

## Limitations & Future Work

- `cost_estimate` uses simplified unit rates; detailed cost estimation with regional pricing is planned.
- `load_combinations` default to ASCE 7 §2.3.1; ASD combinations and Eurocode combinations are planned.
