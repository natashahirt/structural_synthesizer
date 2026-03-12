# NDS Timber Design

> ```julia
> using StructuralSizer
> checker = NDSChecker()
> glulam = GlulamSection(5.125u"inch", 12.0u"inch")
> # NDS checker is currently a stub — full implementation pending
> ```

## Overview

This module provides the framework for NDS (National Design Specification for Wood Construction) capacity checks for timber members. Currently, only the checker interface is defined as a stub — the full NDS 2018 AWC implementation is planned for future work.

Source: `StructuralSizer/src/members/codes/nds/checker.jl`

## Key Types

```@docs
NDSChecker
```

`NDSChecker <: AbstractCapacityChecker` defines the basic design parameters for NDS checks:

| Field | Default | Description |
|:------|:--------|:------------|
| `CD` | 1.0 | Load duration factor |
| `wet_service` | `false` | Wet service condition flag |
| `high_temperature` | `false` | High temperature flag |
| `repetitive` | `false` | Repetitive member factor flag |
| `incised` | `false` | Incised treatment flag |

## Functions

The following `AbstractCapacityChecker` interface functions are declared but raise errors at runtime:

```@docs
is_feasible
```

`is_feasible(::NDSChecker, ...)` — not yet implemented. Raises an error.

```@docs
precompute_capacities!
```

`precompute_capacities!(::NDSChecker, ...)` — not yet implemented. Raises an error.

## Implementation Details

The `NDSChecker` stores adjustment factors that will be used to modify reference design values per NDS §4.3. The NDS design approach multiplies reference design values by a series of adjustment factors:

- `CD` — load duration factor (NDS §4.3.2)
- `CM` — wet service factor (from `wet_service` flag)
- `Ct` — temperature factor (from `high_temperature` flag)
- `Cr` — repetitive member factor (from `repetitive` flag)
- `Ci` — incising factor (from `incised` flag)

Additional factors (beam stability `CL`, column stability `CP`, volume `CV`, etc.) would be computed from member geometry and section properties.

## Options & Configuration

```julia
checker = NDSChecker(CD=1.15, repetitive=true)  # Short-term load, repetitive
```

The `CD` factor should be set based on the governing load combination:
- 0.9 for permanent loads
- 1.0 for occupancy live load (10 years)
- 1.15 for construction load (2 months)
- 1.25 for snow load (7 days)
- 1.6 for wind/seismic (10 minutes)
- 2.0 for impact (instantaneous)

## Limitations & Future Work

The NDS module is a **stub** — no capacity calculations are implemented. The planned scope includes:

- **Flexure:** Adjusted bending stress ``F'_b = F_b\,C_D\,C_M\,C_t\,C_L\,C_F\,C_{fu}\,C_i\,C_r\,C_V`` vs. ``f_b = M/S``
- **Compression:** Column stability factor ``C_P`` per NDS §3.7, Euler buckling ``F_{cE} = 0.822\,E'_{min}/(L_e/d)^2``
- **Tension:** Adjusted tension ``F'_t`` vs. ``f_t = P/A``
- **Shear:** Adjusted shear ``F'_v`` vs. ``f_v = 3V/(2bd)`` for rectangular sections
- **Combined loading:** NDS §3.9 interaction equations for combined bending + axial
- **Connections:** Not planned for initial implementation
- **Material database:** NDS Supplement reference design values for sawn lumber and glulam
