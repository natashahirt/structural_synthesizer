# Foundation Types

> ```julia
> using StructuralSizer
> soil = medium_sand
> demand = FoundationDemand(1; Pu=500u"kip", Mux=100u"kip*ft", c1=24u"inch", c2=24u"inch")
> result = design_footing(SpreadFooting(), demand, soil)
> footprint_area(result)  # ft²
> utilization(result)     # bearing utilization ratio
> ```

## Overview

The foundation module provides design for shallow and deep foundation systems.
The abstract hierarchy separates foundation types, soil models, demand inputs,
and result structures with a common interface for volume and utilization queries.

**Source:** `StructuralSizer/src/foundations/`

The hierarchy:

```
AbstractFoundation
├── AbstractShallowFoundation
│   ├── SpreadFooting
│   ├── CombinedFooting
│   ├── StripFooting
│   └── MatFoundation
└── AbstractDeepFoundation
    ├── DrivenPile
    ├── DrilledShaft
    └── Micropile
```

## Key Types

### Abstract Hierarchy

```@docs
AbstractFoundation
AbstractShallowFoundation
AbstractDeepFoundation
```

### Shallow Foundation Types

```@docs
SpreadFooting
CombinedFooting
StripFooting
MatFoundation
```

### Deep Foundation Types

```@docs
DrivenPile
DrilledShaft
Micropile
```

### Soil Model

```@docs
Soil
```

### Soil Presets

```@docs
loose_sand
medium_sand
dense_sand
soft_clay
stiff_clay
hard_clay
```

### Demand

```@docs
FoundationDemand
```

### Result Types

```@docs
AbstractFoundationResult
SpreadFootingResult
CombinedFootingResult
StripFootingResult
MatFootingResult
PileCapResult
```

### Mat Analysis Methods

```@docs
AbstractMatMethod
RigidMat
ShuklaAFM
WinklerFEA
```

## Functions

### Common Interface

```@docs
concrete_volume
steel_volume
footprint_area
footing_length
footing_width
utilization
```

### Design Entry Point

```@docs
design_footing
recommend_foundation_strategy
```

### Type Mapping

```@docs
foundation_type
foundation_symbol
```

## Implementation Details

### Soil Model

The `Soil` struct stores geotechnical parameters:

| Field | Symbol | Description |
|:------|:-------|:------------|
| `qa` | ``q_a`` | Allowable bearing pressure |
| `γ` | ``\gamma`` | Soil unit weight |
| `ϕ` | ``\phi`` | Friction angle |
| `c` | ``c`` | Cohesion |
| `Es` | ``E_s`` | Soil elastic modulus |
| `qs` | ``q_s`` | Unit skin friction (piles) |
| `qp` | ``q_p`` | Unit end bearing (piles) |
| `ks` | ``k_s`` | Modulus of subgrade reaction |

Six preset soils are provided from Bowles (1996) Table 9-1 and ACI 336.2R:

| Preset | ``q_a`` | ``\phi`` | ``k_s`` |
|:-------|:--------|:---------|:--------|
| `loose_sand` | 1.5 ksf | 28° | 30 pci |
| `medium_sand` | 3.0 ksf | 33° | 100 pci |
| `dense_sand` | 5.0 ksf | 38° | 250 pci |
| `soft_clay` | 1.0 ksf | 0° | 30 pci |
| `stiff_clay` | 3.0 ksf | 0° | 150 pci |
| `hard_clay` | 6.0 ksf | 0° | 300 pci |

### Foundation Demand

`FoundationDemand` wraps the column-to-foundation interface:

- Factored loads: ``P_u, M_{ux}, M_{uy}, V_{ux}, V_{uy}``
- Service load: ``P_s`` (for bearing check)
- Column dimensions: ``c_1, c_2`` and shape (`:square`, `:round`)

### Foundation Strategy Recommendation

`recommend_foundation_strategy` computes the coverage ratio:

```math
R = \frac{\sum_i P_{s,i} / q_a}{\text{total footprint}}
```

and recommends `:spread` (R < 0.3), `:strip` (0.3 ≤ R < threshold), or `:mat`
(R ≥ threshold, default 0.5).

### Result Interface

All result types implement a common interface:
- `concrete_volume`: Total concrete volume
- `steel_volume`: Total rebar volume
- `footprint_area`: Plan area of the foundation
- `utilization`: Governing utilization ratio (max of bearing, punching, shear, flexure)

## Options & Configuration

```@docs
SpreadFootingOptions
StripFootingOptions
MatFootingOptions
FoundationOptions
```

`FoundationOptions` is the top-level container that selects code, strategy,
and mat coverage threshold.

Key `SpreadFootingOptions` fields:

| Field | Default | Description |
|:------|:--------|:------------|
| `cover` | 3 in. | Concrete cover to rebar |
| `bar_size` | 5 | Rebar bar designation |
| `pier_shape` | `:square` | Column/pier shape |
| `ϕ_flexure` | 0.90 | Flexure strength reduction factor |
| `ϕ_shear` | 0.75 | Shear strength reduction factor |

`MatFootingOptions` selects the analysis method:

| Method | Description |
|:-------|:------------|
| `RigidMat()` | Rigid mat, uniform pressure (ACI 336.2R §4.2) |
| `ShuklaAFM()` | Shukla approximate flexible method (ACI 336.2R §6.1.2) |
| `WinklerFEA()` | FEA plate on Winkler springs (ACI 336.2R §6.4) |

## Limitations & Future Work

- Deep foundation types (`DrivenPile`, `DrilledShaft`, `Micropile`) are defined
  but have **no design implementations**.
- `CombinedFooting` design is not implemented.
- Mat foundation design assumes a rectangular plan; irregular shapes require
  custom meshing.
- Soil–structure interaction beyond Winkler springs (e.g., elastic half-space,
  finite element soil models) is not supported.
- Lateral load effects on foundations (overturning, sliding) are not checked.
