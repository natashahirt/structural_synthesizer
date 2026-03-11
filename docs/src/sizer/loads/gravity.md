# Gravity Loads

> ```julia
> using StructuralSizer
> loads = office_loads          # 50 psf LL, 15 psf SDL
> loads.floor_LL               # → 50.0 psf
> custom = GravityLoads(floor_LL = 65.0psf, floor_SDL = 20.0psf)
> ```

## Overview

`GravityLoads` stores unfactored service-level gravity loads for a building. These loads flow through `DesignParameters` → `initialize!` → individual cells, where they are factored by `LoadCombination`s during analysis. Each field accepts any Unitful pressure — mixed units across fields are handled automatically.

## Key Types

```@docs
GravityLoads
```

### Fields

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `floor_LL` | `Pressure` | 80.0 psf | Floor live load |
| `roof_LL` | `Pressure` | 20.0 psf | Roof live load |
| `grade_LL` | `Pressure` | 100.0 psf | Grade / ground floor live load |
| `floor_SDL` | `Pressure` | 15.0 psf | Floor superimposed dead load (finish, MEP, partitions) |
| `roof_SDL` | `Pressure` | 15.0 psf | Roof superimposed dead load (roofing, insulation) |
| `wall_SDL` | `Pressure` | 10.0 psf | Cladding / curtain wall dead load (per area of wall) |

## Presets

All presets follow ASCE 7-22 Table 4.3-1 for minimum uniformly distributed live loads.

| Preset | floor_LL | floor_SDL | roof_LL | Notes |
|:-------|:---------|:----------|:--------|:------|
| `default_loads` | 80 psf | 15 psf | 20 psf | Conservative (includes partition allowance) |
| `office_loads` | 50 psf | 15 psf | 20 psf | Offices (ASCE 7-22 Table 4.3-1) |
| `residential_loads` | 40 psf | 10 psf | 20 psf | One/two-family dwellings |
| `assembly_loads` | 100 psf | 20 psf | 20 psf | Assembly, movable seating |
| `retail_loads` | 100 psf | 15 psf | 20 psf | First floor / ground retail |
| `storage_loads` | 125 psf | 15 psf | 20 psf | Light storage |
| `parking_loads` | 40 psf | 5 psf | 20 psf | Passenger vehicle garages |
| `hospital_loads` | 60 psf | 25 psf | 20 psf | Hospital / institutional |
| `school_loads` | 40 psf | 15 psf | 20 psf | School classrooms |

## Functions

```@docs
load_map
default_loads
office_loads
residential_loads
assembly_loads
retail_loads
storage_loads
parking_loads
hospital_loads
school_loads
```

### load\_map

Builds the floor-group mapping used by `initialize_cells!`:

```julia
mapping = load_map(office_loads)
# → [:grade => (100.0 psf, 15.0 psf),
#    :floor => (50.0 psf, 15.0 psf),
#    :roof  => (20.0 psf, 15.0 psf)]
```

Each entry maps a floor group (`:grade`, `:floor`, `:roof`) to a `(live_load, SDL)` tuple.

## Implementation Details

- **ASCE 7-22 Table 4.3-1**: Live load values match the minimum uniformly distributed live loads specified in the 2022 edition. The `default_loads` preset uses 80 psf as a conservative value that includes a 15 psf partition allowance per ASCE 7-22 §4.3.2.
- **Superimposed dead loads**: SDL values represent non-structural dead loads (floor finish, MEP, partitions, cladding). Self-weight of the structural system (slab, beams, columns) is computed separately from section properties and added during analysis.
- **Unit flexibility**: All fields are `Pressure` (a Unitful type alias). Mixing units is valid:

```julia
GravityLoads(floor_LL = 2.4u"kPa", floor_SDL = 15.0psf)  # SI + imperial
```

- **Grade loads**: The `grade_LL` field applies to slab-on-grade and ground floor slabs. It defaults to 100 psf (light storage/loading dock).
- **Wall SDL**: Applied as a line load along the building perimeter during tributary analysis. Represents cladding, curtain wall, or masonry veneer weight per unit area of wall surface.

## Options & Configuration

Custom loads for parametric studies:

```julia
for ll in [40, 50, 65, 80, 100]
    result = design_building(struc, DesignParameters(
        loads = GravityLoads(floor_LL = Float64(ll) * psf),
    ))
end
```

## Limitations & Future Work

- **No lateral loads**: `GravityLoads` covers only vertical loads. Wind and seismic pressures are not stored here — they enter through `LoadCombination` factors acting on separate lateral analysis results.
- **No occupancy mixing**: Each building uses a single `GravityLoads` instance. Mixed-use buildings (e.g., retail podium + office tower) require manual per-story load assignment or future multi-zone support.
- **Live load reduction**: ASCE 7-22 §4.7 live load reduction is not applied at the load definition level. Reduction factors are applied downstream during tributary analysis.
