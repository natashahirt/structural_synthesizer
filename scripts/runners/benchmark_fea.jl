# =============================================================================
# FEA Performance Benchmark
# =============================================================================
# Runs the same building as report_fea_methods.jl but with @elapsed timing
# on each phase.  Used to measure before/after optimization impact.
# =============================================================================

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))

using Printf
using Unitful
using Unitful: @u_str
using Asap
using Logging

using StructuralSizer
using StructuralSynthesizer

const SR = StructuralSizer
const SS = StructuralSynthesizer

# ─────────────────────────────────────────────────────────────────────────────
# Build the test building (same as report_fea_methods.jl)
# ─────────────────────────────────────────────────────────────────────────────
h     = 7.0u"inch"
sdl   = 20.0u"psf"
ll    = 50.0u"psf"
fc    = 4000.0u"psi"
mat   = SR.RC_4000_60

struc = with_logger(NullLogger()) do
    _skel = SS.gen_medium_office(54.0u"ft", 42.0u"ft", 9.0u"ft", 3, 3, 1)
    _struc = SS.BuildingStructure(_skel)
    _opts = SR.FlatPlateOptions(
        material = mat,
        method   = SR.FEA(),
        cover    = 0.75u"inch",
        bar_size = 5,
    )
    SS.initialize!(_struc; floor_type=:flat_plate, floor_opts=_opts)
    for c in _struc.cells
        c.sdl       = uconvert(u"kN/m^2", sdl)
        c.live_load = uconvert(u"kN/m^2", ll)
    end
    for col in _struc.columns
        col.c1 = 16.0u"inch"
        col.c2 = 16.0u"inch"
    end
    SS.to_asap!(_struc)
    _struc
end

slab    = struc.slabs[1]
cell_set = Set(slab.cell_indices)
columns = SR.find_supporting_columns(struc, cell_set)

γ   = mat.concrete.ρ
ν   = mat.concrete.ν
wc  = ustrip(SR.pcf, γ)
Ecs = SR.Ec(fc, wc)

# ─────────────────────────────────────────────────────────────────────────────
# Timing helper
# ─────────────────────────────────────────────────────────────────────────────
const timings = Dict{String, Float64}()

function timed(f, label::String)
    # Warm-up run (first call includes JIT)
    result = f()
    GC.gc()
    # Timed run
    t = @elapsed begin
        result = f()
    end
    timings[label] = t
    @printf("  %-50s %8.3f s\n", label, t)
    return result
end

println("=" ^ 70)
println("  FEA PERFORMANCE BENCHMARK")
println("=" ^ 70)
println()

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1: Fresh build + solve (mesh generation + factorization + solve)
# ─────────────────────────────────────────────────────────────────────────────
println("Phase 1: Fresh model build + D/L solve")
println("-" ^ 70)

cache1 = timed("Fresh FEA build + solve (frame)") do
    c = SR.FEAModelCache()
    with_logger(NullLogger()) do
        SR.run_moment_analysis(
            SR.FEA(design_approach=:frame, pattern_loading=false),
            struc, slab, columns, h, fc, Ecs, γ;
            ν_concrete=ν, verbose=false, cache=c)
    end
    c
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2: Post-processing — strip extraction methods (reuse solved cache)
# ─────────────────────────────────────────────────────────────────────────────
println()
println("Phase 2: Strip extraction (reuse solved cache)")
println("-" ^ 70)

setup = SR._moment_analysis_setup(struc, slab, columns, h, γ)
span_axis = setup.span_axis

# Nodal isoparametric (the most expensive post-processing path)
timed("Nodal iso (α=0.5) strip extraction") do
    meth = SR.FEA(design_approach=:strip, moment_transform=:projection,
                   field_smoothing=:nodal, cut_method=:isoparametric,
                   iso_alpha=0.5, pattern_loading=false)
    SR._dispatch_fea_strip_extraction(meth, cache1, struc, slab, columns, span_axis)
end

