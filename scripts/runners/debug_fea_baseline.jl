#!/usr/bin/env julia
# =============================================================================
# Debug: FEA Baseline Capture
# =============================================================================
#
# Runs the FEA moment analysis on the standard 3×3 flat plate test fixture
# (same as the EFM integration test) and saves key numerical results to a
# JSON file.  This baseline is used to verify that the file restructure
# (Step 1) produces identical results.
#
# Usage:
#   julia scripts/runners/debug_fea_baseline.jl
#
# Output:
#   scripts/runners/_fea_baseline.json
# =============================================================================

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))

using Logging
using Unitful
using Unitful: @u_str
using Asap
using JSON
using Dates

using StructuralSizer
using StructuralSynthesizer

# ─────────────────────────────────────────────────────────────────────────────
# Build the standard test fixture (3-span × 3-bay, 18ft × 14ft, 16" cols)
# ─────────────────────────────────────────────────────────────────────────────

const sdl = 20.0u"psf"
const ll  = 50.0u"psf"
const h   = 7.0u"inch"

struc = with_logger(NullLogger()) do
    _skel = gen_medium_office(54.0u"ft", 42.0u"ft", 9.0u"ft", 3, 3, 1)
    _struc = BuildingStructure(_skel)
    _opts = FlatPlateOptions(
        material = RC_4000_60,
        method = FEA(),
        cover = 0.75u"inch",
        bar_size = 5,
    )
    initialize!(_struc; floor_type=:flat_plate, floor_opts=_opts)
    for c in _struc.cells
        c.sdl = uconvert(u"kN/m^2", sdl)
        c.live_load = uconvert(u"kN/m^2", ll)
    end
    for col in _struc.columns
        col.c1 = 16.0u"inch"
        col.c2 = 16.0u"inch"
    end
    to_asap!(_struc)
    _struc
end

slab = struc.slabs[1]
cell_set = Set(slab.cell_indices)
columns = StructuralSizer.find_supporting_columns(struc, cell_set)

fc  = 4000.0u"psi"
γ   = RC_4000_60.concrete.ρ
ν   = RC_4000_60.concrete.ν
wc  = ustrip(StructuralSizer.pcf, γ)
Ecs = StructuralSizer.Ec(fc, wc)

# ─────────────────────────────────────────────────────────────────────────────
# Run FEA moment analysis (default: aci_fractions strip design)
# ─────────────────────────────────────────────────────────────────────────────

cache = StructuralSizer.FEAModelCache()
result = StructuralSizer.run_moment_analysis(
    StructuralSizer.FEA(), struc, slab, columns,
    h, fc, Ecs, γ; ν_concrete=ν, verbose=false, cache=cache
)

# ─────────────────────────────────────────────────────────────────────────────
# Also run the strip-level extraction methods for comparison
# ─────────────────────────────────────────────────────────────────────────────

setup = StructuralSizer._moment_analysis_setup(struc, slab, columns, h, γ)
span_axis = setup.span_axis

# Direct strip integration
strip_result = StructuralSizer._extract_fea_strip_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)

# Nodal-smoothed isoparametric cuts
nodal_result = StructuralSizer._extract_nodal_strip_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)

# Wood–Armer per-element
wa_result = StructuralSizer._extract_wood_armer_strip_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)

# Frame-level (cell moments)
frame_result = StructuralSizer._extract_cell_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)

# ─────────────────────────────────────────────────────────────────────────────
# Collect baseline values
# ─────────────────────────────────────────────────────────────────────────────

