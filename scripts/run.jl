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
skel = gen_medium_office(125.0u"ft", 90.0u"ft", 13.0u"ft", 5, 3, 3);
struc = BuildingStructure(skel);

# =============================================================================
# Run complete design pipeline via design_building()
# =============================================================================
# This single function call handles the entire workflow:
#   1. Initialize structure with floor type
#   2. Estimate initial column sizes
#   3. Convert to Asap analysis model
#   4. Size slabs (flat plate DDM/EFM with column P-M design)
#   5. Size foundations (grouped by similar reactions)
#   6. Populate BuildingDesign with all results

design = design_building(struc, DesignParameters(
    name = "3-Story Flat Plate Office",
    max_iterations = 100,
    
    # Column sizing options (RC columns)
    columns = ConcreteColumnOptions(
        grade = NWC_4000,
        rebar_grade = Rebar_60,
        section_shape = :rect,
    ),
    
    # Floor system options
    floor_options = FloorOptions(
        flat_plate = FlatPlateOptions(
            material = RC_4000_60,      # 4000 psi concrete, Grade 60 rebar
            analysis_method = :efm,     # Modified Direct Design Method (or :ddm, :efm)
            cover = 0.75u"inch",
            bar_size = 5,
            shear_studs=:always,
            min_h = 5.0u"inch",         # Experiment: bypass ACI min, let checks drive h
        ),
        tributary_axis = nothing,       # Isotropic tributary for flat plates
    ),
    
    # Foundation options
    foundation_options = FoundationParameters(
        soil = medium_sand,
        concrete = NWC_4000,
        rebar = Rebar_60,
        pier_width = 0.35u"m",
        min_depth = 0.4u"m",
        group_tolerance = 0.15,         # ±15% for grouping
    ),
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
    floor_options = FloorOptions(
        floor_type = :vault,
        vault = VaultOptions(
            lambda = 8.0,
            material = NWC_4000,
        ),
    ),
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