# Nodal δ-band
timed("Nodal δ-band strip extraction") do
    meth = SR.FEA(design_approach=:strip, moment_transform=:projection,
                   field_smoothing=:nodal, cut_method=:delta_band,
                   pattern_loading=false)
    SR._dispatch_fea_strip_extraction(meth, cache1, struc, slab, columns, span_axis)
end

# Element δ-band
timed("Element δ-band strip extraction") do
    meth = SR.FEA(design_approach=:strip, moment_transform=:projection,
                   field_smoothing=:element, cut_method=:delta_band,
                   pattern_loading=false)
    SR._dispatch_fea_strip_extraction(meth, cache1, struc, slab, columns, span_axis)
end

# Separate faces
timed("Nodal iso (α=0.5) separate faces") do
    meth = SR.FEA(design_approach=:strip, moment_transform=:projection,
                   field_smoothing=:nodal, cut_method=:isoparametric,
                   iso_alpha=0.5, sign_treatment=:separate_faces,
                   pattern_loading=false)
    SR._dispatch_fea_strip_extraction(meth, cache1, struc, slab, columns, span_axis)
end

# Wood-Armer
timed("Wood-Armer δ-band strip extraction") do
    meth = SR.FEA(design_approach=:strip, moment_transform=:wood_armer,
                   field_smoothing=:element, cut_method=:delta_band,
                   pattern_loading=false)
    SR._dispatch_fea_strip_extraction(meth, cache1, struc, slab, columns, span_axis)
end

# Area-based extraction
timed("Area-based (projection) extraction") do
    meth = SR.FEA(design_approach=:area, moment_transform=:projection,
                   pattern_loading=false)
    SR._extract_area_design_moments(cache1, meth, span_axis; verbose=false)
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3: Pattern loading (FEA-native resolve)
# ─────────────────────────────────────────────────────────────────────────────
println()
println("Phase 3: Pattern loading (FEA-native resolve)")
println("-" ^ 70)

timed("FEA-native pattern loading (full)") do
    pat_cache = SR.FEAModelCache()
    with_logger(NullLogger()) do
        SR.run_moment_analysis(
            SR.FEA(design_approach=:frame, pattern_loading=true, pattern_mode=:fea_resolve),
            struc, slab, columns, h, fc, Ecs, γ;
            ν_concrete=ν, verbose=false, cache=pat_cache)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4: Mesh convergence (multiple mesh densities)
# ─────────────────────────────────────────────────────────────────────────────
println()
println("Phase 4: Mesh convergence (5 densities)")
println("-" ^ 70)

mesh_edges = [0.50u"m", 0.30u"m", 0.20u"m", 0.12u"m", 0.08u"m"]
for te in mesh_edges
    te_m = ustrip(u"m", te)
    timed("Mesh convergence: edge=$(te_m)m") do
        mc = SR.FEAModelCache()
        meth = SR.FEA(design_approach=:strip, moment_transform=:projection,
                       field_smoothing=:element, cut_method=:delta_band,
                       target_edge=te, pattern_loading=false)
        with_logger(NullLogger()) do
            SR.run_moment_analysis(
                meth, struc, slab, columns, h, fc, Ecs, γ;
                ν_concrete=ν, verbose=false, cache=mc)
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5: Full report equivalent (all 17 method variants)
# ─────────────────────────────────────────────────────────────────────────────
println()
println("Phase 5: Full method comparison (17 variants)")
println("-" ^ 70)

