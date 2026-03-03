# =============================================================================
# Force Extraction from Column Stubs
# =============================================================================

"""
    _extract_stub_forces_at_slab(stub; slab_end=:nodeEnd) -> (Fz, Mx, My)

Extract column forces from a column stub element at the slab connection.
Returns Unitful (N, N·m).

`slab_end` specifies which end of the element connects to the slab:
- `:nodeEnd` (default) — below stub: base(fixed) → slab, slab is nodeEnd (indices 7-12)
- `:nodeStart` — above stub: slab → top(fixed), slab is nodeStart (indices 1-6)

Forces are read in the element's LCS and transformed to GCS.
"""
function _extract_stub_forces_at_slab(stub; slab_end::Symbol = :nodeEnd)
    elem = stub.element
    X = elem.LCS[1]   # element X axis in GCS
    y = elem.LCS[2]   # element y axis in GCS
    z = elem.LCS[3]   # element z axis in GCS

    if slab_end === :nodeEnd
        P    = elem.forces[7]
        Vy   = elem.forces[8]
        Vz   = elem.forces[9]
        T    = elem.forces[10]
        My_l = elem.forces[11]
        Mz_l = elem.forces[12]
    else
        P    = elem.forces[1]
        Vy   = elem.forces[2]
        Vz   = elem.forces[3]
        T    = elem.forces[4]
        My_l = elem.forces[5]
        Mz_l = elem.forces[6]
    end

    # Transform to GCS
    Fz   = (P * X[3] + Vy * y[3] + Vz * z[3]) * u"N"
    Mx_g = (T * X[1] + My_l * y[1] + Mz_l * z[1]) * u"N*m"
    My_g = (T * X[2] + My_l * y[2] + Mz_l * z[2]) * u"N*m"

    return (Fz=Fz, Mx=Mx_g, My=My_g)
end

"""
    _extract_fea_column_forces(col_stubs, span_axis, n_cols)

Extract Vu, Mu, Mub from solved column stubs.  Sums contributions from
both below and above stubs at each column location.  Returns Unitful vectors.
"""
function _extract_fea_column_forces(col_stubs, span_axis::NTuple{2, Float64}, n_cols::Int)
    ax_len = hypot(span_axis...)
    ax = ax_len > 1e-9 ? (span_axis[1] / ax_len, span_axis[2] / ax_len) : (1.0, 0.0)

    ForceT  = typeof(1.0kip)
    MomentT = typeof(1.0kip * u"ft")
    Vu  = Vector{ForceT}(undef, n_cols)
    Mu  = Vector{MomentT}(undef, n_cols)
    Mub = Vector{MomentT}(undef, n_cols)
    Mx  = Vector{MomentT}(undef, n_cols)
    My  = Vector{MomentT}(undef, n_cols)

    for i in 1:n_cols
        stubs = col_stubs[i]

        # Below stub — slab is nodeEnd
        fb = _extract_stub_forces_at_slab(stubs.below; slab_end=:nodeEnd)
        Fz_total = fb.Fz
        Mx_total = fb.Mx
        My_total = fb.My

        # Above stub — slab is nodeStart (if present)
        if !isnothing(stubs.above)
            fa = _extract_stub_forces_at_slab(stubs.above; slab_end=:nodeStart)
            Fz_total += fa.Fz
            Mx_total += fa.Mx
            My_total += fa.My
        end

        Vu[i]  = uconvert(kip, abs(Fz_total))
        Mu[i]  = uconvert(kip * u"ft", hypot(Mx_total, My_total))
        Mub[i] = uconvert(kip * u"ft", abs(ax[1] * My_total - ax[2] * Mx_total))
        Mx[i]  = uconvert(kip * u"ft", Mx_total)
        My[i]  = uconvert(kip * u"ft", My_total)
    end

    return (Vu=Vu, Mu=Mu, Mub=Mub, Mx=Mx, My=My)
end

# =============================================================================
# FEA-Based One-Way Shear Demand  (ACI 318-11 §22.5)
# =============================================================================

