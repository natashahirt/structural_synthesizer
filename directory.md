# Structural Synthesizer — Codebase Directory

> **Last updated:** 2026-03-02 (Drop panel strip widening per Pacoste §4.2.1; cantilever slab note)
> 
> Reference document for codebase capabilities, types, and workflows.
> Update this file when implementing new features or changing APIs.

---

## 📦 Package Overview

| Package | Purpose | Dependencies | Status |
|---------|---------|--------------|--------|
| `Asap` | FEM analysis + **canonical source for units** (kip, ksi, psf, ksf, pcf) | Unitful, LinearAlgebra | ✅ Active |
| `StructuralPlots` | Makie themes, colors, figure utilities | GLMakie | ✅ Stable |
| `StructuralSizer` | Core sizing: materials, sections, codes, optimization | Asap, Unitful, Roots, QuadGK | ✅ Active |
| `StructuralStudies` | Parametric research studies | StructuralSizer, StructuralPlots | ✅ Stable |
| `StructuralSynthesizer` | End-to-end building generation and design workflow | StructuralSizer, Asap, Meshes, Graphs | ✅ Active |

**Dependency Chain:** `Asap` → `StructuralSizer` → `StructuralSynthesizer`

---

## 📐 Units & Type Aliases

> **Canonical source:** `Asap` (re-exported by `StructuralSizer` and `StructuralSynthesizer`)

### US Customary Units
| Unit | Symbol | Definition | Usage |
|------|--------|------------|-------|
| `kip` | kip | 1000 lbf | Force |
| `ksi` | ksi | 1000 psi | Pressure/stress |
| `psf` | psf | lbf/ft² | Area load |
| `ksf` | ksf | 1000 psf | Foundation bearing |
| `pcf` | pcf | lb/ft³ | Density |

### Type Aliases (Dimension-Based)
| Alias | Dimension | Examples |
|-------|-----------|----------|
| `Length` | 𝐋 | `m`, `ft`, `inch` |
| `Area` | 𝐋² | `m²`, `ft²`, `inch²` |
| `Volume` | 𝐋³ | `m³`, `ft³`, `inch³` |
| `Pressure` | 𝐌𝐋⁻¹𝐓⁻² | `Pa`, `ksi`, `psf` |
| `Force` | 𝐌𝐋𝐓⁻² | `N`, `kip`, `lbf` |
| `Moment` | 𝐌𝐋²𝐓⁻² | `N·m`, `kip·ft` |
| `LinearLoad` | 𝐌𝐓⁻² | `N/m`, `kip/ft` |
| `Density` | 𝐌𝐋⁻³ | `kg/m³`, `pcf` |

### Unit Conversion Helpers
| Function | Description |
|----------|-------------|
| `to_ksi(x)` | Convert pressure to ksi |
| `to_kip(x)` | Convert force to kip |
| `to_kipft(x)` | Convert moment to kip·ft |
| `to_inches(x)` | Convert length to inches |
| `to_meters(x)` | Convert length to meters |
| `to_pascals(x)` | Convert pressure to Pa |
| `to_newtons(x)` | Convert force to N |

### Physical Constants
| Constant | Value | Description |
|----------|-------|-------------|
| `GRAVITY` | 9.80665 m/s² | Standard gravity (from Asap) |

### Design Constants (`Constants.jl`)
| Constant | Value | Description |
|----------|-------|-------------|
| `DL_FACTOR` | 1.2 | ASCE 7 dead load factor |
| `LL_FACTOR` | 1.6 | ASCE 7 live load factor |
| `BIG_M` | 1e9 | Optimizer big-M constant |
| `ACI_CRACK_CONTROL_FS_PSI` | 40000 | ACI 318-11 §10.6.4 crack control limit |
| *(removed)* | — | PCA stiffness factors are now computed per-geometry via `pca_slab_beam_factors()` and `pca_column_factors()` in `codes/aci/pca_tables.jl` |

### Unitful Best Practices

> **Rule:** Never create variables with unit suffixes like `length_m`, `force_kN`, `stress_psi`. Let Unitful handle conversions automatically.

**Correct patterns:**
```julia
# Store with natural units, convert when needed
span = 6.0u"m"
fc = 4000u"psi"
stress = uconvert(u"MPa", fc)  # Convert for display/output
value = ustrip(u"ksi", stress)  # Strip only at final boundary
```

**Avoid:**
```julia
# BAD: Manual unit bookkeeping
span_m = 6.0
fc_psi = 4000
stress_ksi = fc_psi / 1000  # Magic number!
```

**Exception:** Internal calculation functions may strip units at the boundary for:
- Optimizer interfaces (require Float64)
- Numerical solvers (Roots.jl, etc.)
- Performance-critical inner loops

In these cases, use named constants for any unit conversion factors:
```julia
const _KPA_PER_MPA = 1000.0  # Instead of magic "/ 1000"
const _PA_PER_MPA = 1e6
```

---

## 🔩 Materials

### Material Type Fields
All material types carry `ecc` (embodied carbon, kgCO₂e/kg) and `cost` ($/kg, `NaN` = not set).

| Type | Key Fields | Notes |
|------|-----------|-------|
| `Metal{K}` | `E, G, Fy, Fu, ρ, ν, ecc, cost` | `K`: `StructuralSteelType` or `RebarType` |
| `Concrete` | `E, fc′, ρ, ν, εcu, ecc, cost, λ` | `λ`: lightweight factor (1.0 for NWC, ACI §19.2.4) |
| `Timber` | `E, Emin, Fb, Ft, Fv, Fc, Fc_perp, ρ, ecc, cost` | NDS reference values |
| `ReinforcedConcreteMaterial` | `concrete, rebar, transverse` | Composite RC material |
| `FiberReinforcedConcrete` | `concrete, fiber_dosage, fR3, fiber_ecc` | FRC for PixelFrame (wraps Concrete) |

### Steel Presets
| Material | Type | Fy | Status |
|----------|------|-----|--------|
| `A992_Steel` | Structural | 50 ksi | ✅ |
| `S355_Steel` | Structural | 50 ksi | ✅ |
| `Rebar_40` | Reinforcing | 40 ksi | ✅ |
| `Rebar_60` | Reinforcing | 60 ksi | ✅ |
| `Rebar_75` | Reinforcing | 75 ksi | ✅ |
| `Rebar_80` | Reinforcing | 80 ksi | ✅ |

### Concrete Presets
| Material | f'c | Notes | Status |
|----------|-----|-------|--------|
| `NWC_3000` | 3 ksi | Normal weight | ✅ |
| `NWC_4000` | 4 ksi | Normal weight | ✅ |
| `NWC_5000` | 5 ksi | Normal weight | ✅ |
| `NWC_6000` | 6 ksi | Normal weight | ✅ |
| `NWC_GGBS` | 4 ksi | Ground granite blast furnace slag | ✅ |
| `NWC_PFA` | 4 ksi | Pulverized fuel ash | ✅ |

### Timber Presets
| Material | Type | Status |
|----------|------|--------|
| `Timber` | Generic | ⚠️ Type only |

---

## 🏗️ Structural Sections

### Steel — W Shapes (Wide Flange)
| Type | Catalog Functions | Design Code | Status |
|------|-------------------|-------------|--------|
| `ISymmSection` | `W(name)`, `all_W()`, `preferred_W()` | AISC 360-16 | ✅ Full |

**Key functions:** `section_area`, `section_depth`, `section_width`, `weight_per_length`, `bounding_box`

