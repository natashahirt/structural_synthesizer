using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))  # Activate root project
Pkg.instantiate()

# Note: Revise is loaded automatically via ~/.julia/config/startup.jl

using Unitful
using StructuralSizer     # Member-level sizing (materials) - re-exports units from Asap
using StructuralSynthesizer  # Geometry & BIM logic

# =============================================================================
# Generate building geometry
# =============================================================================
# gen_medium_office(Lx, Ly, floor_height, x_bays, y_bays, n_stories)
#   irregular = :none | :shift_x | :shift_y | :zigzag
#   offset    = shift amount for irregular grids (default 0.0u"m")
skel = gen_medium_office(125.0u"ft", 90.0u"ft", 13.0u"ft", 5, 3, 3);
struc = BuildingStructure(skel);

# =============================================================================
# Run complete design pipeline via design_building()
# =============================================================================
# Pipeline stages (executed in order):
#   1. Initialize structure (cells, slabs, members, tributary areas)
#   2. Estimate initial column sizes → build Asap frame model
#   3. Size slabs (flat plate DDM/EFM/FEA with column P-M design)
#   4. Reconcile columns (punching shear, slenderness, biaxial)
#   5. Size beams (if beam-based floor system)
#   6. Size foundations (grouped by similar reactions)
#   7. Capture results → BuildingDesign

