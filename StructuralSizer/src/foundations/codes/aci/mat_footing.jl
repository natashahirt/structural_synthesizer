# =============================================================================
# ACI 336.2R / ACI 318-14 Rigid Mat Foundation Design
# =============================================================================
#
# Analytical approach for mat foundations assuming rigid behavior:
#   1. Plan sizing (building footprint + overhang)
#   2. Uniform/linear soil pressure from resultant loads
#   3. Punching shear at each column → governs thickness
#   4. One-way shear in each direction (strip statics)
#   5. Flexural reinforcement from strip statics (x and y directions)
#
# Punching checks include biaxial unbalanced moment transfer via the shared
# punching_check() utility (ACI §8.4.4.2).
#
# Fully Unitful throughout.
# Reference: ACI 336.2R-88 §4.2 "Rigid Mat Analysis"
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# Internal: rigid mat strip statics (Kramrisch simplified)
# ─────────────────────────────────────────────────────────────────────────────

"""
Governing moment for a strip of the mat in one direction.

Treats column-line strips as continuous beams: negative ≈ wL²/10,
positive ≈ wL²/12 (interior); end spans use wL²/11.

Returns (M_pos, M_neg) both as positive Unitful Torques.
"""
function _rigid_mat_strip_moments(qu::Pressure, trib_width::Length,
                                   spans::Vector{<:Length})
    w = qu * trib_width  # force per length

    M_neg = zero(w * spans[1]^2)
    M_pos = zero(w * spans[1]^2)

    n = length(spans)
    for (i, Ls) in enumerate(spans)
        wL2 = w * Ls^2
        if n == 1
            M_neg = max(M_neg, wL2 / 2)
        elseif i == 1 || i == n
            M_neg = max(M_neg, wL2 / 10)
            M_pos = max(M_pos, wL2 / 11)
        else
            M_neg = max(M_neg, wL2 / 10)
            M_pos = max(M_pos, wL2 / 12)
        end
    end

    return (M_pos = M_pos, M_neg = M_neg)
end

"""Extract sorted span lengths from sorted unique column coordinates."""
function _unique_spans(coords::Vector{<:Length})
    vals = sort(unique(round.(ustrip.(u"ft", coords); digits = 3)))
    length(vals) < 2 && return Length[]
    return [(vals[i + 1] - vals[i]) * u"ft" for i in 1:length(vals) - 1]
end

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

