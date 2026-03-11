# Size Dispatch

> ```julia
> design = BuildingDesign(struc, params)
> size!(design; max_iterations = 10, convergence_tol = 0.01)
> design.summary.all_checks_pass
> ```

## Overview

`size!` is the top-level sizing dispatcher that runs the pipeline stages built by `build_pipeline`. It iterates through stages, calling each sizing function and optionally re-solving the FEM model, until all stages complete or the maximum iteration count is reached.

## Functions

```@docs
size!
```

## Implementation Details

### Dispatch Logic

`size!(design::BuildingDesign)` performs:

1. Retrieves the pipeline via `build_pipeline(design.params)`
2. For each `PipelineStage`:
   - Calls `stage.fn(design.structure, design.params)`
   - If `stage.needs_sync`, calls `sync_asap!(design.structure; params = design.params)` to update the FEM model
3. After all stages, calls `_update_design_results!(design)` to refresh result summaries

### Floor Type Dispatch

The pipeline stages differ by floor type:

| Floor Type | Slab Sizing | Member Sizing | Foundation Sizing |
|:-----------|:------------|:--------------|:-----------------|
| `FlatPlate` / `FlatSlab` | DDM, EFM, or FEA | Column reconciliation | Optional |
| `OneWay` / `TwoWay` | Per-cell slab design | Iterative beam + column | Optional |
| `CompositeDeck` | Steel deck tables | AISC beam optimization | Optional |
| `Vault` | Shell/analytical | Supporting member sizing | Optional |
| `CLT` / `NLT` / `DLT` | Timber panel design | Timber/steel beam sizing | Optional |

### Convergence

For iterative stages (beam–column sizing), convergence is checked by comparing section assignments between iterations. The loop terminates when:
- No section changes occur between iterations, OR
- `max_iterations` is reached

The `convergence_tol` parameter controls the minimum section size change that counts as a modification.

## Options & Configuration

| Parameter | Description | Default |
|:----------|:------------|:--------|
| `max_iterations` | Maximum sizing iterations | 10 |
| `convergence_tol` | Minimum change threshold | 0.01 |
| `size_foundations` | Whether to include foundation sizing | `true` |
| `verbose` | Print iteration progress | `false` |

## Limitations & Future Work

- Convergence is not formally guaranteed for all building geometries; in rare cases, section oscillation can occur between two close sizes.
- Parallel sizing of independent stories within a single iteration is planned but not yet implemented.
