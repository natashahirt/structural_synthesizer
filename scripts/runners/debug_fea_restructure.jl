#!/usr/bin/env julia
# =============================================================================
# Debug: Verify FEA File Restructure (Step 1)
# =============================================================================
#
# Loads the baseline JSON from debug_fea_baseline.jl and re-runs the same
# FEA analysis.  Compares every saved value and reports PASS/FAIL.
#
# Usage:
#   1. Run debug_fea_baseline.jl BEFORE the restructure
#   2. Perform the file restructure (replace fea.jl with fea/ barrel)
#   3. Run this script to verify identical results
#
# Output:
#   Prints a comparison table to stdout.  Exits with code 1 on failure.
# =============================================================================

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))

using Logging
using Unitful
using Unitful: @u_str
using Asap
using JSON

using StructuralSizer
using StructuralSynthesizer

# ─────────────────────────────────────────────────────────────────────────────
# Load baseline
# ─────────────────────────────────────────────────────────────────────────────

baseline_path = joinpath(@__DIR__, "_fea_baseline.json")
if !isfile(baseline_path)
    error("Baseline not found at $baseline_path — run debug_fea_baseline.jl first.")
end
baseline = JSON.parsefile(baseline_path)

# ─────────────────────────────────────────────────────────────────────────────
# Re-build the same test fixture
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
# Run FEA
# ─────────────────────────────────────────────────────────────────────────────

cache = StructuralSizer.FEAModelCache()
result = StructuralSizer.run_moment_analysis(
    StructuralSizer.FEA(), struc, slab, columns,
    h, fc, Ecs, γ; ν_concrete=ν, verbose=false, cache=cache
)

setup = StructuralSizer._moment_analysis_setup(struc, slab, columns, h, γ)
span_axis = setup.span_axis

strip_result = StructuralSizer._extract_fea_strip_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)
nodal_result = StructuralSizer._extract_nodal_strip_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)
wa_result = StructuralSizer._extract_wood_armer_strip_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)
frame_result = StructuralSizer._extract_cell_moments(
    cache, struc, slab, columns, span_axis; verbose=false
)

# ─────────────────────────────────────────────────────────────────────────────
# Compare
# ─────────────────────────────────────────────────────────────────────────────

n_pass = 0
n_fail = 0
# Mesh is non-deterministic (Delaunay triangulator randomness), so FEA results
# vary ~1-5% between runs even with identical code.  Use 10% tolerance for
# mesh-dependent quantities.  For mesh-invariant quantities (M₀, qu, etc.)
# callers pass a tighter tol.
const TOL_MESH = 0.10   # 10% for mesh-dependent FEA results
const TOL_EXACT = 1e-6  # for mesh-invariant quantities

function check(label, computed, reference; tol=TOL_MESH)
    global n_pass, n_fail
    if isnothing(reference)
        if isnothing(computed)
            n_pass += 1
            println("  ✓ $label: both nothing")
        else
            n_fail += 1
            println("  ✗ $label: expected nothing, got $computed")
        end
        return
    end
    ref = Float64(reference)
    val = Float64(computed)
    if abs(ref) < 1e-12
        diff = abs(val - ref)
        ok = diff < tol
    else
        diff = abs(val - ref) / abs(ref)
        ok = diff < tol
    end
    if ok
        n_pass += 1
        println("  ✓ $label: $(round(val, sigdigits=8)) ≈ $(round(ref, sigdigits=8))")
    else
        n_fail += 1
        println("  ✗ $label: $(round(val, sigdigits=8)) ≠ $(round(ref, sigdigits=8))  (Δ=$(round(diff*100, sigdigits=3))%)")
    end
end

println("\n" * "="^70)
println("FEA RESTRUCTURE VERIFICATION")
println("="^70)

println("\n── Top-Level MomentAnalysisResult ──")
check("M₀",        ustrip(u"kip*ft", result.M0),        baseline["M0_kft"];   tol=TOL_EXACT)
check("M⁻_ext",    ustrip(u"kip*ft", result.M_neg_ext), baseline["M_neg_ext_kft"])
check("M⁻_int",    ustrip(u"kip*ft", result.M_neg_int), baseline["M_neg_int_kft"])
check("M⁺",        ustrip(u"kip*ft", result.M_pos),     baseline["M_pos_kft"])
check("qu",         ustrip(u"psf", result.qu),            baseline["qu_psf"];   tol=TOL_EXACT)
check("Vu_max",     ustrip(u"kip", result.Vu_max),       baseline["Vu_max_kip"])