design = design_building(struc, DesignParameters(
    name = "3-Story Flat Plate Office",
    max_iterations = 100,
    
    # ─── Gravity Loads (unfactored service level) ───
    # loads = GravityLoads(
    #     floor_LL  = 80.0psf,     # Floor live load (default: 80 psf)
    #     roof_LL   = 20.0psf,     # Roof live load
    #     grade_LL  = 100.0psf,    # Grade-level live load
    #     floor_SDL = 15.0psf,     # Floor superimposed dead load
    #     roof_SDL  = 15.0psf,     # Roof superimposed dead load
    #     wall_SDL  = 10.0psf,     # Wall dead load
    # ),
    
    # ─── Load Combinations (ASCE 7) ───
    # load_combinations = [strength_1_2D_1_6L],   # default
    # Presets: strength_1_4D, strength_1_2D_1_6L, strength_1_2D_1_6Lr,
    #          strength_1_2D_1_0W, strength_1_2D_1_0E,
    #          strength_0_9D_1_0W, strength_0_9D_1_0E, service
    # Custom:  LoadCombination(name=:custom, D=1.2, L=1.6, S=0.5, ...)
    
    # ─── Materials (cascading: building-level → per-member override) ───
    # Concrete presets: NWC_3000, NWC_4000, NWC_5000, NWC_6000, NWC_GGBS, NWC_PFA
    # Rebar presets:    Rebar_40, Rebar_60, Rebar_75, Rebar_80
    # RC composites:    RC_4000_60, RC_5000_60, RC_6000_60, RC_5000_75, RC_6000_75
    # Steel presets:    A992_Steel, A36_Steel, A500_Gr_B, A500_Gr_C
    materials = MaterialOptions(concrete = NWC_4000, rebar = Rebar_60),
    # Per-member override (takes priority):
    #   materials = MaterialOptions(
    #       slab   = RC_5000_60,     # 5 ksi slab concrete + Gr 60 rebar
    #       column = RC_6000_75,     # 6 ksi columns + Gr 75 rebar
    #   ),
    
    # ─── Fire Rating (ACI 216.1 / AISC) ───
    # fire_rating = 0.0,           # hours: 0, 1, 1.5, 2, 3, 4
    # fire_protection = SFRM(),    # steel only: SFRM(), IntumescentCoating(),
    #                               #             NoFireProtection(), CustomCoating(t_in, ρ_pcf)
    
    # ─── Column Sizing ───
    #   ConcreteColumnOptions  → RC columns (ACI 318 P-M interaction)
    #     section_shape:    :rect | :circular
    #     sizing_strategy:  :catalog (MIP) | :nlp (Ipopt continuous)
    #     grade:            NWC_4000, NWC_5000, ... (or grades=[...] for multi-material MIP)
    #     include_slenderness: true/false  (ACI 318 §6.6)
    #     include_biaxial:    true/false  (Bresler reciprocal load)
    #   SteelColumnOptions     → steel W/HSS/pipe columns (AISC 360)
    #     section_type:     :w | :hss | :pipe | :w_and_hss
    #     catalog:          :common | :preferred | :all
    #   PixelFrameColumnOptions → FRC + EPT columns (ACI 318-19 + fib MC2010)
    #     λ_values:         [:X4] | [:X2] | [:X2, :X4]
    columns = ConcreteColumnOptions(section_shape = :rect),
    
    # ─── Beam Sizing (for beam-based floor systems) ───
    #   ConcreteBeamOptions    → RC beams (ACI 318 flexure/shear)
    #     include_flange: true → auto T-beam from adjacent slabs
    #   SteelBeamOptions       → steel W/HSS beams (AISC 360)
    #     deflection_limit: 1/360, 1/480, etc.
    #   PixelFrameBeamOptions  → FRC + EPT beams (ACI 318-19 + fib MC2010)
    #     λ_values:         [:Y]  (Y-section for beams)
    #     objective:        MinCarbon(), MinVolume(), MinWeight(), MinCost()
    #     deflection_limit: 1/360 (or nothing for no check)
    #
    # Example — PixelFrame beams with custom catalog:
    #   beams = PixelFrameBeamOptions(
    #       L_px_values   = [125.0, 200.0] .* u"mm",
    #       fc_values     = [40.0, 57.0, 80.0] .* u"MPa",
    #       dosage_values = [20.0, 40.0] .* u"kg/m^3",
    #       objective     = MinCarbon(),
    #       deflection_limit = 1/360,
    #   )
    
    # ─── Floor System ───
    #   Type:
    #     FlatPlateOptions       → beamless two-way slab (ACI 318 Ch 8)
    #     FlatSlabOptions        → flat plate + drop panels (ACI 8.2.4)
    #     OneWayOptions          → one-way CIP slab (ACI Table 7.3.1.1)
    #     VaultOptions           → unreinforced parabolic vault
    #     CompositeDeckOptions   → steel deck + concrete fill
    #     TimberOptions          → CLT / DLT / NLT panels
    #
    #   Analysis method (flat plate/slab only):
    #     DDM()                    → Direct Design Method (ACI tables)
    #     DDM(:simplified)         → Modified DDM (0.65/0.35 coefficients)
    #     EFM()                    → Equivalent Frame Method (ASAP solver)
    #     EFM(:moment_distribution)→ EFM with Hardy Cross
    #     FEA()                    → Finite Element Analysis (shell model)
    #
    #   Punching shear resolution (ACI 318-11 §11.11):
    #     punching_strategy — when to apply reinforcement:
    #       :grow_columns    → only grow columns (default)
    #       :reinforce_last  → try columns first, reinforce if columns max out
    #       :reinforce_first → try reinforcement first, grow columns if reinf. fails
    #     punching_reinforcement — what type of reinforcement:
    #       :headed_studs_generic → generic headed studs (π d²/4, §11.11.5)
    #       :headed_studs_incon   → INCON ISS catalog studs (§11.11.5)
    #       :headed_studs_ancon   → Ancon Shearfix catalog studs (§11.11.5)
    #       :closed_stirrups      → closed stirrup reinforcement (§11.11.3)
    #       :shear_caps           → localized slab thickening at columns (§13.2.6)
    #       :column_capitals      → flared column head enlargement (§13.1.2)
    floor = FlatPlateOptions(
        method = EFM(),
        cover = 0.75u"inch",
        bar_size = 5,
        punching_strategy = :reinforce_first,
        punching_reinforcement = :headed_studs_generic,
        min_h = 5.0u"inch",        # Override ACI min thickness (nothing = use ACI Table 8.3.1.1)
        # grouping = :by_floor,     # :individual | :by_floor | :building_wide
        # deflection_limit = :L_360,# :L_240 | :L_360 | :L_480
        # objective = MinVolume(),  # MinVolume() | MinWeight() | MinCost() | MinCarbon()
    ),
    
    # ─── Foundation Options ───
    #   strategy: :auto       → heuristic (spread → strip → mat by coverage ratio)
    #             :all_spread → force isolated spread footings
    #             :all_strip  → force strip/combined footings
    #             :mat        → force mat foundation
    #   Soil presets: loose_sand, medium_sand, dense_sand,
    #                 soft_clay, stiff_clay, hard_clay
    foundation_options = FoundationParameters(
        soil = medium_sand,
        pier_width = 0.35u"m",
        min_depth = 0.4u"m",
        group_tolerance = 0.15,
        options = FoundationOptions(
            strategy = :auto,
            mat_coverage_threshold = 0.50,
            # spread = SpreadFootingOptions(min_depth = 12.0u"inch"),
            # strip  = StripFootingOptions(min_depth = 12.0u"inch"),
            # mat    = MatFootingOptions(
            #     analysis_method = RigidMat(),   # or ShuklaAFM(), WinklerFEA()
            #     min_depth = 24.0u"inch",
            # ),
        ),
    ),
    
    # ─── Display & Output ───
    # display_units = imperial,    # imperial | metric (controls summary output units)
    # optimize_for  = :weight,     # :weight | :carbon | :cost
));