baseline = Dict{String, Any}(
    "timestamp" => string(Dates.now()),
    "description" => "FEA baseline before file restructure",

    # Top-level MomentAnalysisResult
    "M0_kft"        => ustrip(u"kip*ft", result.M0),
    "M_neg_ext_kft" => ustrip(u"kip*ft", result.M_neg_ext),
    "M_neg_int_kft" => ustrip(u"kip*ft", result.M_neg_int),
    "M_pos_kft"     => ustrip(u"kip*ft", result.M_pos),
    "qu_psf"        => ustrip(u"psf", result.qu),
    "l1_ft"         => ustrip(u"ft", result.l1),
    "l2_ft"         => ustrip(u"ft", result.l2),
    "ln_ft"         => ustrip(u"ft", result.ln),
    "n_columns"     => length(result.column_moments),
    "column_moments_kft" => [ustrip(u"kip*ft", m) for m in result.column_moments],
    "column_shears_kip"  => [ustrip(u"kip", v) for v in result.column_shears],
    "unbalanced_moments_kft" => [ustrip(u"kip*ft", m) for m in result.unbalanced_moments],
    "Vu_max_kip"    => ustrip(u"kip", result.Vu_max),
    "pattern_loading" => result.pattern_loading,

    # Secondary direction
    "sec_M_neg_ext_kft" => isnothing(result.secondary) ? nothing : ustrip(u"kip*ft", result.secondary.M_neg_ext),
    "sec_M_neg_int_kft" => isnothing(result.secondary) ? nothing : ustrip(u"kip*ft", result.secondary.M_neg_int),
    "sec_M_pos_kft"     => isnothing(result.secondary) ? nothing : ustrip(u"kip*ft", result.secondary.M_pos),

    # FEA deflection
    "fea_delta_panel_inch" => isnothing(result.fea_Δ_panel) ? nothing : ustrip(u"inch", result.fea_Δ_panel),

    # Strip-level extraction: direct integration
    "strip_M_neg_ext_cs_Nm" => strip_result.M_neg_ext_cs,
    "strip_M_neg_int_cs_Nm" => strip_result.M_neg_int_cs,
    "strip_M_pos_cs_Nm"     => strip_result.M_pos_cs,
    "strip_M_neg_ext_ms_Nm" => strip_result.M_neg_ext_ms,
    "strip_M_neg_int_ms_Nm" => strip_result.M_neg_int_ms,
    "strip_M_pos_ms_Nm"     => strip_result.M_pos_ms,

    # Strip-level extraction: nodal cuts
    "nodal_M_neg_ext_cs_Nm" => nodal_result.M_neg_ext_cs,
    "nodal_M_neg_int_cs_Nm" => nodal_result.M_neg_int_cs,
    "nodal_M_pos_cs_Nm"     => nodal_result.M_pos_cs,
    "nodal_M_neg_ext_ms_Nm" => nodal_result.M_neg_ext_ms,
    "nodal_M_neg_int_ms_Nm" => nodal_result.M_neg_int_ms,
    "nodal_M_pos_ms_Nm"     => nodal_result.M_pos_ms,

    # Strip-level extraction: Wood–Armer
    "wa_M_neg_ext_cs_Nm" => wa_result.M_neg_ext_cs,
    "wa_M_neg_int_cs_Nm" => wa_result.M_neg_int_cs,
    "wa_M_pos_cs_Nm"     => wa_result.M_pos_cs,
    "wa_M_neg_ext_ms_Nm" => wa_result.M_neg_ext_ms,
    "wa_M_neg_int_ms_Nm" => wa_result.M_neg_int_ms,
    "wa_M_pos_ms_Nm"     => wa_result.M_pos_ms,

    # Frame-level extraction (cell moments)
    "frame_col_Mneg_Nm" => frame_result.col_Mneg,
    "frame_M_pos_Nm"    => ustrip(u"N*m", frame_result.M_pos),
    "frame_n_cells"     => frame_result.n_cells,

    # Mesh diagnostics
    "mesh_edge_length_mm" => cache.mesh_edge_length * 1000,
    "n_elements"          => length(cache.element_data),
    "n_cell_tri_groups"   => length(cache.cell_tri_indices),
)

# ─────────────────────────────────────────────────────────────────────────────
# Save to JSON
# ─────────────────────────────────────────────────────────────────────────────

outpath = joinpath(@__DIR__, "_fea_baseline.json")
open(outpath, "w") do io
    JSON.print(io, baseline, 2)
end

println("\n✓ FEA baseline saved to: $outpath")
println("  M₀ = $(round(baseline["M0_kft"], digits=1)) kip·ft")
println("  M⁻_ext = $(round(baseline["M_neg_ext_kft"], digits=1)) kip·ft")
println("  M⁻_int = $(round(baseline["M_neg_int_kft"], digits=1)) kip·ft")
println("  M⁺ = $(round(baseline["M_pos_kft"], digits=1)) kip·ft")
println("  Δ_panel = $(isnothing(baseline["fea_delta_panel_inch"]) ? "N/A" : "$(round(baseline["fea_delta_panel_inch"], digits=3))\"") ")
println("  n_elements = $(baseline["n_elements"])")
println("  mesh_edge = $(round(baseline["mesh_edge_length_mm"], digits=1)) mm")