### Steel — HSS (Hollow Structural Sections)
| Type | Catalog Functions | Design Code | Status |
|------|-------------------|-------------|--------|
| `HSSRectSection` | `HSS(name)`, `all_HSS()` | AISC 360-16 | ✅ Full |
| `HSSRoundSection` | `HSSRound(name)`, `all_HSSRound()` | AISC 360-16 | ✅ Full |
| `PipeSection` | `PIPE(name)`, `all_PIPE()` (alias) | AISC 360-16 | ✅ Full |

**Key functions:** `is_square`, `governing_slenderness`, `slenderness`

### Concrete — Rectangular Columns
| Type | Catalog Functions | Design Code | Status |
|------|-------------------|-------------|--------|
| `RCColumnSection` | `standard_rc_columns()`, `common_rc_rect_columns()`, `all_rc_rect_columns()` | ACI 318 | ✅ Full |

**Key functions:** `effective_depth`, `compression_steel_depth`, `moment_of_inertia`, `radius_of_gyration`, `n_bars`

### Concrete — Circular Columns
| Type | Catalog Functions | Design Code | Status |
|------|-------------------|-------------|--------|
| `RCCircularSection` | `standard_rc_circular_columns()`, `common_rc_circular_columns()`, `all_rc_circular_columns()` | ACI 318 | ✅ Full |

**Key functions:** `circular_compression_zone`

### Concrete — Beams
| Type | Design Code | Status |
|------|-------------|--------|
| `RCBeamSection` | ACI 318 | ✅ Full (flexure + shear design pipeline) |

### Concrete — PixelFrame (External PT + FRC)
| Type | Catalog Functions | Design Code | Status |
|------|-------------------|-------------|--------|
| `PixelFrameSection` | `generate_pixelframe_catalog()` | ACI 318-19, fib MC2010 | ✅ Full |

**Key fields:** `L_px` (module width), `t` (top slab), `L_c` (web depth), `material` (FRC), `A_s` (tendon area), `f_pe` (effective prestress), `d_ps` (tendon depth, external)

**Key functions:** `section_area`, `section_width`, `section_depth`, `pf_axial_capacity`, `pf_flexural_capacity`, `frc_shear_capacity`, `pf_carbon_per_meter`, `pf_tendon_deviation_force`

### Timber — Glulam
| Type | Design Code | Status |
|------|-------------|--------|
| `GlulamSection` | NDS | ⚠️ Stub (geometry only, no design checks) |

**Available constants:** `STANDARD_GLULAM_WIDTHS`, `GLULAM_LAM_THICKNESS`

---

## 📐 Design Code Coverage

### AISC 360-16 (Steel)
| Check | Sections | Functions | Status |
|-------|----------|-----------|--------|
| Flexure (Mn) | W, HSS Rect, HSS Round | `get_Mn`, `get_ϕMn` | ✅ |
| Shear (Vn) | W, HSS Rect, HSS Round | `get_Vn`, `get_ϕVn` | ✅ |
| Compression (Pn) | W, HSS Rect, HSS Round | `get_Pn`, `get_ϕPn` | ✅ |
| P-M Interaction | W, HSS | `check_PM_interaction`, `check_PMxMy_interaction` | ✅ |
| Slenderness | W, HSS Rect, HSS Round | `get_slenderness`, `is_compact` | ✅ |
| LTB | W | `get_Lp_Lr`, `get_Fcr_LTB` | ✅ |
| Tension | Generic | `get_Tn`, `get_ϕTn` | ✅ |

**Checker:** `AISCChecker`, `AISCCapacityCache`

### ACI 318 — Columns
| Check | Sections | Functions | Status |
|-------|----------|-----------|--------|
| P-M Interaction (Rect) | `RCColumnSection` | `PMInteractionDiagram`, `generate_PM_diagram` | ✅ |
| P-M Interaction (Circular) | `RCCircularSection` | `PMInteractionDiagramCircular` | ✅ |
| Slenderness Magnification | Both | `magnify_moment_nonsway`, `magnify_moment_sway` | ✅ |
| Biaxial Bending | Both | `bresler_reciprocal_load`, `check_biaxial_capacity` | ✅ |
| Capacity Checks | Both | `check_PM_capacity`, `capacity_at_axial`, `utilization_ratio` | ✅ |

**Checker:** `ACIColumnChecker`, `ACIColumnCapacityCache`

### ACI 318 — Flat Plates (🚧 In Progress)
| Check | Functions | Status |
|-------|-----------|--------|
| Minimum Thickness | `min_thickness_flat_plate` | ✅ |
| Clear Span | `clear_span` | ✅ |
| Static Moment | `total_static_moment` | ✅ |
| Moment Distribution (MDDM) | `distribute_moments_mddm` | 🚧 |
| Moment Distribution (DDM) | `distribute_moments_aci` | 🚧 |
| Reinforcement | `required_reinforcement`, `minimum_reinforcement`, `max_bar_spacing` | 🚧 |
| Punching Shear | `punching_perimeter`, `punching_capacity_interior`, `check_punching_shear` | 🚧 |
| Deflection | `cracked_moment_of_inertia`, `effective_moment_of_inertia`, `immediate_deflection`, `long_term_deflection_factor` | 🚧 |

> **Planning:** See `CIP_FLAT_PLATE_DESIGN_PLAN.md` for detailed implementation roadmap.

### ACI 318 — Beams
| Check | Functions | Status |
|-------|-----------|--------|
| Min Depth | `beam_min_depth` (Table 9.3.1.1) | ✅ |
| Effective Depth | `beam_effective_depth` | ✅ |
| Flexure — Whitney Block | `required_reinforcement` (shared), `stress_block_depth`, `neutral_axis_depth` | ✅ |
| Flexure — Min Reinf | `beam_min_reinforcement` (ACI 9.6.1.2) | ✅ |
| Flexure — Strain/φ | `tensile_strain`, `is_tension_controlled`, `flexure_phi` | ✅ |
| Flexure — Bar Selection | `select_beam_bars`, `beam_max_bar_spacing` (ACI 25.2.1/24.3.2) | ✅ |
| Flexure — Singly Reinforced | `design_beam_flexure` (auto-dispatch) | ✅ |
| Flexure — Doubly Reinforced | `max_singly_reinforced`, `compression_steel_stress`, `design_beam_flexure_doubly` | ✅ |
| Flexure — Auto-Dispatch | `design_beam_flexure` auto-detects singly vs doubly reinforced | ✅ |
| Shear — Vc | `Vc_beam` (ACI 22.5.5.1) | ✅ |
| Shear — Vs | `Vs_required`, `Vs_max_beam` (ACI 22.5.1.2) | ✅ |
| Shear — Min Reinf | `min_shear_reinforcement` (ACI 9.6.3.3) | ✅ |
| Shear — Stirrup Spacing | `max_stirrup_spacing` (ACI 9.7.6.2.2), `design_stirrups` | ✅ |
| Shear — Pipeline | `design_beam_shear` | ✅ |
| Deflection | deferred — use shared `cracked_moment_of_inertia`, `effective_moment_of_inertia` | ⚠️ Planned |

**Files:** `StructuralSizer/src/members/codes/aci/beams/flexure.jl`, `shear.jl`
**Tests:**
- `test/concrete_beam/test_rc_beam_reference.jl` (53 tests — simply supported, StructurePoint validated)
- `test/concrete_beam/test_cantilever_beam.jl` (24 tests — cantilever, StructurePoint validated)
- `test/concrete_beam/test_doubly_reinforced.jl` (29 tests — doubly reinforced, StructurePoint validated)
- Total: **106 beam tests**, all passing