println("\n── Column Moments ──")
col_ref = baseline["column_moments_kft"]
for i in 1:length(result.column_moments)
    check("col_M[$i]", ustrip(u"kip*ft", result.column_moments[i]), col_ref[i])
end

println("\n── Column Shears ──")
shear_ref = baseline["column_shears_kip"]
for i in 1:length(result.column_shears)
    check("col_V[$i]", ustrip(u"kip", result.column_shears[i]), shear_ref[i])
end

println("\n── Secondary Direction ──")
check("sec M⁻_ext", isnothing(result.secondary) ? nothing : ustrip(u"kip*ft", result.secondary.M_neg_ext), baseline["sec_M_neg_ext_kft"])
check("sec M⁻_int", isnothing(result.secondary) ? nothing : ustrip(u"kip*ft", result.secondary.M_neg_int), baseline["sec_M_neg_int_kft"])
check("sec M⁺",     isnothing(result.secondary) ? nothing : ustrip(u"kip*ft", result.secondary.M_pos),     baseline["sec_M_pos_kft"])

println("\n── FEA Deflection ──")
check("Δ_panel", isnothing(result.fea_Δ_panel) ? nothing : ustrip(u"inch", result.fea_Δ_panel), baseline["fea_delta_panel_inch"])

println("\n── Strip Integration (direct) ──")
check("strip ext⁻ CS", strip_result.M_neg_ext_cs, baseline["strip_M_neg_ext_cs_Nm"])
check("strip int⁻ CS", strip_result.M_neg_int_cs, baseline["strip_M_neg_int_cs_Nm"])
check("strip pos CS",  strip_result.M_pos_cs,      baseline["strip_M_pos_cs_Nm"])
check("strip ext⁻ MS", strip_result.M_neg_ext_ms, baseline["strip_M_neg_ext_ms_Nm"])
check("strip int⁻ MS", strip_result.M_neg_int_ms, baseline["strip_M_neg_int_ms_Nm"])
check("strip pos MS",  strip_result.M_pos_ms,      baseline["strip_M_pos_ms_Nm"])

println("\n── Nodal Cuts ──")
check("nodal ext⁻ CS", nodal_result.M_neg_ext_cs, baseline["nodal_M_neg_ext_cs_Nm"])
check("nodal int⁻ CS", nodal_result.M_neg_int_cs, baseline["nodal_M_neg_int_cs_Nm"])
check("nodal pos CS",  nodal_result.M_pos_cs,      baseline["nodal_M_pos_cs_Nm"])
check("nodal ext⁻ MS", nodal_result.M_neg_ext_ms, baseline["nodal_M_neg_ext_ms_Nm"])
check("nodal int⁻ MS", nodal_result.M_neg_int_ms, baseline["nodal_M_neg_int_ms_Nm"])
check("nodal pos MS",  nodal_result.M_pos_ms,      baseline["nodal_M_pos_ms_Nm"])

println("\n── Wood–Armer ──")
check("WA ext⁻ CS", wa_result.M_neg_ext_cs, baseline["wa_M_neg_ext_cs_Nm"])
check("WA int⁻ CS", wa_result.M_neg_int_cs, baseline["wa_M_neg_int_cs_Nm"])
check("WA pos CS",  wa_result.M_pos_cs,      baseline["wa_M_pos_cs_Nm"])
check("WA ext⁻ MS", wa_result.M_neg_ext_ms, baseline["wa_M_neg_ext_ms_Nm"])
check("WA int⁻ MS", wa_result.M_neg_int_ms, baseline["wa_M_neg_int_ms_Nm"])
check("WA pos MS",  wa_result.M_pos_ms,      baseline["wa_M_pos_ms_Nm"])

println("\n── Frame-Level (Cell Moments) ──")
check("frame M⁺", ustrip(u"N*m", frame_result.M_pos), baseline["frame_M_pos_Nm"])
check("frame n_cells", frame_result.n_cells, baseline["frame_n_cells"]; tol=TOL_EXACT)
frame_col_ref = baseline["frame_col_Mneg_Nm"]
for i in 1:length(frame_result.col_Mneg)
    check("frame col_M⁻[$i]", frame_result.col_Mneg[i], frame_col_ref[i])
end

println("\n── Mesh Diagnostics ──")
check("mesh_edge_mm", cache.mesh_edge_length * 1000, baseline["mesh_edge_length_mm"])
check("n_elements",   length(cache.element_data),     baseline["n_elements"])

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "="^70)
total = n_pass + n_fail
if n_fail == 0
    println("ALL $total CHECKS PASSED ✓")
    println("="^70)
else
    println("$n_fail / $total CHECKS FAILED ✗")
    println("="^70)
    exit(1)
end
