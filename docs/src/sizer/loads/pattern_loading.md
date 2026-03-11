# Pattern Loading

> ```julia
> using StructuralSizer
> requires_pattern_loading(100.0psf, 80.0psf)   # L/D = 1.25 → true
> patterns = generate_load_patterns(3)            # 5 patterns for 3 spans
> qu = factored_pattern_loads(patterns[2], 100.0psf, 50.0psf)
> ```

## Overview

Pattern loading is required by ACI 318-11 §13.7.6 for continuous slab and frame systems when the live-to-dead load ratio exceeds 0.75. By selectively loading and unloading spans, pattern loading finds the governing moment and shear envelopes that full uniform loading may underestimate — particularly negative moments at interior supports.

This module generates load patterns, checks the L/D trigger, and computes factored load intensities for use with any stiffness-based analysis method (EFM, FEA).

## Key Types

```@docs
PatternLoadCase
```

### Enumeration Values

| Case | Description | Typical Governing Effect |
|:-----|:------------|:------------------------|
| `FULL_LOAD` | All spans loaded with D + L | Maximum positive moment, deflection |
| `CHECKERBOARD_ODD` | Odd spans D + L, even spans D only | Maximum positive moment in odd spans |
| `CHECKERBOARD_EVEN` | Even spans D + L, odd spans D only | Maximum positive moment in even spans |
| `ADJACENT_PAIRS` | Adjacent span pairs loaded (3+ spans) | Maximum negative moment at interior supports |

## Functions

```@docs
requires_pattern_loading
generate_load_patterns
apply_load_pattern
factored_pattern_loads
pattern_case_name
```

### requires\_pattern\_loading

Checks the ACI 318-11 §13.7.6 trigger:

```julia
requires_pattern_loading(qD, qL)  # → true if qL/qD > 0.75
```

Typical results:

| Occupancy | L (psf) | D (psf) | L/D | Required? |
|:----------|:--------|:--------|:----|:----------|
| Office | 50 | ~100 | 0.50 | No |
| Residential | 40 | ~100 | 0.40 | No |
| Assembly | 100 | ~100 | 1.00 | Yes |
| Storage | 125 | ~100 | 1.25 | Yes |

### generate\_load\_patterns

Generates all required patterns for `n_spans`:

```julia
patterns = generate_load_patterns(3)
# Returns 5 patterns (vectors of :dead_plus_live / :dead_only):
#   1. [:dead_plus_live, :dead_plus_live, :dead_plus_live]  — Full
#   2. [:dead_plus_live, :dead_only, :dead_plus_live]       — Checkerboard odd
#   3. [:dead_only, :dead_plus_live, :dead_only]            — Checkerboard even
#   4. [:dead_plus_live, :dead_plus_live, :dead_only]       — Adjacent 1-2
#   5. [:dead_only, :dead_plus_live, :dead_plus_live]       — Adjacent 2-3
```

For `n_spans < 3`, adjacent-pair patterns are omitted (only full + 2 checkerboard).

### apply\_load\_pattern

Converts a pattern to load intensities per span:

```julia
loads = apply_load_pattern(pattern, qD, qL)
# :dead_plus_live → qD + qL
# :dead_only      → qD
```

### factored\_pattern\_loads

Computes **factored** (ultimate) pressures per span within the governing combination:

```julia
qu = factored_pattern_loads(pattern, qD, qL)
# :dead_plus_live → max(1.2D + 1.6L, 1.4D)
# :dead_only      → 1.2D
```

Uses ASCE 7 §2.3.1 Combination 2 (1.2D + 1.6L) for loaded spans. Unloaded spans use 1.2D (not 1.4D) because all spans share the same load combination — only the live load placement varies.

### pattern\_case\_name

Returns a human-readable string for each case:

```julia
pattern_case_name(CHECKERBOARD_ODD)  # → "Checkerboard (odd spans loaded)"
```

## Implementation Details

- **ACI 318-11 §13.7.6**: Pattern loading is triggered when `L/D > 0.75`. The code uses the unfactored service-level ratio. When triggered, the analysis must consider all pattern cases and take the envelope of resulting forces.
- **ACI 318-11 §9.2.1 / ASCE 7 §2.3.1**: Factored loads within each pattern case use Combination 2 (`1.2D + 1.6L`). The `max(1.2D + 1.6L, 1.4D)` check in `factored_pattern_loads` ensures Combination 1 governs for spans with very low live load.
- **Adjacent pairs**: For 3+ spans, loading two adjacent spans maximizes the negative moment at the shared interior support. The module generates `n_spans - 1` adjacent-pair cases.
- **Applicability**: Pattern loading applies to flat plate (RC and PT), voided plate, one-way continuous slabs, and skip joist systems — any continuous system analyzed by DDM or EFM.
- **Envelope computation**: The calling code (DDM or EFM analysis) runs all patterns and takes the maximum absolute value at each section to construct the moment/shear envelope.

## Limitations & Future Work

- **Skip patterns**: For systems with many spans (>5), exhaustive pattern generation grows linearly. A skip-one-span heuristic could reduce the pattern count while capturing the dominant effects.
- **Moving loads**: The current approach covers uniformly distributed pattern loading only. Concentrated or moving loads (e.g., forklift traffic in storage occupancies) are not modeled.
- **Two-way pattern loading**: The current implementation generates patterns along one direction at a time. True two-way pattern loading (checkerboard in both plan directions simultaneously) would require panel-level load case generation.