### PixelFrame — ACI 318-19 + fib MC2010
| Check | Functions | Status |
|-------|-----------|--------|
| Axial (ACI §22.4.2.3) | `pf_axial_capacity` | ✅ |
| Flexure (ACI §22.4.1.2, unbonded PT) | `pf_flexural_capacity` (iterative εc loop) | ✅ |
| FRC Shear (fib MC2010 §7.7-5) | `frc_shear_capacity` (keyword + section convenience) | ✅ |
| Deflection — Simplified (Branson + EPT) | `pf_cracking_moment`, `pf_cracked_moment_of_inertia`, `pf_effective_Ie`, `pf_deflection`, `pf_check_deflection` | ✅ |
| Embodied Carbon (thesis Eq. 2.16) | `pf_carbon_per_meter`, `pf_concrete_ecc` | ✅ |
| MinCarbon override | `objective_value(::MinCarbon, ::PixelFrameSection, ...)` | ✅ |
| Deflection — Full Iterative Ng & Tan (2006) | `pf_deflection(..., method=PFThirdPointLoad())`, `pf_deflection_curve` | ✅ |

**Checker:** `PixelFrameChecker`, `PixelFrameCapacityCache`

**Cache units:** N, N·m (consistent with AISC checker convention)

> **Note on Deflection:** The full Ng & Tan iterative deflection model is implemented, but the simplified, non-iterative Branson approach remains the default for `pf_deflection` and `pf_check_deflection` for performance in design-level serviceability checks. The full model can be explicitly selected via the `method` keyword argument (e.g., `method=PFThirdPointLoad()` or `method=PFSinglePointLoad()`) for detailed analysis or research validation. See `StructuralSizer/src/members/codes/pixelframe/README.md` for details.

### NDS — Timber
| Check | Status |
|-------|--------|
| All | ⚠️ Stub (`NDSChecker` defined, throws errors) |

### CSA — Canadian Steel
| Check | Status |
|-------|--------|
| All | ❌ Directory exists, no implementation |

### Eurocode
| Check | Status |
|-------|--------|
| All | ❌ Empty directory |

---

## 🧱 Floor Systems

### Slab Sizing API (Public)

| Function | Description | Status |
|----------|-------------|--------|
| `size_slabs!(struc; options=FloorOptions())` | Size all slabs in building | ✅ |
| `size_slab!(struc, slab_idx; options=FloorOptions())` | Size single slab (debug/testing) | ✅ |

Internal dispatch: `_size_slab!(::FloorType, struc, slab, idx; ...)` routes to type-specific pipelines.

### CIP Concrete
| Type | Spanning | Status |
|------|----------|--------|
| `OneWay` | One-way | ⚠️ Type defined |
| `TwoWay` | Two-way | ⚠️ Type defined |
| `FlatPlate` | Beamless | ✅ Full (DDM + EFM + FEA) |
| `FlatSlab` | Beamless | ⚠️ Type defined |
| `PTBanded` | Two-way | ⚠️ Type defined |
| `Waffle` | Two-way | ⚠️ Type defined |
| `HollowCore` | One-way | ⚠️ Stub |
| `Vault` | Custom | ✅ Full (Haile method) |
| `CantileverSlab` | Cantilever | ❌ Not Started |

> **Cantilever Slabs (future):** Relevant for balconies and bridge overhangs. Distribution widths for transverse moments and shear follow Pacoste et al. (2012) §4.4, based on Hedman & Losberg (1976) tests. Key equations: `w_x = min(7d + b + t, 10d + 1.3·y_CS)` for ULS moments (Eq. 4.32), with SLS width `w_x = 2h + b + t` (Eq. 4.33). Shear distribution widths interpolate between `w_max` at the clamped edge and `w_min` at `y_max` (Eqs. 4.34–4.35). Implementation would require a simplified clamped-free slab model (Fig. 4.15) and integration with the existing FEA infrastructure. See `Pacoste_et_al_2012_FEA_Recommendations.pdf` for full details.

> **Wall Supports (future):** Walls are line supports (on skeleton edges, not vertices) and require different treatment from columns at every layer:
>
> *Building model:* Add `Wall{T} <: AbstractMember{T}` on a skeleton edge `(v1, v2)` with thickness `t_w`, height, and material. Currently no wall type exists — only `Beam`, `Column`, `Strut`.
>
> *FEA model (`model.jl`):* Pacoste §2.2.1 (Fig 2.1) recommends a **pin support at the wall centreline** — constrain vertical DOF at each node along the wall top edge, no rotational constraint (avoids over-constraint per Rombach 2004). For monolithic connections, either include the wall as shell elements below the slab (preferred, §2.2.1 Fig 2.2) or use rigid links over the wall width when `a < min(l₀₁, l₀₂)` and `a/t < 2`. Mesh conformity via an elongated `ShellPatch` running the full wall length × wall thickness, with at least one element between the support line and the critical section (§2.2.2).
>
> *Moment extraction:* Wall-supported edges don't participate in the column-strip/middle-strip paradigm. The slab is continuously supported → **one-way spanning** perpendicular to the wall. Design for the maximum moment at the wall face (§3.1.2 for monolithic, §3.1.3 at `a/4` for simple supports). In the direction parallel to the wall, normal strip rules apply if the slab also spans to columns. Distribution widths per Pacoste §4.2.1.3: `L_c = L_x` (longitudinal), `L_c = B_y` (transverse).
>
> *Phased plan:* (1) `Wall` type + FEA pin-line support + `ShellPatch`, (2) line-integration moment extraction at wall face, (3) ACI one-way slab provisions for wall-supported edges.

#### FEA Knobs (`FEA` struct in `slabs/types.jl`)

| Knob | Values | Default | Description |
|------|--------|---------|-------------|
| `target_edge` | `Length` / `nothing` | `nothing` (auto) | Mesh edge length |
| `pattern_loading` | `Bool` | `true` | ACI 318-11 §13.7.6 pattern loading |
| `pattern_mode` | `:efm_amp`, `:fea_resolve` | `:efm_amp` | Pattern loading strategy |
| `design_approach` | `:frame`, `:strip`, `:area` | `:frame` | How element moments → design moments |
| `moment_transform` | `:projection`, `:wood_armer`, `:no_torsion` | `:projection` | 2D tensor → scalar reduction |
| `field_smoothing` | `:element`, `:nodal` | `:element` | Raw centroids vs SPR-smoothed field |
| `cut_method` | `:delta_band`, `:isoparametric` | `:delta_band` | Section cut integration method |
| `iso_alpha` | `[0, 1]` | `1.0` | Isoparametric cut blending |
| `rebar_direction` | `Float64` (rad) / `nothing` | `nothing` (span) | Reinforcement axis angle |
| `sign_treatment` | `:signed`, `:separate_faces` | `:signed` | Nodal smoothing sign handling |
| `concrete_torsion_discount` | `Bool` | `false` | Subtract concrete Mxy capacity before Wood–Armer |

