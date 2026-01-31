# StructuralStudies

Parametric studies for structural design optimization research.

## Column Properties Study

**Goal:** Understand how RC column design parameters affect structural capacity and embodied carbon to inform optimization strategies.

**Parameters:**
| Category | Parameters |
|----------|------------|
| Geometry | Shape (rect/circular), size (12–36"), aspect ratio, cover |
| Materials | f'c (3–8 ksi), fy (60/80 ksi), ρ (1–6%) |
| Detailing | Bar arrangement (perimeter/two-layer), tie type (tied/spiral) |
| Loading | Slenderness ratio (kLu/r = 0–70) |

**Figures:**
| Figure | Insight |
|--------|---------|
| Pareto frontier | Capacity vs carbon trade-off; identifies efficient designs |
| Capacity heatmaps | How f'c and ρ jointly affect φPn,max |
| Slenderness cliff | At what kLu/r does capacity drop significantly? |
| Shape comparison | Rectangular vs circular efficiency |
| Grade 60 vs 80 | Is high-strength rebar worth it? |
| Arrangement | Perimeter vs two-layer moment capacity |
| Tie comparison | Tied vs spiral confinement benefit |
| Cover effect | Capacity cost of increased durability |
| f'c effect | Concrete strength vs efficiency |
| Carbon breakdown | Concrete vs steel carbon contribution |
| Dashboard | Multi-panel summary |

## Running

```bash
# Run parametric study
julia --project=StructuralStudies StructuralStudies/src/column_properties/column_parametric_study.jl

# Generate figures (in Julia REPL)
include("src/init.jl")
include("src/column_properties/vis.jl")
df = load_study_results(latest_results(RESULTS_DIR))
generate_all_visualizations(df)
```

Results → `src/column_properties/results/`  
Figures → `src/column_properties/figs/`
