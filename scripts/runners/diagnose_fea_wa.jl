#!/usr/bin/env julia
# Diagnostic script: inspect FEA_WA element-level behavior

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))

using StructuralSizer
using StructuralSynthesizer
using Unitful
using Unitful: @u_str
using Asap
using Logging

# Build the same 3×3 bay structure used in the report (Step 4F)
fea_struc = with_logger(NullLogger()) do
    _skel = gen_medium_office(54.0u"ft", 42.0u"ft", 9.0u"ft", 3, 3, 1)
    _struc = BuildingStructure(_skel)
    _opts = FlatPlateOptions(
        material = RC_4000_60,
        method = FEA(),
        cover = 0.75u"inch",
        bar_size = 5,
    )
    initialize!(_struc; floor_type=:flat_plate, floor_opts=_opts)
    for c_fea in _struc.cells
        c_fea.sdl = uconvert(u"kN/m^2", 20.0u"psf")
        c_fea.live_load = uconvert(u"kN/m^2", 50.0u"psf")
    end
    for col_fea in _struc.columns
        col_fea.c1 = 16.0u"inch"
        col_fea.c2 = 16.0u"inch"
    end
    to_asap!(_struc)
    _struc
end

function run_diagnostic(fea_struc)
    slab = fea_struc.slabs[1]
    h = 7.0u"inch"
    fc = 4000.0u"psi"
    γ  = RC_4000_60.concrete.ρ
    ν  = RC_4000_60.concrete.ν
    wc = ustrip(StructuralSizer.pcf, γ)
    Ecs = StructuralSizer.Ec(fc, wc)

    cell_set = Set(slab.cell_indices)
    columns = StructuralSizer.find_supporting_columns(fea_struc, cell_set)

    cache = StructuralSizer.FEAModelCache()
    fea_result = StructuralSizer.run_moment_analysis(
        StructuralSizer.FEA(), fea_struc, slab, columns,
        h, fc, Ecs, γ; ν_concrete=ν, verbose=false, cache=cache
    )

    span_axis = StructuralSizer._get_span_axis(slab)
    ax, ay = span_axis

    println("Span axis: $span_axis")
    println("Number of elements: $(length(cache.element_data))")
    println()

    # Pick center cell of 3×3
    ci = slab.cell_indices[5]
    geom = StructuralSizer._cell_geometry_m(fea_struc, ci; _cache=cache.cell_geometries)
    tri_idx = get(cache.cell_tri_indices, ci, Int[])

    println("Cell $ci: $(length(tri_idx)) triangles")
    println("Cell centroid: $(geom.centroid)")
    println()

    n_mohr_sag = 0
    n_mohr_hog = 0
    n_wa_bot_zero = 0
    n_wa_top_zero = 0
    n_wa_proj_zero_bot = 0

    mohr_vals = Float64[]
    wa_bot_proj_lcs = Float64[]
    wa_bot_proj_glb = Float64[]
    wa_top_proj_lcs = Float64[]

    for (j, k) in enumerate(tri_idx)
        ed = cache.element_data[k]

        # Mohr's circle in LCS (what _integrate_at_subset does)
        axl = (ax * ed.ex[1] + ay * ed.ex[2],
               ax * ed.ey[1] + ay * ed.ey[2])
        Mn_mohr = ed.Mxx * axl[1]^2 + ed.Myy * axl[2]^2 + 2 * ed.Mxy * axl[1] * axl[2]

        wa = StructuralSizer.wood_armer(ed.Mxx, ed.Myy, ed.Mxy)

        Mn_bot_lcs = wa.Mx_bot * axl[1]^2 + wa.My_bot * axl[2]^2
        Mn_top_lcs = wa.Mx_top * axl[1]^2 + wa.My_top * axl[2]^2

        Mn_bot_glb = wa.Mx_bot * ax^2 + wa.My_bot * ay^2
        Mn_top_glb = wa.Mx_top * ax^2 + wa.My_top * ay^2

        push!(mohr_vals, Mn_mohr)
        push!(wa_bot_proj_lcs, Mn_bot_lcs)
        push!(wa_bot_proj_glb, Mn_bot_glb)
        push!(wa_top_proj_lcs, Mn_top_lcs)

        if Mn_mohr < 0
            n_mohr_sag += 1
            if Mn_bot_lcs ≈ 0.0
                n_wa_proj_zero_bot += 1
            end
        else
            n_mohr_hog += 1
        end

        wa.Mx_bot ≈ 0.0 && wa.My_bot ≈ 0.0 && (n_wa_bot_zero += 1)
        wa.Mx_top ≈ 0.0 && wa.My_top ≈ 0.0 && (n_wa_top_zero += 1)

        if j <= 8
            println("Elem $k: LCS ex=$(round.(ed.ex, digits=3)) ey=$(round.(ed.ey, digits=3))")
            println("  Mxx=$(round(ed.Mxx, digits=1)) Myy=$(round(ed.Myy, digits=1)) Mxy=$(round(ed.Mxy, digits=1))")
            println("  axl=$(round.(axl, digits=3))")
            println("  Mohr Mn=$(round(Mn_mohr, digits=1))  (+hog/-sag)")
            println("  WA raw: Mx_bot=$(round(wa.Mx_bot, digits=1)) My_bot=$(round(wa.My_bot, digits=1)) " *
                    "Mx_top=$(round(wa.Mx_top, digits=1)) My_top=$(round(wa.My_top, digits=1))")
            println("  WA proj LCS: bot=$(round(Mn_bot_lcs, digits=1)) top=$(round(Mn_top_lcs, digits=1))")
            println("  WA proj GLB: bot=$(round(Mn_bot_glb, digits=1)) top=$(round(Mn_top_glb, digits=1))")
            println()
        end
    end

    println("=== Summary for cell $ci (center cell) ===")
    println("Mohr sagging: $n_mohr_sag / $(length(tri_idx))")
    println("Mohr hogging: $n_mohr_hog / $(length(tri_idx))")
    println("WA bot = 0 (both Mx,My): $n_wa_bot_zero / $(length(tri_idx))")
    println("WA top = 0 (both Mx,My): $n_wa_top_zero / $(length(tri_idx))")
    println("WA proj LCS bot ≈ 0 among sagging: $n_wa_proj_zero_bot / $n_mohr_sag")
    println()

    # δ-band analysis
    cell_to_cols = StructuralSizer._build_cell_to_columns(columns)
    cell_cols = get(cell_to_cols, ci, eltype(columns)[])
    δ = StructuralSizer._section_cut_bandwidth(cache, cell_cols)
    half_δ = δ / 2
    println("δ = $(round(δ * 1000, digits=0)) mm  (half_δ = $(round(half_δ * 1000, digits=0)) mm)")

    cx, cy = geom.centroid
    cent_s = ax * cx + ay * cy
    n_in_band = 0
    n_in_band_sag = 0
    wa_bot_band_lcs = 0.0
    wa_bot_band_glb = 0.0
    mohr_band = 0.0
    for (j, k) in enumerate(tri_idx)
        ed = cache.element_data[k]
        elem_s = ax * ed.cx + ay * ed.cy
        abs(elem_s - cent_s) > half_δ && continue
        n_in_band += 1
        mohr_vals[j] < 0 && (n_in_band_sag += 1)
        wa_bot_band_lcs += wa_bot_proj_lcs[j] * ed.area
        wa_bot_band_glb += wa_bot_proj_glb[j] * ed.area
        mohr_band += mohr_vals[j] * ed.area
    end
    println("Elements in midspan δ-band: $n_in_band / $(length(tri_idx))")
    println("  of which sagging (Mohr): $n_in_band_sag")
    println()
    println("Mohr integration at centroid: $(round(mohr_band / δ, digits=1)) N·m")
    println("  → M⁺ = $(round(max(0.0, -mohr_band / δ), digits=1)) N·m")
    println("WA bot (LCS proj) at centroid: $(round(wa_bot_band_lcs / δ, digits=1)) N·m")
    println("WA bot (GLB proj) at centroid: $(round(wa_bot_band_glb / δ, digits=1)) N·m")

    println("\n=== LCS alignment check ===")
    ex_devs = Float64[]
    for k in tri_idx
        ed = cache.element_data[k]
        push!(ex_devs, sqrt((ed.ex[1] - 1.0)^2 + ed.ex[2]^2))
    end
    println("ex deviation from (1,0): min=$(round(minimum(ex_devs), digits=4)) " *
            "max=$(round(maximum(ex_devs), digits=4)) " *
            "mean=$(round(sum(ex_devs)/length(ex_devs), digits=4))")
    if maximum(ex_devs) > 0.01
        println("  → LCS NOT aligned with global! This is the root cause.")
        # Show distribution
        n_aligned = count(d -> d < 0.01, ex_devs)
        n_45deg = count(d -> 0.3 < d < 1.0, ex_devs)
        n_90deg = count(d -> d > 1.3, ex_devs)
        println("  Roughly aligned (<0.01): $n_aligned")
        println("  ~45° rotated (0.3-1.0): $n_45deg")
        println("  ~90° rotated (>1.3): $n_90deg")
    else
        println("  → LCS approximately aligned with global.")
    end

    # === The correct approach ===
    # 1. Rotate element-local moments to global frame
    # 2. Negate to convert Asap convention (pos=hogging) to WA convention (pos=sagging)
    # 3. Apply WA in global frame
    # 4. Project to span using global axes
    println("\n=== Alternative: Rotate to global, negate sign, then WA ===")
    wa_bot_correct_sum = 0.0
    wa_top_correct_sum = 0.0
    wa_bot_noneg_sum = 0.0  # without negation for comparison
    wa_top_noneg_sum = 0.0
    for (j, k) in enumerate(tri_idx)
        ed = cache.element_data[k]
        elem_s = ax * ed.cx + ay * ed.cy
        abs(elem_s - cent_s) > half_δ && continue

        # Rotate element-local moments to global frame
        # M_global = R * M_local * R^T where R = [ex ey] (columns = local axes in global)
        ex1, ex2 = ed.ex
        ey1, ey2 = ed.ey
        Mxx_g = ed.Mxx * ex1^2 + ed.Myy * ey1^2 + 2 * ed.Mxy * ex1 * ey1
        Myy_g = ed.Mxx * ex2^2 + ed.Myy * ey2^2 + 2 * ed.Mxy * ex2 * ey2
        Mxy_g = ed.Mxx * ex1 * ex2 + ed.Myy * ey1 * ey2 + ed.Mxy * (ex1 * ey2 + ex2 * ey1)

        # Without negation (WA assumes pos=sagging, Asap has pos=hogging)
        wa_noneg = StructuralSizer.wood_armer(Mxx_g, Myy_g, Mxy_g)
        Mn_bot_noneg = wa_noneg.Mx_bot * ax^2 + wa_noneg.My_bot * ay^2
        Mn_top_noneg = wa_noneg.Mx_top * ax^2 + wa_noneg.My_top * ay^2
        wa_bot_noneg_sum += Mn_bot_noneg * ed.area
        wa_top_noneg_sum += Mn_top_noneg * ed.area

        # With negation: convert Asap convention to WA convention
        wa_neg = StructuralSizer.wood_armer(-Mxx_g, -Myy_g, -Mxy_g)
        Mn_bot_neg = wa_neg.Mx_bot * ax^2 + wa_neg.My_bot * ay^2
        Mn_top_neg = wa_neg.Mx_top * ax^2 + wa_neg.My_top * ay^2
        wa_bot_correct_sum += Mn_bot_neg * ed.area
        wa_top_correct_sum += Mn_top_neg * ed.area
    end
    println("Without negation:")
    println("  WA bot (sagging) at centroid: $(round(wa_bot_noneg_sum / δ, digits=1)) N·m")
    println("  WA top (hogging) at centroid: $(round(-wa_top_noneg_sum / δ, digits=1)) N·m")
    println("With negation (correct):")
    println("  WA bot (sagging) at centroid: $(round(wa_bot_correct_sum / δ, digits=1)) N·m")
    println("  WA top (hogging) at centroid: $(round(-wa_top_correct_sum / δ, digits=1)) N·m")
    println()
    println("Reference (Mohr): M⁺ = $(round(max(0.0, -mohr_band / δ), digits=1)) N·m (sagging)")
    println("  WA should be ≥ Mohr (conservative envelope)")
end

run_diagnostic(fea_struc)