- `:no_torsion` drops Mxy from projection — intentionally unconservative baseline for quantifying torsion effects.
- `:separate_faces` smooths hogging/sagging fields independently, preventing cross-sign cancellation at inflection points.
- `concrete_torsion_discount` reduces |Mxy| by the concrete's torsion capacity (ACI 318-11 §11.2.1.1 via Parsekian circular V–T interaction) before the Wood–Armer transformation. Only applies when `moment_transform = :wood_armer`. See `torsion_discount.jl`.
- **Drop panel strip widening** (Pacoste §4.2.1 Fig 4.4): When a `DropPanelGeometry` is present, column strip polygons are automatically widened so their transverse extent covers the drop panel zone. The minimum CS half-width becomes `max(d_max/2, a_drop)`, where `a_drop` is the drop panel half-extent. Stored in `FEAModelCache.drop_panel` and threaded to all `_build_cs_polygons_abs` call sites. A `@debug` warning fires when the widening scale exceeds 1.5× (check `m_av/m_max ≥ 0.6` per Pacoste §4.2.1 point 1).

**Flat plate functions:** `StripReinforcement`, `FlatPlatePanelResult`, `estimate_column_size`

**Flat plate optimization:** `size_flat_plate_optimized(struc, slab, opts)` — 2D grid search over (h, c) with inner rebar sweep. Supports `MinVolume`, `MinWeight`, `MinCost`, `MinCarbon` objectives via `FlatPlateOptions(objective=MinCarbon())`.

**Vault analysis methods:** `VaultAnalysisMethod`, `HaileAnalytical`, `ShellFEA` (future)

**Vault functions:** `vault_stress_symmetric`, `vault_stress_asymmetric`, `solve_equilibrium_rise`, `parabolic_arc_length`, `get_vault_properties`

**VaultResult fields:** `thickness`, `rise`, `arc_length`, `thrust_dead`, `thrust_live`, `volume_per_area`, `self_weight`, `σ_max`, `governing_case`, `stress_check`, `deflection_check`, `convergence_check`

**VaultResult accessors:** `total_thrust(r)`, `is_adequate(r)`

### Steel Floors
| Type | Status |
|------|--------|
| `CompositeDeck` | ⚠️ Stub (throws error) |
| `NonCompositeDeck` | ⚠️ Stub |
| `JoistRoofDeck` | ⚠️ Stub |

### Timber Floors
| Type | Status |
|------|--------|
| `CLT` | ⚠️ Stub (throws error) |
| `DLT` | ⚠️ Stub |
| `NLT` | ⚠️ Stub |
| `MassTimberJoist` | ⚠️ Stub |

### Custom
| Type | Status |
|------|--------|
| `ShapedSlab` | ⚠️ Type defined |

### Floor Options
| Options Struct | Floor Types | Key Fields |
|----------------|-------------|------------|
| `FloorOptions` | All | `flat_plate`, `one_way`, `vault`, `composite`, `timber`, `tributary_axis` |
| `FlatPlateOptions` | FlatPlate, FlatSlab, Waffle, PT | `material`, `cover`, `bar_size`, `analysis_method`, `has_edge_beam`, `φ_flexure`, `φ_shear`, `λ`, `deflection_limit`, `objective` |
| `OneWayOptions` | OneWay | `material`, `cover`, `bar_size`, `support` |
| `VaultOptions` | Vault | `rise`/`lambda`, `thickness`, `material`, `method`, `allowable_stress` |
| `CompositeDeckOptions` | Composite deck | `deck_material`, `fill_material`, `deck_profile` |
| `TimberOptions` | CLT, DLT, NLT | `timber_material` |

**Material presets:** `RC_4000_60` (NWC_4000 + Rebar_60), `RC_5000_60`, etc.

**Helper functions:** `floor_type`, `floor_symbol`, `infer_floor_type`

---

## 🔲 Tributary Area Calculations

> **Note:** Generic tributary computation moved to **Asap** package. ACI strip geometry remains in **StructuralSizer**.

### Edge-Based (Straight Skeleton) — **Asap**
| Function | Description | Status |
|----------|-------------|--------|
| `Asap.get_tributary_polygons` | Main dispatch (one-way or isotropic) | ✅ |
| `Asap.get_tributary_polygons_isotropic` | Two-way spanning (isotropic) | ✅ |
| `Asap.get_tributary_polygons_one_way` | One-way spanning (axis-dependent) | ✅ |
| `Asap.TributaryPolygon` | Result type with edge index, vertices | ✅ |
| `Asap.TributaryBuffers` | Pre-allocated buffers for batch processing | ✅ |

### Vertex-Based (Voronoi) — **Asap**
| Function | Description | Status |
|----------|-------------|--------|
| `Asap.compute_voronoi_tributaries` | Column tributary areas | ✅ |
| `Asap.VertexTributary` | Result type with vertex index, polygon, area | ✅ |

### Span Calculations — **Asap**
| Function | Description | Status |
|----------|-------------|--------|
| `Asap.SpanInfo` | Short/long span info for a cell | ✅ |
| `Asap.get_polygon_span` | Compute span for a polygon | ✅ |
| `Asap.governing_spans` | Combine spans from multiple cells | ✅ |
| `Asap.short_span`, `long_span`, `two_way_span` | Span accessors | ✅ |

### ACI Strip Geometry — **StructuralSizer**
| Function | Description | Status |
|----------|-------------|--------|
| `split_tributary_at_half_depth` | Split tributary into column/middle strips | ✅ |
| `compute_panel_strips` | Full strip geometry for panel | ✅ |
| `ColumnStripPolygon`, `MiddleStripPolygon` | Strip types | ✅ |
| `verify_rectangular_strips` | Validation | ✅ |

---

## 🏛️ Foundations

### Foundation Type Hierarchy
| Type | Category | Status |
|------|----------|--------|
| `SpreadFooting` | Shallow | ✅ IS 456 + ACI 318-11 |
| `CombinedFooting` | Shallow | ⚠️ Type only (subsumed by StripFooting) |
| `StripFooting` | Shallow | ✅ ACI 318-11 + ACI 336.2R (rigid) |
| `MatFoundation` | Shallow | ✅ ACI 336.2R (rigid); 🚧 Hetenyi + FEA stub |
| `DrivenPile` | Deep | ⚠️ Type only |
| `DrilledShaft` | Deep | ⚠️ Type only |
| `Micropile` | Deep | ⚠️ Type only |

### Soil Types
| Constant | Description |
|----------|-------------|
| `loose_sand`, `medium_sand`, `dense_sand` | Sand presets |
| `soft_clay`, `stiff_clay`, `hard_clay` | Clay presets |

**Soil fields:** `qa` (bearing), `γ` (unit weight), `ϕ` (friction angle), `c` (cohesion), `Es` (modulus), `qs`/`qp` (pile friction/bearing), `ks` (modulus of subgrade reaction — for Winkler analysis)

### Design Codes — IS 456
| Function | Status |
|----------|--------|
| `design_spread_footing` (IS 456) | ✅ Full (bearing, punching, one-way shear, flexure) |

### Design Codes — ACI 318-11 (✅ Implemented)

#### Spread Footing (`codes/aci/spread_footing.jl`)
Full 7-step StructurePoint workflow, Unitful throughout.

| Step | Description | ACI Reference | Status |
|------|-------------|---------------|--------|
| 1 | Bearing check (service loads) → footing plan (B × L) | ACI 318-11 §15.2 | ✅ |
| 2 | Two-way (punching) shear → minimum depth | ACI 318-11 §11.11.2.1 | ✅ |
| 3 | One-way (beam) shear check | ACI 318-11 §11.2.1.1 | ✅ |
| 4 | Flexural reinforcement (both directions) | ACI 318-11 §10.2, §7.7 | ✅ |
| 5 | Development length verification | ACI 318-11 §12.2 | ✅ |
| 6 | Bearing at column-footing joint + dowels | ACI 318-11 §10.14, §15.8 | ✅ |
| 7 | Volume computation (concrete + steel) | — | ✅ |