"""
    _extract_fea_one_way_shear(cache, columns, span_axis, d; verbose=false) -> Force

Extract the maximum factored one-way shear demand from the FEA element data.

For each interior column, a section cut is placed at distance `d` from the
column face, perpendicular to the span axis.  The transverse shear resultant
`Q_n` (N/m) at each element centroid is projected onto the span-normal
direction and integrated (area-weighted) across all elements within a narrow
band at the critical section.

Returns the maximum `Vu` (Unitful Force) across all columns and both faces
(left/right of each column along the span axis).

# Method
1. For each column, define two section cuts at ±(c₁/2 + d) from the column
   centre along the span axis.
2. Select elements whose centroid falls within a band of width `δ` centred
   on each cut line (δ = median mesh edge length from the cache).
3. For each selected element, the shear contribution is
   `Q_n × area` where `Q_n = |Qxz × nx + Qyz × ny|` and `(nx, ny)` is the
   span-axis unit vector (the cut is perpendicular to the span, so the
   normal to the cut is the span direction).
4. Sum contributions across the band to approximate `∫ Q_n ds × bw`.

# Reference
- ACI 318-11 §22.5.1.1: Vu at critical section d from face of support
"""
function _extract_fea_one_way_shear(
    cache::FEAModelCache,
    columns,
    span_axis::NTuple{2, Float64},
    d::Length;
    verbose::Bool = false,
)
    ax_len = hypot(span_axis...)
    ax_len < 1e-9 && return 0.0kip
    nx = span_axis[1] / ax_len
    ny = span_axis[2] / ax_len

    d_m = ustrip(u"m", d)
    δ = cache.mesh_edge_length   # band half-width (m)
    δ < 1e-9 && return 0.0kip

    Vu_max = 0.0  # N

    for col in columns
        # Column centroid in mesh coordinates (m)
        skel = nothing  # not needed — we use the col_stubs slab_node position
        stubs = get(cache.col_stubs, findfirst(c -> c === col, columns), nothing)
        # Fall back to getting column position from the stub's slab node
        col_idx = findfirst(c -> c === col, columns)
        col_idx === nothing && continue
        stub_data = get(cache.col_stubs, col_idx, nothing)
        stub_data === nothing && continue
        slab_node = stub_data.below.slab_node
        cx = ustrip(u"m", slab_node.position[1])
        cy = ustrip(u"m", slab_node.position[2])

        c1_m = ustrip(u"m", col.c1)

        # Two section cuts: one on each side of the column along the span axis
        for sign in (-1.0, 1.0)
            cut_dist = sign * (c1_m / 2 + d_m)
            cut_x = cx + cut_dist * nx
            cut_y = cy + cut_dist * ny

            # Integrate Q_n across elements in the band
            Vu_band = 0.0  # N
            n_in_band = 0

            for ed in cache.element_data
                # Signed distance from element centroid to cut line
                # Cut line passes through (cut_x, cut_y) with normal (nx, ny)
                proj = (ed.cx - cut_x) * nx + (ed.cy - cut_y) * ny
                abs(proj) > δ && continue

                # Transverse shear projected onto span axis (N/m)
                # Qxz, Qyz are in the element LCS; project to global span direction
                # using the element's LCS → GCS mapping.
                # For a flat slab (z up), the element LCS x̂/ŷ are in the XY plane:
                #   Q_global_x = Qxz × ex[1] + Qyz × ey[1]
                #   Q_global_y = Qxz × ex[2] + Qyz × ey[2]
                Qgx = ed.Qxz * ed.ex[1] + ed.Qyz * ed.ey[1]
                Qgy = ed.Qxz * ed.ex[2] + ed.Qyz * ed.ey[2]

                # Project onto span axis to get shear normal to the cut
                Q_n = abs(Qgx * nx + Qgy * ny)   # N/m

                # Contribution = Q_n × element area / δ_band ≈ Q_n × (area / 2δ) × 2δ = Q_n × area
                # More precisely: we integrate Q_n over the band width.
                # Each element contributes Q_n × area (N·m), and we divide by
                # the band depth (2δ) to get force per unit length, then multiply
                # by the cut length.  But since we want the total shear force
                # across the full strip width, the area-weighted sum gives:
                #   V ≈ Σ(Q_n_k × A_k) / (2δ)  × (2δ) = Σ(Q_n_k × A_k)
                # This works because the band captures one row of elements
                # perpendicular to the span, and Q_n × A / edge_length ≈ V per element.
                Vu_band += Q_n * ed.area   # N·m ... but Q_n is N/m, area is m² → N·m
                n_in_band += 1
            end

            # Vu_band has units of N·m (shear intensity × area).
            # Divide by band depth to get the total shear force across the section:
            # V = Σ(Q_n × A) / (2δ) ... but this isn't quite right.
            # Actually: for a uniform Q_n field, the total shear across a cut of
            # length L is V = Q_n × L.  Our band captures elements of total area
            # A_band ≈ L × 2δ.  So V = Σ(Q_n × A) / (2δ) is correct.
            if n_in_band > 0
                Vu_section = Vu_band / (2 * δ)   # N
                Vu_section > Vu_max && (Vu_max = Vu_section)
            end
        end
    end

    Vu_result = uconvert(kip, Vu_max * u"N")

    if verbose
        @debug "FEA ONE-WAY SHEAR" Vu_max=Vu_result δ_band=round(δ * 1000, digits=1) * u"mm"
    end

    return Vu_result
end