# Structural Synthesizer — Codebase Directory

> **Last updated:** 2026-02-02
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
| `GRAVITY` | 9.80665 m/s² | Standard gravity |

---

## 🔩 Materials

### Steel
| Material | Type | Fy | Status |
|----------|------|-----|--------|
| `A992_Steel` | Structural | 50 ksi | ✅ |
| `S355_Steel` | Structural | 50 ksi | ✅ |
| `Rebar_40` | Reinforcing | 40 ksi | ✅ |
| `Rebar_60` | Reinforcing | 60 ksi | ✅ |
| `Rebar_75` | Reinforcing | 75 ksi | ✅ |
| `Rebar_80` | Reinforcing | 80 ksi | ✅ |

### Concrete
| Material | f'c | Notes | Status |
|----------|-----|-------|--------|
| `NWC_3000` | 3 ksi | Normal weight | ✅ |
| `NWC_4000` | 4 ksi | Normal weight | ✅ |
| `NWC_5000` | 5 ksi | Normal weight | ✅ |
| `NWC_6000` | 6 ksi | Normal weight | ✅ |
| `NWC_GGBS` | 4 ksi | Ground granite blast furnace slag | ✅ |
| `NWC_PFA` | 4 ksi | Pulverized fuel ash | ✅ |

### Timber
| Material | Type | Status |
|----------|------|--------|
| `Timber` | Generic | ⚠️ Type only |

---

## 🏗️ Structural Sections

### Steel — W Shapes (Wide Flange)
| Type | Catalog Functions | Design Code | Status |
|------|-------------------|-------------|--------|
| `ISymmSection` | `W(name)`, `all_W()`, `preferred_W()` | AISC 360-16 | ✅ Full |

**Key functions:** `section_area`, `section_depth`, `section_width`, `weight_per_length`

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
| `RCBeamSection` | ACI 318 | ⚠️ Stub (type + `rho` function only) |

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
| Check | Status |
|-------|--------|
| Flexure | ⚠️ Stub (`ACIChecker` defined, no implementation) |
| Shear | ⚠️ Stub |

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

### CIP Concrete
| Type | Spanning | Sizing Function | Status |
|------|----------|-----------------|--------|
| `OneWay` | One-way | `size_floor` | ⚠️ Type defined |
| `TwoWay` | Two-way | `size_floor` | ⚠️ Type defined |
| `FlatPlate` | Beamless | `size_floor` | 🚧 In Progress (see `CIP_FLAT_PLATE_DESIGN_PLAN.md`) |
| `FlatSlab` | Beamless | — | ⚠️ Type defined only |
| `PTBanded` | Two-way | — | ⚠️ Type defined only |
| `Waffle` | Two-way | — | ⚠️ Type defined only |
| `HollowCore` | One-way | `size_floor` | ⚠️ Stub |
| `Vault` | Custom | `size_floor` | ✅ Full (Haile method) |

**Flat plate functions (🚧):** `StripReinforcement`, `FlatPlatePanelResult`, `estimate_column_size`

**Vault functions:** `vault_stress_symmetric`, `vault_stress_asymmetric`, `solve_equilibrium_rise`, `parabolic_arc_length`

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
| Options Struct | Floor Types |
|----------------|-------------|
| `CIPOptions` | One-way, two-way, flat plate, flat slab |
| `VaultOptions` | Vault |
| `CompositeDeckOptions` | Composite deck |
| `TimberOptions` | CLT, DLT, NLT |

**Helper functions:** `required_floor_options`, `floor_options_help`, `floor_type`, `floor_symbol`, `infer_floor_type`

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

### Types Defined
| Type | Category | Status |
|------|----------|--------|
| `SpreadFooting` | Shallow | ✅ Design implemented (IS 456/ACI) |
| `CombinedFooting` | Shallow | ⚠️ Type only |
| `StripFooting` | Shallow | ⚠️ Type only |
| `MatFoundation` | Shallow | ⚠️ Type only |
| `DrivenPile` | Deep | ⚠️ Type only |
| `DrilledShaft` | Deep | ⚠️ Type only |
| `Micropile` | Deep | ⚠️ Type only |

### Soil Types
| Constant | Description |
|----------|-------------|
| `LOOSE_SAND`, `MEDIUM_SAND`, `DENSE_SAND` | Sand presets |
| `SOFT_CLAY`, `STIFF_CLAY`, `HARD_CLAY` | Clay presets |