method_variants = [
    ("frm",     SR.FEA(design_approach=:frame, pattern_loading=false)),
    ("δ-proj",  SR.FEA(design_approach=:strip, moment_transform=:projection,
                        field_smoothing=:element, cut_method=:delta_band, pattern_loading=false)),
    ("δ-WA",    SR.FEA(design_approach=:strip, moment_transform=:wood_armer,
                        field_smoothing=:element, cut_method=:delta_band, pattern_loading=false)),
    ("nδ-proj", SR.FEA(design_approach=:strip, moment_transform=:projection,
                        field_smoothing=:nodal, cut_method=:delta_band, pattern_loading=false)),
    ("iso1-pr", SR.FEA(design_approach=:strip, moment_transform=:projection,
                        field_smoothing=:nodal, cut_method=:isoparametric, iso_alpha=1.0,
                        pattern_loading=false)),
    ("iso5-pr", SR.FEA(design_approach=:strip, moment_transform=:projection,
                        field_smoothing=:nodal, cut_method=:isoparametric, iso_alpha=0.5,
                        pattern_loading=false)),
    ("iso0-pr", SR.FEA(design_approach=:strip, moment_transform=:projection,
                        field_smoothing=:nodal, cut_method=:isoparametric, iso_alpha=0.0,
                        pattern_loading=false)),
    ("iso1-WA", SR.FEA(design_approach=:strip, moment_transform=:wood_armer,
                        field_smoothing=:nodal, cut_method=:isoparametric, iso_alpha=1.0,
                        pattern_loading=false)),
    ("area-pr", SR.FEA(design_approach=:area, moment_transform=:projection,
                        pattern_loading=false)),
    ("area-WA", SR.FEA(design_approach=:area, moment_transform=:wood_armer,
                        pattern_loading=false)),
    ("area-pr-30", SR.FEA(design_approach=:area, moment_transform=:projection,
                           rebar_direction=deg2rad(30.0), pattern_loading=false)),
    ("area-pr-45", SR.FEA(design_approach=:area, moment_transform=:projection,
                           rebar_direction=deg2rad(45.0), pattern_loading=false)),
    ("area-wa-30", SR.FEA(design_approach=:area, moment_transform=:wood_armer,
                          rebar_direction=deg2rad(30.0), pattern_loading=false)),
    ("area-wa-45", SR.FEA(design_approach=:area, moment_transform=:wood_armer,
                          rebar_direction=deg2rad(45.0), pattern_loading=false)),
    ("δ-noMxy", SR.FEA(design_approach=:strip, moment_transform=:no_torsion,
                        field_smoothing=:element, cut_method=:delta_band, pattern_loading=false)),
    ("area-noMxy", SR.FEA(design_approach=:area, moment_transform=:no_torsion,
                           pattern_loading=false)),
    ("iso5-sep", SR.FEA(design_approach=:strip, moment_transform=:projection,
                         field_smoothing=:nodal, cut_method=:isoparametric, iso_alpha=0.5,
                         sign_treatment=:separate_faces, pattern_loading=false)),
]

timed("All 17 method variants (post-processing only)") do
    for (lbl, meth) in method_variants
        da = meth.design_approach
        if da == :frame
            with_logger(NullLogger()) do
                SR.run_moment_analysis(meth, struc, slab, columns, h, fc, Ecs, γ;
                    ν_concrete=ν, verbose=false, cache=cache1)
            end
        elseif da == :strip
            _rax = !isnothing(meth.rebar_direction) ?
                SR._resolve_rebar_axis(meth, span_axis) : nothing
            try
                SR._dispatch_fea_strip_extraction(
                    meth, cache1, struc, slab, columns, span_axis;
                    rebar_axis=_rax, verbose=false)
            catch; end
        elseif da == :area
            try
                area_moms = SR._extract_area_design_moments(cache1, meth, span_axis; verbose=false)
                _rax = !isnothing(meth.rebar_direction) ?
                    SR._resolve_rebar_axis(meth, span_axis) : nothing
                SR._area_to_strip_envelope(
                    area_moms, cache1, struc, slab, columns, span_axis;
                    rebar_axis=_rax, verbose=false)
            catch; end
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
println()
println("=" ^ 70)
println("  TIMING SUMMARY")
println("=" ^ 70)

total = sum(values(timings))
@printf("  Total benchmark time: %.3f s\n", total)
println()

# Sort by time descending
sorted = sort(collect(timings), by=x -> -x.second)
for (label, t) in sorted
    pct = t / total * 100
    @printf("  %-50s %8.3f s  (%5.1f%%)\n", label, t, pct)
end
println()
println("=" ^ 70)