**Pier shapes:** `:rect` (includes square when c1==c2), `:circular`
**Footing shapes:** `:rect` (B × L, square when B==L)

**Punching perimeter:** Reuses `punching_perimeter(c1, c2, d; shape)` and `punching_geometry_interior` from flat plate code — already handles both `:rectangular` and `:circular`.

**Validation:** StructurePoint ACI 318-11 Spread Footing reference (18" sq column, fc'=4ksi, fy=60ksi, qa=5ksf, Pu=440kip, Ps=300kip)

#### Strip / Combined Footing (`codes/aci/strip_footing.jl`)
Rigid-analysis strip supporting N ≥ 2 columns.

| Step | Description | ACI Reference | Status |
|------|-------------|---------------|--------|
| 1 | Plan sizing: length from column positions, width from bearing | ACI 336.2R §4.1 | 🚧 |
| 2 | Two-way (punching) shear at each column | ACI 318-11 §11.11.2.1 | 🚧 |
| 3 | One-way (beam) shear check | ACI 318-11 §11.2.1.1 | 🚧 |
| 4 | Longitudinal flexure (continuous beam statics) | ACI 336.2R §4.1 | 🚧 |
| 5 | Transverse flexure (band under each column) | ACI 318-11 §13.3.3 | 🚧 |
| 6 | Development length | ACI 318-11 §12.2 | ✅ |

**Auto-merge from spread:** When `gap < merge_gap_factor × D_max` or `eccentricity > limit`, adjacent spread footings merge into a strip.

**Validation:** StructurePoint ACI 318-11 Combined Footing reference (two columns: 18"×18" ext + 18"×18" int, fc'=4ksi, fy=60ksi, qa=5ksf)

#### Mat Foundation (`codes/aci/mat/`)
Tiered analysis methods (mirrors flat plate DDM → EFM → FEA pattern).

| Method Type | Analysis | k_s Required? | Geometry | Status |
|-------------|----------|:-------------:|----------|--------|
| `RigidMat()` | Uniform/linear pressure, strip statics | No | Regular grid | ✅ |
| `Hetenyi()` | Beam-on-elastic-foundation closed-form | **Yes** | Regular grid (strips) | 🚧 |
| `WinklerFEA(; mesh_density=8)` | Shell mesh + `Asap.Spring` per node | **Yes** | Any (irregular, L-shape) | ❌ Stub |

**Common steps (all methods):**
1. Mat plan extents from column positions + edge overhang
2. Bearing check: q_net ≤ q_a
3. Thickness from punching shear at each column (heaviest governs)
4. Dispatch to analysis method → bending moments
5. Design reinforcement from moment envelope
6. Return `MatFootingResult`

**Hetenyi closed-form** (default): Solves each X/Y strip analytically via `λ = ⁴√(k_s B / 4EI)`. Superposition of point-load solutions from Hetenyi (1946). ACI 336.2R §5.4.

**WinklerFEA** (future): Builds Asap model with `ShellTri3` mesh + `Spring(node; kz=k_s × trib_area)` at each node. Reuses flat plate FEA infrastructure (meshing, moment extraction, punching checks). ACI 336.2R Chapter 6.

### Foundation Options (User Knobs)

| Options Struct | Scope | Key Fields |
|----------------|-------|------------|
| `FoundationOptions` | Top-level container | `spread`, `strip`, `mat`, `strategy` (`:auto`/`:all_spread`/`:all_strip`/`:mat`), `mat_coverage_threshold` |
| `SpreadFootingOptions` | Spread footing | `material`, `cover`, `bar_size`, `pier_shape` (`:rect`/`:circular`), `pier_c1`/`pier_c2`, `min_depth`, `depth_increment`, `size_increment`, `ϕ_flexure`, `ϕ_shear`, `λ`, `code` (`:aci318`/`:is456`), `check_bearing`, `check_dowels`, `check_development`, `objective` |
| `StripFootingOptions` | Strip/combined | `material`, `cover`, `bar_size_long`/`bar_size_trans`, `min_depth`, `analysis` (`:rigid`), `merge_gap_factor`, `eccentricity_limit`, `ϕ_flexure`, `ϕ_shear`, `objective` |
| `MatFootingOptions` | Mat foundation | `material`, `cover`, `bar_size_x`/`bar_size_y`, `min_depth`, `edge_overhang`, `analysis_method` (`RigidMat()`/`Hetenyi()`/`WinklerFEA()`), `ϕ_flexure`, `ϕ_shear`, `objective` |

**Integration with `DesignParameters`:**
```
FoundationParameters.soil::Soil
FoundationParameters.options::FoundationOptions
FoundationParameters.group_tolerance::Float64
```

### Mat Analysis Method Types
| Type | Description | Reference |
|------|-------------|-----------|
| `RigidMat` | Uniform pressure, strip statics | ACI 336.2R §5.2 |
| `Hetenyi` | Closed-form beam-on-elastic-foundation | Hetenyi 1946, ACI 336.2R §5.4 |
| `WinklerFEA` | FEA plate on Winkler springs | ACI 336.2R Ch. 6, `Asap.Spring` |

### Auto-Selection Strategy (`:auto`)
```
1. Size all supports as spread footings (tentative)
2. Global coverage ratio > mat_coverage_threshold? → :mat
3. For adjacent spread footings: gap < merge_gap_factor × D_max? → merge to strip
4. Edge columns with eccentricity > limit? → merge to strip
5. Return mixed spread + strip set
```

### Result Types
| Type | Fields | Status |
|------|--------|--------|
| `SpreadFootingResult` | `B`, `L_ftg`, `D`, `d`, `As`, `rebar_count`, `rebar_dia`, `concrete_volume`, `steel_volume`, `utilization` | ✅ |
| `CombinedFootingResult` | `B`, `L_ftg`, `D`, `d`, `As_bot`, `As_top`, `concrete_volume`, `steel_volume`, `utilization` | ⚠️ Type only |
| `StripFootingResult` | `B`, `L_ftg`, `D`, `d`, `As_long_bot/top`, `As_trans`, `n_columns`, `concrete_volume`, `steel_volume`, `utilization` | ✅ |
| `MatFootingResult` | `B`, `L_ftg`, `D`, `d`, `As_x`, `As_y`, `n_columns`, `concrete_volume`, `steel_volume`, `utilization` | ✅ |
| `PileCapResult` | `n_piles`, `pile_dia`, `pile_length`, etc. | ⚠️ Type only |

### Implementation Phases
| Phase | Scope | Deliverable |
|-------|-------|-------------|
| **1** | `options.jl` + `spread_footing.jl` (ACI) + updated `types.jl` | ✅ Validated against StructurePoint spread footing reference |
| **2** | `strip_footing.jl` (ACI, rigid) + auto-merge logic | ✅ Validated against StructurePoint combined footing reference |
| **3** | `mat/rigid.jl` + selection heuristic | ✅ Rigid mat + Voronoi coverage heuristic |
| **4** | `mat/hetenyi.jl` + `mat/fea.jl` (Winkler FEA) | 🚧 Hetenyi + FEA stub |

### Reference Documents
| Document | Content | Used For |
|----------|---------|----------|
| StructurePoint ACI 318-11 Spread Footing | 7-step hand calc: 18" sq column, 4ksi, 60ksi, qa=5ksf | Phase 1 validation |
| StructurePoint ACI 318-11 Combined Footing | 2-column combined: punching at int/ext, longitudinal flexure | Phase 2 validation |
| ACI 336.2R-88 Combined Footings and Mats | K_r rigidity, strip procedures, Winkler FEA, mat heuristics | Phases 2–4 theory |

---

## 🧮 Optimization & Sizing

### Discrete Optimization
| Function | Description | Status |
|----------|-------------|--------|
| `optimize_discrete` | Generic discrete section optimizer | ✅ |
| `optimize_discrete` (multi-material) | Overload accepting `materials::Vector` for multi-material MIP | ✅ |
| `expand_catalog_with_materials` | Expand catalog × materials for multi-material solve | ✅ |
| `size_columns` | Column sizing from demands | ✅ |
| `to_steel_demands`, `to_rc_demands` | Demand conversion | ✅ |
| `to_steel_geometry`, `to_concrete_geometry` | Geometry conversion | ✅ |

### Continuous Optimization (Grid Search)
| Function / Type | Description | Status |
|-----------------|-------------|--------|
| `optimize_continuous` | Generic grid-search NLP solver (1D/2D + refinement) | ✅ |
| `VaultNLPProblem` | Vault rise + thickness optimization | ✅ |
| `FlatPlateNLPProblem` | Slab thickness + column size optimization with inner rebar sweep | ✅ |
| `size_flat_plate_optimized` | User-facing API for flat plate optimization | ✅ |

> **Note:** The continuous solver uses a multi-pass grid search with refinement. Objectives: `MinVolume`, `MinWeight`, `MinCost`, `MinCarbon`. The flat plate optimizer jointly searches over slab thickness `h` and column size `c`, with an inner sweep over bar sizes (#4–#8) at each grid point to find the best rebar/thickness trade-off.

### Sizing Options
| Struct | Material | Notes |
|--------|----------|-------|
| `SteelMemberOptions` | Steel | Columns & beams (same AISC checker) |
| `SteelColumnOptions` | Steel | Alias for `SteelMemberOptions` |
| `SteelBeamOptions` | Steel | Alias for `SteelMemberOptions` |
| `ConcreteColumnOptions` | Concrete | ACI P-M interaction |
| `ConcreteBeamOptions` | Concrete | ACI flexure + shear |
| `ColumnOptions` | Union | `SteelMemberOptions ∪ ConcreteColumnOptions` |
| `BeamOptions` | Union | `SteelMemberOptions ∪ ConcreteBeamOptions` |
| `MemberOptions` | Union | All member option types |

### Catalog Functions
| Function | Returns |
|----------|---------|
| `steel_column_catalog()` | Preferred W shapes for columns |
| `rc_column_catalog()` | Standard RC column sections |

### Objectives
| Objective | Description |
|-----------|-------------|
| `MinWeight` | Minimize weight |
| `MinVolume` | Minimize volume |
| `MinCost` | Minimize cost |
| `MinCarbon` | Minimize embodied carbon |

---

## 🏢 Building Workflow (StructuralSynthesizer)

### Building Generation
| Function | Description | Status |
|----------|-------------|--------|
| `gen_medium_office` | DOE medium office template | ✅ |

### Building Types
| Type | Description |
|------|-------------|
| `BuildingSkeleton` | Geometric skeleton (vertices, edges, faces) |
| `BuildingStructure` | Structural model (cells, slabs, members) |
| `Story` | Story definition |
| `Cell` | Floor cell (face + floor type + spans) |
| `Slab`, `SlabGroup` | Slab definitions |
| `Segment`, `MemberGroup` | Member grouping |
| `TributaryCache` | Cached tributary computations |

### Member Types
| Type | Description |
|------|-------------|
| `MemberBase` | Base member with section, volumes |
| `Beam` | Horizontal member |
| `Column` | Vertical member |
| `Strut` | Diagonal/bracing member |
| `Support`, `Foundation` | Support conditions |

### Initialization Pipeline
| Function | Description |
|----------|-------------|
| `initialize!` | Full initialization pipeline |
| `initialize_cells!` | Create cells from faces |
| `initialize_slabs!` | Create slabs from cells |
| `initialize_segments!` | Create segments from edges |
| `initialize_members!` | Create members from segments |
| `initialize_supports!` | Create supports |
| `initialize_foundations!` | Create foundations |
| `update_bracing!` | Update unbraced lengths |

### Tributary Caching
| Function | Description |
|----------|-------------|
| `get_cached_edge_tributaries` | Get cached edge tributaries |
| `cache_edge_tributaries!` | Store edge tributaries |
| `get_cached_column_tributary` | Get cached column tributary |
| `cache_column_tributary!` | Store column tributary |
| `column_tributary_area` | Get area for a column |
| `clear_tributary_cache!` | Clear all cached data |

### Design Workflow
| Function | Description | Status |
|----------|-------------|--------|
| `design_building` | Full design from structure + parameters | ✅ |
| `compare_designs` | Compare multiple designs | ✅ |
| `DesignParameters` | Design configuration (materials, load combos, analysis settings) | ✅ |
| `BuildingDesign` | Design result container | ✅ |

**DesignParameters fields:**
- Materials: `concrete`, `steel`, `rebar`, `timber`
- Member options: `columns`, `beams`, `floor_options`
- Analysis: `load_combination`, `diaphragm_mode`, `diaphragm_E/ν`
- Frame defaults: `default_frame_E/G/ρ`
- ACI factors: `column_I_factor` (0.70), `beam_I_factor` (0.35)
- Display: `display_units::DisplayUnits` (default `imperial`)

**Unit Convention:**
All `*DesignResult` types store values in coherent SI (m, m², m³, kN, kN·m, kPa, kg).
Analysis modules work in whatever units are natural internally, then normalize at the return boundary.
`DisplayUnits` controls how values are presented in summaries and reports.

| Type | Description |
|------|-------------|
| `DisplayUnits` | Unit preferences for display (`:imperial` or `:metric`) |
| `imperial` / `metric` | Built-in presets |
| `fmt(du, :category, value)` | Convert + round a value to display units |

Summary functions (`slab_summary`, `foundation_group_summary`, `ec_summary`) accept either
`BuildingDesign` (auto-uses `display_units`) or `BuildingStructure` + `du` keyword.

### Member Sizing
| Function | Description |
|----------|-------------|
| `build_member_groups!` | Group similar members |
| `member_group_demands` | Get demands for a group |
| `size_steel_members!` | Steel MIP sizing (AISCChecker) |
| `size_beams!` | Dispatch by material + method |
| `size_columns!` | Dispatch by material |
| `size_members!` | Orchestrator (beams + columns) |
| `estimate_column_sizes!` | Initial column estimates |

### Foundation Sizing
| Function | Description |
|----------|-------------|
| `support_demands` | Get demands at supports |
| `size_foundations!` | Strategy-aware pipeline (`:auto`→ spread/strip/mat) |
| `group_foundations_by_reaction!` | Group similar foundations |
| `size_foundations_grouped!` | Size grouped foundations |
| `foundation_summary`, `foundation_group_summary` | Summary reports |

### Asap Integration
| Function | Description |
|----------|-------------|
| `to_asap!(struc; params)` | Convert to Asap model (uses DesignParameters) |
| `create_slab_diaphragm_shells` | Create shell elements for diaphragm |
| `to_asap_section` | Convert StructuralSizer sections to Asap.Section |

### Load Combinations
| Constant | Description |
|----------|-------------|
| `strength_1_4D` | 1.4D |
| `strength_1_2D_1_6L` | 1.2D + 1.6L (default) |
| `strength_1_2D_1_0W` | 1.2D + 1.0W + L |
| `strength_1_2D_1_0E` | 1.2D + 1.0E + L |
| `strength_0_9D_1_0W` | 0.9D + 1.0W |
| `strength_0_9D_1_0E` | 0.9D + 1.0E |
| `service` | 1.0D + 1.0L |
| `factored_pressure(combo, D, L)` | Apply load factors |

### Asap Analysis (Internal Forces & Displacements)
| Type/Function | Description | Status |
|---------------|-------------|--------|
| `Asap.ElementInternalForces` | Struct holding P, Vy, Vz, My, Mz along element | ✅ |
| `Asap.forces` | Compute internal forces for element(s) | ✅ |
| `Asap.load_envelopes` | Compute force envelopes from load cases | ✅ |
| `Asap.ElementDisplacements` | Struct holding local/global displacements | ✅ |
| `Asap.displacements` | Compute displacements along element(s) | ✅ |
| `Asap.groupbyid` | Group elements by ID | ✅ |
| `Asap.etype2DOF` | Element type to DOF mapping | ✅ |

### Section Conversion (to_asap_section)
| Section Type | Material | ACI Cracking Factor | Status |
|--------------|----------|---------------------|--------|
| `ISymmSection` | Steel | — | ✅ |
| `HSSRectSection` | Steel | — | ✅ |
| `HSSRoundSection` | Steel | — | ✅ |
| `RCColumnSection` | Concrete | 0.70 Ig (default) | ✅ |
| `RCCircularSection` | Concrete | 0.70 Ig (default) | ✅ |
| `RCBeamSection` | Concrete | 0.35 Ig (default) | ✅ |
| `GlulamSection` | Timber | — | ✅ |
| `AbstractSection` | Generic | — | ✅ (fallback) |

> **Note:** RC section conversion uses ACI 318 effective stiffness method for elastic analysis.
> Cracking factors (I_factor) reduce gross Ig to account for cracking in service conditions.

### Meshing
| Function | Description | Status |
|----------|-------------|--------|
| `Asap.Shell(corners, section)` | Auto-mesh polygon into ShellTri3 elements | ✅ |
| `Asap.mesh(corners, n)` | Get raw triangulation | ✅ |
| `target_edge_length` kwarg | Set mesh density via target element size (default 0.25m) | ✅ |
| `refinement_edge_length` / `refinement_radius` | Local mesh refinement near supports | ✅ |
| Delaunay + refinement rings | Radial local refinement for any polygon shape | ✅ |
| Structured `_t3blockx` with alternating diagonals | Uniform rectangular panels (no refinement) | ✅ |
| `_warn_mesh_density(h, Lx, Ly)` | Warns if effective n < 4 (coarse) or > 100 (fine) | ✅ |

### Shell Draping (Deflection Visualization)
| Function | Description | Status |
|----------|-------------|--------|
| `compute_draped_displacements(design)` | Superimpose shell local bending + frame global field | ✅ |
| `_idw_interpolate(qx, qy, sx, sy, vals)` | 2D inverse-distance weighted interpolation | ✅ |
| `vis_design.jl` shell rendering | Auto-drapes shells over deflected frame when both models available | ✅ |

### Postprocessing — Embodied Carbon
| Function | Description | Status |
|----------|-------------|--------|
| `element_ec` | EC for single element | ✅ |
| `compute_building_ec` | EC for full building | ✅ |
| `ec_summary` | Summary report | ✅ |
| `ElementECResult`, `BuildingECResult` | Result types | ✅ |

---

## 📊 Visualization (StructuralSynthesizer)

| Function | Description |
|----------|-------------|
| `visualize` | 3D building visualization |
| `visualize_cell_groups` | Color-coded cell groups |
| `visualize_cell_tributary` | Single cell tributaries |
| `visualize_cell_tributaries` | All cell tributaries |
| `visualize_vertex_tributaries` | Column Voronoi tributaries |
| `visualize_tributaries_combined` | Edge + vertex tributaries |
| `vis_embodied_carbon_summary` | EC breakdown chart |

---

## 📊 Visualization (StructuralPlots)

### Themes
| Theme | Description |
|-------|-------------|
| `sp_light` | Light with transparent background |
| `sp_dark` | Dark with near-black background |
| `sp_light_mono` | Light + JetBrains Mono |
| `sp_dark_mono` | Dark + JetBrains Mono |

### Colors
`sp_powderblue`, `sp_skyblue`, `sp_gold`, `sp_magenta`, `sp_orange`, `sp_ceruleanblue`, `sp_charcoalgrey`, `sp_irispurple`, `sp_darkpurple`, `sp_lilac`

### Gradients
`tension_compression`, `stress_gradient`, `blue2gold`, `purple2gold`, `magenta2gold`, `white2blue`, `white2purple`, `white2magenta`, `white2black`, `trans2blue`, `trans2purple`, `trans2magenta`, `trans2black`, `trans2white`

### Axis Styles
`graystyle!`, `structurestyle!`, `cleanstyle!`, `asapstyle!`, `blueprintstyle!`

### Figure Sizes
`fullwidth`, `halfwidth`, `thirdwidth`, `quarterwidth`, `customwidth`

---

## 🧪 Test Coverage

| Area | Test Files | Coverage |
|------|------------|----------|
| Steel members (AISC) | `test_aisc_*.jl`, `test_hss_sections.jl` | ✅ Good |
| RC columns (ACI) | `test_column_pm.jl`, `test_circular_column_pm.jl`, `test_biaxial.jl`, `test_slenderness.jl` | ✅ Good |
| RC beams | `test_rc_beam_reference.jl` (53), `test_cantilever_beam.jl` (24), `test_doubly_reinforced.jl` (29) — 106 total | ✅ Good (3 StructurePoint examples) |
| Flat plates | `test_flat_plate.jl`, `test_spanning_behavior.jl` | 🚧 In Progress |
| Vault | `test_vault.jl` | ✅ Good (validated against MATLAB) |
| Foundations (IS 456) | `test_spread_footing.jl` | ✅ Basic |
| Foundations (ACI spread) | `test_spread_aci.jl` | ✅ StructurePoint-validated |
| Foundations (ACI strip) | `test_strip_aci.jl` | ✅ StructurePoint-validated |
| Foundations (ACI mat) | `test_mat_aci.jl` | ✅ Sanity-checked |
| Foundations (integration) | `test_foundation_integration.jl` | ✅ Report + comparison |
| Tributaries | `test_tributary_workflow.jl`, `test_voronoi_tributaries.jl`, `test_strip_geometry.jl` | ✅ Good |
| Optimization | `test_column_optimization.jl`, `test_column_full.jl` | ✅ Basic |
| Multi-material MIP | `test_multi_material_mip.jl` | ✅ Steel + concrete multi-material |
| PixelFrame capacities | `test_pixelframe_capacities.jl` (54 tests — axial, flexure, shear, carbon) | ✅ Hand-verified |
| PixelFrame checker | `test_pixelframe_checker.jl` (168 tests — catalog, feasibility, MIP, objectives) | ✅ Full |

---

## 📁 Key File Locations

| What | Path |
|------|------|
| **Packages** | |
| Asap (units + FEM) | `external/Asap/src/Asap.jl` |
| StructuralPlots | `StructuralPlots/src/StructuralPlots.jl` |
| StructuralSizer | `StructuralSizer/src/StructuralSizer.jl` |
| StructuralStudies | `StructuralStudies/src/init.jl` |
| StructuralSynthesizer | `StructuralSynthesizer/src/StructuralSynthesizer.jl` |
| **Asap - Units (canonical source)** | |
| Units & type aliases | `external/Asap/src/Units/units.jl` |
| **Asap - Analysis** | |
| Force functions | `external/Asap/src/Analysis/force_functions.jl` |
| Force analysis | `external/Asap/src/Analysis/force_analysis.jl` |
| Displacements | `external/Asap/src/Analysis/displacements.jl` |
| Translations | `external/Asap/src/Analysis/translations.jl` |
| **Section conversion** | |
| to_asap_section | `StructuralSizer/src/members/sections/to_asap_section.jl` |
| **Steel sections** | |
| W shapes | `StructuralSizer/src/members/sections/steel/i_symm_section.jl` |
| HSS rectangular | `StructuralSizer/src/members/sections/steel/hss_rect_section.jl` |
| HSS round | `StructuralSizer/src/members/sections/steel/hss_round_section.jl` |
| Catalogs (CSV) | `StructuralSizer/src/members/sections/steel/catalogs/` |
| **Concrete sections** | |
| RC beam | `StructuralSizer/src/members/sections/concrete/rc_beam_section.jl` |
| RC column (rect) | `StructuralSizer/src/members/sections/concrete/rc_rect_column_section.jl` |
| RC column (circular) | `StructuralSizer/src/members/sections/concrete/rc_circular_column_section.jl` |
| RC column catalogs | `StructuralSizer/src/members/sections/concrete/catalogs/rc_columns.jl` |
| PixelFrame section | `StructuralSizer/src/members/sections/concrete/pixelframe_section.jl` |
| PixelFrame catalog | `StructuralSizer/src/members/sections/concrete/catalogs/pixelframe_catalog.jl` |
| **Design codes** | |
| AISC (all) | `StructuralSizer/src/members/codes/aisc/` |
| AISC W shapes | `StructuralSizer/src/members/codes/aisc/i_symm/` |
| AISC HSS rect | `StructuralSizer/src/members/codes/aisc/hss_rect/` |
| AISC HSS round | `StructuralSizer/src/members/codes/aisc/hss_round/` |
| ACI columns | `StructuralSizer/src/members/codes/aci/columns/` |
| ACI beams | `StructuralSizer/src/members/codes/aci/beams/` |
| PixelFrame (ACI+fib) | `StructuralSizer/src/members/codes/pixelframe/` |
| fib MC2010 (FRC shear) | `StructuralSizer/src/members/codes/fib/` |
| NDS (stub) | `StructuralSizer/src/members/codes/nds/` |
| **Floor systems** | |
| Types | `StructuralSizer/src/slabs/types.jl` |
| Flat plate (🚧) | `StructuralSizer/src/slabs/codes/concrete/flat_plate/` |
| PCA table interpolation | `StructuralSizer/src/codes/aci/pca_tables.jl` (✅) |
| Vault | `StructuralSizer/src/slabs/codes/vault/haile_unreinforced.jl` |
| Steel floors (stub) | `StructuralSizer/src/slabs/codes/steel/` |
| Timber floors (stub) | `StructuralSizer/src/slabs/codes/timber/` |
| ACI strips | `StructuralSizer/src/slabs/utils/strips.jl` |
| **Tributary (Asap)** | |
| Edge tributaries | `external/Asap/src/Tributary/` |
| DCEL skeleton | `external/Asap/src/Tributary/dcel.jl` |
| Voronoi | `external/Asap/src/Tributary/voronoi.jl` |
| Spans | `external/Asap/src/Tributary/spans.jl` |
| **Foundations** | |
| Types + Soil | `StructuralSizer/src/foundations/types.jl` |
| Options | `StructuralSizer/src/foundations/options.jl` |
| IS 456 spread footing | `StructuralSizer/src/foundations/codes/is/spread_footing.jl` |
| ACI spread footing | `StructuralSizer/src/foundations/codes/aci/spread_footing.jl` (🚧) |
| ACI strip footing | `StructuralSizer/src/foundations/codes/aci/strip_footing.jl` (🚧) |
| ACI mat — barrel | `StructuralSizer/src/foundations/codes/aci/mat/_mat.jl` (🚧) |
| ACI mat — types | `StructuralSizer/src/foundations/codes/aci/mat/types.jl` (🚧) |
| ACI mat — rigid | `StructuralSizer/src/foundations/codes/aci/mat/rigid.jl` (🚧) |
| ACI mat — Hetenyi | `StructuralSizer/src/foundations/codes/aci/mat/hetenyi.jl` (🚧) |
| ACI mat — FEA | `StructuralSizer/src/foundations/codes/aci/mat/fea.jl` (❌ stub) |
| Footing reference | `StructuralSizer/src/foundations/codes/reference/` |
| **Optimization** | |
| Core interface | `StructuralSizer/src/members/optimize/core/` |
| Discrete solver | `StructuralSizer/src/members/optimize/solvers/discrete_mip.jl` |
| Continuous solver | `StructuralSizer/src/optimize/solvers/continuous_nlp.jl` |
| Flat plate NLP problem | `StructuralSizer/src/slabs/optimize/flat_plate_problem.jl` |
| Column options | `StructuralSizer/src/members/optimize/types/columns.jl` |
| **Building workflow** | |
| Types | `StructuralSynthesizer/src/building_types.jl` |
| Design types | `StructuralSynthesizer/src/design_types.jl` |
| Design workflow | `StructuralSynthesizer/src/design_workflow.jl` |
| Initialization | `StructuralSynthesizer/src/core/initialize.jl` |
| Tributary accessors | `StructuralSynthesizer/src/core/tributary_accessors.jl` |
| Embodied carbon | `StructuralSynthesizer/src/postprocess/ec.jl` |
| Visualization | `StructuralSynthesizer/src/visualization/` |
| **Reference docs** | |
| AISC 360-16 | `StructuralSizer/src/members/codes/aisc/reference/` |
| ACI columns | `StructuralSizer/src/members/codes/aci/reference/columns/` |
| ACI beams | `StructuralSizer/src/members/codes/aci/reference/beams/` |
| Slab reference | `StructuralSizer/src/slabs/codes/concrete/reference/` |
| Vault MATLAB | `StructuralSizer/src/slabs/codes/vault/haile_reference/` |
| Footing reference | `StructuralSizer/src/foundations/codes/reference/` |

---

## 📋 Status Legend

| Icon | Meaning |
|------|---------|
| ✅ | **Full** — Implemented, tested, production-ready |
| ⚠️ | **Stub/Partial** — Type defined, limited or no implementation |
| 🚧 | **In Progress** — Currently being developed |
| ❌ | **Not Started** — Planned but not implemented |

---

## 📝 Planning Documents

| Document | Description | Status |
|----------|-------------|--------|
| `CIP_FLAT_PLATE_DESIGN_PLAN.md` | Detailed flat plate implementation plan | 🚧 Active |
| `StructuralSizer/test/TEST_OPPORTUNITIES.md` | Testing backlog | Reference |

---

## 🔄 Maintenance Notes

**When to update this file:**
- After implementing a new feature
- After adding a new type or function
- When changing API signatures
- When completing stub implementations

**Format conventions:**
- Use ✅/⚠️/🚧/❌ consistently for status
- Keep tables sorted alphabetically within sections
- Include both function names AND entry point functions
- Link to key files for navigation
