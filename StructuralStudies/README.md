# StructuralStudies

Parametric studies for structural design optimization research.

## Column Properties Study

**Goal:** Understand how RC column design parameters affect structural capacity
and embodied carbon to inform optimization strategies.

### Running (REPL)

```julia
# from StructuralStudies/ directory
using Pkg; Pkg.activate(".")

# ── Load the study ──
include("src/column_properties/column_parametric_study.jl")

# ── Run sweeps ──
df = sweep()                              # full factorial (~25k sections)
df = material_sweep()                     # f'c × fy × ρ, geometry fixed
df = geometry_sweep()                     # size × AR × shape, material fixed
df = detailing_sweep()                    # cover × arrangement × tie type

# ── Customize ──
df = sweep(sizes=[20, 24], fc=[4.0, 6.0]) # any parameter subset
df = sweep(shapes=[:rect], ρ=[0.02])       # rect-only at 2% steel

# ── Save manually ──
save_results(df, "my_study")              # → results/my_study_<timestamp>.csv
```

### Running (command line)

```bash
julia --project=StructuralStudies -e "include(\"src/column_properties/column_parametric_study.jl\"); sweep()"
```

### Visualization

```julia
include("src/column_properties/vis.jl")

df = load_results()       # latest CSV
generate_all(df)          # all 9 figures → figs/

# Individual figures:
plot_pareto(df)           # capacity vs carbon Pareto frontier
plot_heatmap(df)          # f'c × ρ capacity heatmap
plot_capacity_scaling(df) # capacity vs Ag/As
plot_slenderness(df)      # δns boxplots by kLu/r
plot_efficiency(df)       # carbon efficiency vs ρ
plot_carbon_breakdown(df) # stacked bar: concrete vs steel carbon
plot_carbon_crossover(df) # carbon fraction crossover
plot_fy_comparison(df)    # Grade 60 vs 80
```

### Focused Sub-Studies

| Sweep | Varies | Fixes | Question |
|-------|--------|-------|----------|
| `material_sweep()` | f'c, fy, ρ | 20" sq, tied, 1.5" cover | How do material choices affect capacity per kg CO₂e? |
| `geometry_sweep()` | size, AR, shape | f'c=4, fy=60, ρ=2% | How does geometry scale capacity & carbon? |
| `detailing_sweep()` | cover, arrangement, tie | 20" sq, f'c=4, fy=60 | How much do detailing choices matter? |

### Sweep Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `sizes` | `[12, 16, 20, 24, 30, 36]` | Column size (inches) |
| `aspect_ratios` | `[1.0, 1.33, 1.5, 2.0]` | h/b for rectangular |
| `fc` | `[3.0, 4.0, 5.0, 6.0, 8.0]` | f'c (ksi) |
| `fy` | `[40.0, 60.0, 75.0, 80.0]` | fy (ksi) |
| `ρ` | `[0.01, 0.02, 0.03, 0.04, 0.06]` | Target reinforcement ratios |
| `covers` | `[1.5, 2.0, 3.0]` | Clear cover (inches) |
| `arrangements` | `[:perimeter, :two_layer, :corners_only]` | Bar layout |
| `tie_types` | `[:tied, :spiral]` | Confinement |
| `shapes` | `[:rect, :circular]` | Section shape |
| `kLu_r` | `[30, 50, 70]` | Slenderness ratios |
| `save` | `true` | Auto-save CSV |

### Figures

| # | Figure | Insight |
|---|--------|---------|
| 01 | Pareto frontier | Capacity-vs-carbon efficient designs |
| 02–03 | Heatmaps | f'c × ρ capacity interaction by size |
| 04 | Capacity scaling | How Ag and As drive capacity |
| 05 | Slenderness | δns distribution at each kLu/r |
| 06 | Carbon efficiency | Efficiency vs ρ, colored by Ag |
| 07 | Carbon breakdown | Concrete vs steel contribution |
| 08 | Carbon crossover | Carbon fraction crossover at ~2.5% ρ |
| 09 | Grade comparison | Grade 60 vs 80 rebar trade-off |

### Output

- Results → `src/column_properties/results/`
- Figures → `src/column_properties/figs/`

---

## Flat Plate Method Comparison Study

**Goal:** Compare all five flat plate slab sizing methods (MDDM, DDM, EFM Hardy Cross,
EFM ASAP, FEA) on square bays to understand how analysis method choice affects
thickness, punching shear, deflection, column sizes, rebar, and runtime.

### Methods

| # | Key | Method | Description |
|---|-----|--------|-------------|
| 1 | `:mddm` | MDDM | Modified DDM — simplified 0.65 / 0.35 coefficients |
| 2 | `:ddm` | DDM (Full) | Full ACI 318 Table 8.10.4.2 coefficients |
| 3 | `:efm_hc` | EFM (HC) | Equivalent Frame — Hardy Cross moment distribution |
| 4 | `:efm` | EFM (ASAP) | Equivalent Frame — ASAP FEM stiffness solver |
| 5 | `:fea` | FEA | 2D shell model with column stubs |

### Running (REPL)

```julia
# from StructuralStudies/ directory
using Pkg; Pkg.activate(".")

# ── Load the study ──
include("src/flat_plate_methods/flat_plate_method_comparison.jl")

# ── Quick comparison table ──
compare()                                 # 20 ft square bays, LL=50 psf
compare(span=24.0, ll=80.0)              # custom

# ── Run sweeps ──
df = sweep()                              # full factorial (4 spans × 3 LLs × 5 methods = 60)
df = span_sweep(ll=50.0)                  # all spans, single LL
df = load_sweep(span=20.0)                # all LLs, single span
df = sweep(spans=[20, 24], live_loads=[50])  # custom subset

# ── Save manually ──
save_results(df, "my_study")              # → results/my_study_<timestamp>.csv
```

### Visualization

```julia
include("src/flat_plate_methods/vis.jl")

df = load_results()       # latest CSV
generate_all(df)          # all 7 figures → figs/

# Individual figures:
plot_thickness(df)        # slab thickness vs span
plot_moments(df)          # M₀ comparison (sanity check)
plot_punching(df)         # punching ratio vs span
plot_deflection(df)       # deflection ratio vs span
plot_columns(df)          # final column sizes
plot_rebar(df)            # total rebar area
plot_runtime(df)          # runtime comparison (log scale)
```

### Sweep Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `spans` | `[16.0, 20.0, 24.0, 28.0]` | Bay span (ft), square panels |
| `live_loads` | `[40.0, 50.0, 80.0]` | Live load (psf) |
| `story_ht` | `10.0` | Story height (ft) |
| `n_bays` | `3` | Number of bays (3×3 grid) |
| `sdl` | `20.0` | Superimposed dead load (psf) |
| `col_in` | `16.0` | Initial column size (inches) |
| `methods` | all five | Methods to run |
| `save` | `true` | Auto-save CSV |

### Figures

| # | Figure | Insight |
|---|--------|---------|
| 01 | Thickness vs span | How method choice affects required slab depth |
| 02 | M₀ vs span | Sanity check — M₀ should match across methods |
| 03 | Punching vs span | Unbalanced moment sensitivity to analysis method |
| 04 | Deflection vs span | Deflection sensitivity to moment distribution |
| 05 | Column sizes | Column growth driven by P-M interaction |
| 06 | Rebar area | Material quantity implications |
| 07 | Runtime | Computational cost (FEA vs analytical) |

### Output

- Results → `src/flat_plate_methods/results/`
- Figures → `src/flat_plate_methods/figs/`