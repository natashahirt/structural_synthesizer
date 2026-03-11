# General Concrete Slab Provisions

> ```julia
> using StructuralSizer
> h_min = min_thickness(FlatPlate(), 7.5u"m")  # ACI Table 9.5(c)
> h_ow  = min_thickness(OneWay(), 5.0u"m"; support=BOTH_ENDS_CONT)
> ```

## Overview

The general concrete slab module provides minimum thickness rules and generic
sizing for cast-in-place concrete slabs.  These provisions apply across all CIP
concrete slab types and serve as starting points for detailed design.

**Source:**
- `StructuralSizer/src/slabs/codes/concrete/min_thickness.jl`
- `StructuralSizer/src/slabs/codes/concrete/sizing.jl`

## Key Types

`PTBanded` — post-tensioned banded slab type. Uses PTI DC20.9 thickness heuristics.

See also `OneWay`, `TwoWay`, `FlatPlate`,
`FlatSlab`, `Waffle`, `SupportCondition`, and
`CIPSlabResult` in [Slab Types & Options](../../types.md).

## Functions

### Minimum Thickness

```@docs
min_thickness
```

### Generic Sizing

`_size_span_floor(slab_type, ...)` — internal dispatch for simplified floor sizing by slab type.

## Implementation Details

### Minimum Thickness — ACI 318-11

Minimum thickness provisions prevent excessive deflection without requiring
detailed deflection calculations.

**Flat plates** (ACI Table 9.5(c), Row 1):

| Condition | Formula |
|:----------|:--------|
| Interior panel | ``l_n / 33`` |
| Exterior panel (discontinuous edge) | ``l_n / 30`` |
| Absolute minimum | 5 in. |

**Flat slabs with drop panels** (ACI Table 9.5(c), Row 2):

| Condition | Formula |
|:----------|:--------|
| Interior panel | ``l_n / 36`` |
| Exterior panel | ``l_n / 33`` |
| Absolute minimum | 4 in. |

**Two-way slabs with beams** (ACI §9.5.3.3, Eq. 9-13):

```math
h = \frac{l_n \left(0.8 + \frac{f_y}{200{,}000}\right)}{36 + 5\beta\left(\alpha_{fm} - 0.2\right)}
```

where ``\beta = l_{\text{long}}/l_{\text{short}}`` and ``\alpha_{fm}`` is the
average beam-to-slab stiffness ratio.

**One-way slabs** (ACI Table 9.5(a)):

| Support condition | Factor |
|:------------------|:-------|
| Simply supported | ``l / 20`` |
| One end continuous | ``l / 24`` |
| Both ends continuous | ``l / 28`` |
| Cantilever | ``l / 10`` |

For Grade 60 rebar (``f_y = 60{,}000`` psi); other grades use the adjustment
factor ``(0.4 + f_y / 100{,}000)``.

**Waffle slabs** (ACI §9.8): ``l_n / 22``

**PT banded slabs** (PTI DC20.9):
- Without drop panels: ``l_n / 45``
- With drop panels: ``l_n / 50``

### Generic Sizing Pipeline

The `_size_span_floor` dispatch provides simplified sizing for each slab type:

- **`FlatPlate` / `FlatSlab`**: Calls `min_thickness`, computes factored loads
  (``1.2D + 1.6L``), builds basic moment analysis, and returns
  `CIPSlabResult`.  For detailed design with iteration, use
  `size_flat_plate!` instead.
- **`TwoWay`**: Uses `min_thickness` with beam stiffness parameters, returns
  `CIPSlabResult`.
- **`OneWay`**: Uses ACI Table 7.3.1.1 (`min_thickness` with support condition),
  returns `CIPSlabResult`.
- **`Waffle`**: Uses ``l_n/22`` per ACI §9.8.
- **`PTBanded`**: Uses PTI DC20.9 heuristic.

All generic sizing functions compute self-weight from ``\rho_c \cdot g \cdot h``
and volume per area equal to the slab thickness.

## Options & Configuration

See `OneWayOptions` in [Slab Types & Options](../../types.md).

The `SupportCondition` enum controls the one-way slab minimum thickness
coefficient:

| Value | Meaning |
|:------|:--------|
| `SIMPLE` | Simply supported |
| `ONE_END_CONT` | One end continuous |
| `BOTH_ENDS_CONT` | Both ends continuous |
| `CANTILEVER` | Cantilever |

## Limitations & Future Work

- The generic `_size_span_floor` for `FlatPlate` / `FlatSlab` is a simplified
  wrapper; the full iterative design uses `size_flat_plate!`.
- Two-way slab `min_thickness` with beams requires ``\alpha_{fm}``; the current
  implementation assumes ``\alpha_{fm} = 0`` (no beams) as default.
- `PTBanded` thickness is heuristic only—full tendon layout and balanced load
  analysis are not implemented.
- Fire rating adjustments per ACI 216.1-14 are handled separately and override
  the code-based minimum when more restrictive.