# =============================================================================
# Design Summary
# =============================================================================
println("\n" * "="^60)
println("DESIGN SUMMARY: $(design.params.name)")
println("="^60)
println("Compute time: $(round(design.compute_time_s, digits=2))s")
println("All checks pass: $(all_ok(design))")
println("Critical element: $(design.summary.critical_element)")
println("Critical ratio: $(round(design.summary.critical_ratio, digits=3))")

# Slab summary (display units from design params)
du = design.params.display_units
println("\n--- Slabs ($(length(design.slabs))) ---")
for (idx, slab_result) in sort(collect(design.slabs), by=first)
    println("  Slab $idx: h=$(fmt(du, :thickness, slab_result.thickness)) | deflection_ok=$(slab_result.deflection_ok)")
end

# Column summary  
println("\n--- Columns ($(length(design.columns))) ---")
for (idx, col_result) in sort(collect(design.columns), by=first)
    println("  Column $idx: $(col_result.section_size) | ok=$(col_result.ok)")
end

# Foundation summary
println("\n--- Foundations ($(length(design.foundations))) ---")
for (idx, fdn_result) in sort(collect(design.foundations), by=first)
    L_disp = fmt(du, :length, fdn_result.length)
    B_disp = fmt(du, :length, fdn_result.width)
    println("  Foundation $idx: $(L_disp) × $(B_disp) (group $(fdn_result.group_id)) | ok=$(fdn_result.ok)")
end

# =============================================================================
# Detailed Reports (now accept design → auto-use display_units)
# =============================================================================
slab_summary(design)
foundation_group_summary(design)

# =============================================================================
# Build Global Analysis Model (Frame + Shell)
# =============================================================================
# After design is complete, build a separate frame+shell model for global
# deflection analysis. This preserves the original struc.asap_model (frame-only)
# while adding shell elements for the designed slabs.
build_analysis_model!(design; load_combination=service, target_edge_length=0.5u"m");

# =============================================================================
# Visualizations
# =============================================================================

# 1. Structure with column tributary areas (Voronoi)
visualize(struc, color_by=:tributary_vertex)

# 2. Sized design (slabs, foundations, member utilization)
visualize(design, show_sections=:solid)

# 3. Deflected design
visualize(design, mode=:deflected, color_by=:displacement_global, deflection_scale=1.0)

# =============================================================================
# Embodied Carbon
# =============================================================================
ec_summary(design)
vis_embodied_carbon_summary(struc)

# =============================================================================
# Vault Design + Visualization
# =============================================================================
println("\n\n" * "="^60)
println("VAULT DESIGN")
println("="^60)

skel_v = gen_medium_office(30.0u"ft", 24.0u"ft", 12.0u"ft", 2, 2, 1)
struc_v = BuildingStructure(skel_v)

design_v = design_building(struc_v, DesignParameters(
    name = "1-Story Vault Office",
    floor = VaultOptions(lambda = 8.0, material = NWC_4000),
))

println("Compute time: $(round(design_v.compute_time_s, digits=2))s")
println("All checks pass: $(all_ok(design_v))")

# Vault-specific summary
for (i, slab) in enumerate(struc_v.slabs)
    r = slab.result
    r isa VaultResult || continue
    println("\n  Vault $i:")
    println("    Span:  $(round(u"ft", slab.spans.primary, digits=1))")
    println("    Rise:  $(round(u"inch", r.rise, digits=1))")
    println("    Shell: $(round(u"inch", r.thickness, digits=2))")
    println("    λ:     $(round(ustrip(slab.spans.primary / r.rise), digits=1))")
    println("    H_dead: $(round(u"kip/ft", r.thrust_dead, digits=2))")
    println("    H_live: $(round(u"kip/ft", r.thrust_live, digits=2))")
    println("    σ/σ_allow: $(round(r.stress_check.ratio, digits=3))")
    println("    Adequate: $(is_adequate(r))")
end

# Vault visualization (3D + cross-section)
visualize_vault(design_v)

# Also works with the standard visualize() — vaults show as parabolic arches
visualize(design_v, show_sections=:solid)