"""
    design_mat_footing(demands, positions, soil; opts) → MatFootingResult

Design a rigid mat foundation per ACI 336.2R / ACI 318-14.

Punching checks at each column include biaxial unbalanced moment transfer
(Mux, Muy from each column's FoundationDemand).

# Arguments
- `demands::Vector{FoundationDemand}`: Factored & service loads per column.
- `positions::Vector{NTuple{2,<:Length}}`: (x, y) column positions.
- `soil::Soil`: `qa` = net allowable bearing pressure.

# Returns
`MatFootingResult` with SI output quantities.
"""
function design_mat_footing(
    demands::Vector{<:FoundationDemand},
    positions::Vector{<:NTuple{2, <:Length}},
    soil::Soil;
    opts::MatFootingOptions = MatFootingOptions()
)
    N = length(demands)
    length(positions) == N ||
        throw(DimensionMismatch("positions and demands must match"))

    # Material / options
    fc    = opts.material.concrete.fc′
    fy    = opts.material.rebar.Fy
    λ     = something(opts.λ, opts.material.concrete.λ)
    cover = opts.cover
    db_x  = bar_diameter(opts.bar_size_x)
    db_y  = bar_diameter(opts.bar_size_y)
    ϕf    = opts.ϕ_flexure
    ϕv    = opts.ϕ_shear

    xs = [p[1] for p in positions]
    ys = [p[2] for p in positions]

    Pu_total = sum(d.Pu for d in demands)
    Ps_total = sum(d.Ps for d in demands)

    # =====================================================================
    # Step 1: Plan Sizing
    # =====================================================================
    x_min, x_max = extrema(xs)
    y_min, y_max = extrema(ys)

    if opts.edge_overhang !== nothing
        overhang = opts.edge_overhang
    else
        x_sp = _unique_spans(xs)
        y_sp = _unique_spans(ys)
        min_span = min(
            isempty(x_sp) ? 20.0u"ft" : minimum(x_sp),
            isempty(y_sp) ? 20.0u"ft" : minimum(y_sp))
        overhang = max(min_span / 6, 2.0u"ft")
    end

    B  = (x_max - x_min) + 2overhang   # width  (x)
    Lm = (y_max - y_min) + 2overhang   # length (y)

    # Local coordinates (origin at mat corner)
    x_left = x_min - overhang
    y_bot  = y_min - overhang
    xs_loc = xs .- x_left
    ys_loc = ys .- y_bot

    qu = Pu_total / (B * Lm)

    # Bearing utilization (convert to common unit to avoid mixed-unit ustrip)
    util_bearing = to_kip(Ps_total) / to_kip(soil.qa * B * Lm)
    util_bearing > 1.0 && @warn "Mat bearing exceeds allowable: util=$(round(util_bearing, digits=3))"

    # =====================================================================
    # Step 2: Identify Grid Spans
    # =====================================================================
    x_spans = _unique_spans(xs_loc)
    y_spans = _unique_spans(ys_loc)

    # =====================================================================
    # Step 3: Thickness from Punching Shear
    # =====================================================================
    # Estimate column size from largest Pu
    Pu_max_kip = to_kip(maximum(d.Pu for d in demands))
    c_est = max(12.0, ceil(sqrt(Pu_max_kip / 0.5) / 3.0) * 3.0) * u"inch"
    c_est = min(c_est, 36.0u"inch")

    h = opts.min_depth
    h_incr = opts.depth_increment

    for iter in 1:60
        d_eff = h - cover - max(db_x, db_y)
        d_eff < 6.0u"inch" && (h += h_incr; continue)

        all_ok = true
        for j in 1:N
            at_xmin = xs_loc[j] < overhang + 0.5u"ft"
            at_xmax = xs_loc[j] > (B - overhang - 0.5u"ft")
            at_ymin = ys_loc[j] < overhang + 0.5u"ft"
            at_ymax = ys_loc[j] > (Lm - overhang - 0.5u"ft")
            is_edge = at_xmin || at_xmax || at_ymin || at_ymax

            pos_sym = is_edge ? :edge : :interior
            Ac = is_edge ? (c_est + d_eff / 2) * (c_est + d_eff) :
                           (c_est + d_eff) * (c_est + d_eff)
            Vu_p = max(uconvert(u"lbf", demands[j].Pu - qu * Ac), 0.0u"lbf")

            pch = punching_check(Vu_p, demands[j].Mux, demands[j].Muy,
                                  d_eff, fc, c_est, c_est;
                                  position = pos_sym, λ = λ, ϕ = ϕv)
            if !pch.ok
                all_ok = false
                break
            end
        end

        all_ok && break
        h += h_incr
        iter == 60 && @warn "Mat footing thickness did not converge at h=$h"
    end

    d_eff = h - cover - max(db_x, db_y)

    # =====================================================================
    # Step 4: Flexural Reinforcement via Strip Statics
    # =====================================================================
    avg_trib_x = isempty(y_spans) ? Lm : sum(y_spans) / length(y_spans)
    mom_x = _rigid_mat_strip_moments(qu, avg_trib_x, x_spans)

    avg_trib_y = isempty(x_spans) ? B : sum(x_spans) / length(x_spans)
    mom_y = _rigid_mat_strip_moments(qu, avg_trib_y, y_spans)

    # Reinforcement distributed over full mat width
    As_x_bot = max(_flexural_steel_footing(mom_x.M_pos, Lm, d_eff, fc, fy, ϕf),
                   _min_steel_footing(Lm, h, fy))
    As_x_top = max(_flexural_steel_footing(mom_x.M_neg, Lm, d_eff, fc, fy, ϕf),
                   _min_steel_footing(Lm, h, fy))
    As_y_bot = max(_flexural_steel_footing(mom_y.M_pos, B, d_eff, fc, fy, ϕf),
                   _min_steel_footing(B, h, fy))
    As_y_top = max(_flexural_steel_footing(mom_y.M_neg, B, d_eff, fc, fy, ϕf),
                   _min_steel_footing(B, h, fy))

    # =====================================================================
    # Step 5: Relative Stiffness (Kr) — informational
    # =====================================================================
    if soil.ks !== nothing
        Ec_psi = 57000.0 * sqrt(ustrip(u"psi", fc))
        Ig_in4 = ustrip(u"inch", B) * ustrip(u"inch", h)^3 / 12.0
        ks_pci = ustrip(u"lbf/inch^3", uconvert(u"lbf/inch^3", soil.ks))
        Kr = Ec_psi * Ig_in4 / (ks_pci * ustrip(u"inch", B) * ustrip(u"inch", Lm)^3)
        Kr < 0.5 && @warn "Kr=$(round(Kr, digits=3)) < 0.5 — flexible analysis may be needed"
    end

    # =====================================================================
    # Utilization
    # =====================================================================
    util_punch = 0.0
    for j in 1:N
        at_xmin = xs_loc[j] < overhang + 0.5u"ft"
        at_xmax = xs_loc[j] > (B - overhang - 0.5u"ft")
        at_ymin = ys_loc[j] < overhang + 0.5u"ft"
        at_ymax = ys_loc[j] > (Lm - overhang - 0.5u"ft")
        is_edge = at_xmin || at_xmax || at_ymin || at_ymax
        pos_sym = is_edge ? :edge : :interior
        Ac = is_edge ? (c_est + d_eff / 2) * (c_est + d_eff) :
                       (c_est + d_eff) * (c_est + d_eff)
        Vu_p = max(uconvert(u"lbf", demands[j].Pu - qu * Ac), 0.0u"lbf")
        pch = punching_check(Vu_p, demands[j].Mux, demands[j].Muy,
                              d_eff, fc, c_est, c_est;
                              position = pos_sym, λ = λ, ϕ = ϕv)
        util_punch = max(util_punch, pch.utilization)
    end
    utilization = max(util_bearing, util_punch)

    # =====================================================================
    # Result (SI output)
    # =====================================================================
    V_conc = uconvert(u"m^3", B * Lm * h)

    Ab_x = bar_area(opts.bar_size_x)
    Ab_y = bar_area(opts.bar_size_y)
    n_xb = ceil(Int, As_x_bot / Ab_x)
    n_xt = ceil(Int, As_x_top / Ab_x)
    n_yb = ceil(Int, As_y_bot / Ab_y)
    n_yt = ceil(Int, As_y_top / Ab_y)
    len_x = B  - 2cover
    len_y = Lm - 2cover
    V_steel = uconvert(u"m^3",
        (n_xb + n_xt) * Ab_x * len_x +
        (n_yb + n_yt) * Ab_y * len_y)

    return MatFootingResult{typeof(uconvert(u"m", B)),
                            typeof(uconvert(u"m^2", As_x_bot)),
                            typeof(V_conc),
                            typeof(demands[1].Pu)}(
        uconvert(u"m", B),
        uconvert(u"m", Lm),
        uconvert(u"m", h),
        uconvert(u"m", d_eff),
        uconvert(u"m^2", As_x_bot),
        uconvert(u"m^2", As_x_top),
        uconvert(u"m^2", As_y_bot),
        uconvert(u"m^2", As_y_top),
        N,
        V_conc, V_steel,
        utilization,
    )
end