### Design Functions
| Function | Status |
|----------|--------|
| `design_spread_footing` | ✅ Full (bearing, punching, one-way shear, flexure) |
| `check_spread_footing` | ✅ Full |
| `SpreadFootingResult` | ✅ Result type with dimensions, rebar, volumes |

---

## 🧮 Optimization & Sizing

### Discrete Optimization
| Function | Description | Status |
|----------|-------------|--------|
| `optimize_discrete` | Generic discrete section optimizer | ✅ |
| `size_columns` | Column sizing from demands | ✅ |
| `to_steel_demands`, `to_rc_demands` | Demand conversion | ✅ |
| `to_steel_geometry`, `to_concrete_geometry` | Geometry conversion | ✅ |

### Continuous Optimization
| Function | Description | Status |
|----------|-------------|--------|
| NLP solver | Continuous variable optimization | ❌ Not implemented |

> **Note:** Only discrete (catalog-based) optimization is currently supported. Continuous NLP optimization is not implemented.

### Sizing Options
| Struct | Material |
|--------|----------|
| `SteelColumnOptions` | Steel |
| `ConcreteColumnOptions` | Concrete |
| `SteelBeamOptions` | Steel |
| `ColumnOptions` | Union type for dispatch |

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

### Member Sizing
| Function | Description |
|----------|-------------|
| `build_member_groups!` | Group similar members |
| `member_group_demands` | Get demands for a group |
| `size_members_discrete!` | Size members in groups |
| `size_columns!` | Size all columns |
| `estimate_column_sizes!` | Initial column estimates |

### Foundation Sizing
| Function | Description |
|----------|-------------|
| `support_demands` | Get demands at supports |
| `size_foundations!` | Size all foundations |
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
| `STRENGTH_1_4D` | 1.4D |
| `STRENGTH_1_2D_1_6L` | 1.2D + 1.6L (default) |
| `STRENGTH_1_2D_1_0W` | 1.2D + 1.0W + L |
| `STRENGTH_1_2D_1_0E` | 1.2D + 1.0E + L |
| `STRENGTH_0_9D_1_0W` | 0.9D + 1.0W |
| `STRENGTH_0_9D_1_0E` | 0.9D + 1.0E |
| `SERVICE` | 1.0D + 1.0L |
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
| Function | Description |
|----------|-------------|
| `Asap.Shell(corners, section)` | Auto-triangulate polygon into ShellTri3 elements |
| `Asap.mesh(corners, n)` | Get raw triangulation |

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
| RC beams | `test_rc_beam_reference.jl` | ⚠️ Reference only |
| Flat plates | `test_flat_plate.jl`, `test_spanning_behavior.jl` | 🚧 In Progress |
| Vault | `test_vault.jl` | ✅ Good (validated against MATLAB) |
| Foundations | `test_spread_footing.jl` | ✅ Basic |
| Tributaries | `test_tributary_workflow.jl`, `test_voronoi_tributaries.jl`, `test_strip_geometry.jl` | ✅ Good |
| Optimization | `test_column_optimization.jl`, `test_column_full.jl` | ✅ Basic |

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
| **Design codes** | |
| AISC (all) | `StructuralSizer/src/members/codes/aisc/` |
| AISC W shapes | `StructuralSizer/src/members/codes/aisc/i_symm/` |
| AISC HSS rect | `StructuralSizer/src/members/codes/aisc/hss_rect/` |
| AISC HSS round | `StructuralSizer/src/members/codes/aisc/hss_round/` |
| ACI columns | `StructuralSizer/src/members/codes/aci/` |
| NDS (stub) | `StructuralSizer/src/members/codes/nds/` |
| **Floor systems** | |
| Types | `StructuralSizer/src/slabs/types.jl` |
| Flat plate (🚧) | `StructuralSizer/src/slabs/codes/concrete/flat_plate/` |
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
| Types | `StructuralSizer/src/foundations/types.jl` |
| Spread footing | `StructuralSizer/src/foundations/codes/spread_footing_is456.jl` |
| **Optimization** | |
| Core interface | `StructuralSizer/src/members/optimize/core/` |
| Discrete solver | `StructuralSizer/src/members/optimize/solvers/discrete_mip.jl` |
| Continuous solver (❌) | `StructuralSizer/src/members/optimize/solvers/continuous_nlp.jl` |
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
