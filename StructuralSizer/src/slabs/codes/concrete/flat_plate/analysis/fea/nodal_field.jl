# =============================================================================
# Nodal Moment Field — Area-Weighted Smoothing (Global Frame)
# =============================================================================
#
# Extrapolates element-centroid bending moments to mesh nodes via area-weighted
# averaging, producing a smooth, continuous field that can be interpolated
# linearly inside each triangle.
#
# ⚠ Asap ShellTri3 elements store moments in element-local coordinates (LCS),
#   and each triangle has a different LCS orientation.  Before averaging, each
#   element's (Mxx, Myy, Mxy) tensor is rotated to the **global** frame so
#   that the nodal average is physically meaningful.
#
# This is a standard "SPR-lite" (superconvergent patch recovery) technique:
#   M_node(n) = Σ [Aₑ × M_global(e)] / Σ [Aₑ]
#               over all elements e sharing node n
#
# The smoothed field eliminates element-to-element jumps inherent in
# constant-moment Tri3 elements, enabling:
#   - True line-integral section cuts (no δ-band)
#   - Peak-nodal envelope extraction
#   - Smooth contour / heatmap visualization
#
# Reference:
#   Zienkiewicz & Zhu (1992), "The superconvergent patch recovery and
#   a posteriori error estimates", Int. J. Numer. Meth. Eng. 33(7).
# =============================================================================

# =============================================================================
# Nodal Moment Data
# =============================================================================

"""
    NodalMomentField

Smooth bending-moment field defined at mesh nodes.

# Fields
- `node_Mxx`, `node_Myy`, `node_Mxy`: Moment components at each node (N·m/m),
  indexed directly by `node.nodeID` (flat vectors, 1-based).
- `node_x`, `node_y`: Node positions in meters, indexed by `node.nodeID`.
- `tri_node_ids`: Per-element tuple of 3 `nodeID`s, indexed by element index
  (same ordering as `cache.element_data`).
- `max_node_id`: Highest nodeID in the mesh (length of the flat arrays).
"""
struct NodalMomentField
    node_Mxx::Vector{Float64}
    node_Myy::Vector{Float64}
    node_Mxy::Vector{Float64}
    node_x::Vector{Float64}
    node_y::Vector{Float64}
    tri_node_ids::Vector{NTuple{3, Int}}
    max_node_id::Int
end

# =============================================================================
# Construction
# =============================================================================

"""
    build_nodal_moment_field(cache::FEAModelCache) -> NodalMomentField

Build a smooth nodal moment field from the solved FEA model by area-weighted
averaging of element centroid moments (rotated to global) to their nodes.

For each node `n`:
    Mxx_g(n) = Σ [Aₑ × Mxx_global(e)] / Σ [Aₑ]
over all shell elements `e` that share node `n`.

Each element's local `(Mxx, Myy, Mxy)` is first rotated to the global frame
via the 2D tensor rotation `M_g = R · M_l · Rᵀ` where `R = [ex ey]`.

Requires `cache.initialized == true` and a valid `cache.model`.
"""
function build_nodal_moment_field(cache::FEAModelCache)::NodalMomentField
    model = cache.model
    shell_vec = model.shell_elements
    n_elem = length(shell_vec)

    # Determine max nodeID for flat-array sizing
    max_nid = length(model.nodes)

    # Flat accumulators indexed by nodeID (1-based)
    sum_Mxx = zeros(Float64, max_nid)
    sum_Myy = zeros(Float64, max_nid)
    sum_Mxy = zeros(Float64, max_nid)
    sum_A   = zeros(Float64, max_nid)
    node_x  = zeros(Float64, max_nid)
    node_y  = zeros(Float64, max_nid)
    node_set = falses(max_nid)  # track which nodes have been positioned
    tri_node_ids = Vector{NTuple{3, Int}}(undef, n_elem)

    @inbounds for k in 1:n_elem
        tri = shell_vec[k]
        tri isa Asap.ShellTri3 || continue
        ed = cache.element_data[k]
        A = ed.area
        A > 0 || continue

        nids = (tri.nodes[1].nodeID, tri.nodes[2].nodeID, tri.nodes[3].nodeID)
        tri_node_ids[k] = nids

        # Rotate element-local moments to global frame:
        # M_global = R · M_local · Rᵀ  where R = [ex ey] (columns = local axes)
        ex1, ex2 = ed.ex
        ey1, ey2 = ed.ey
        Mxx_g = ed.Mxx * ex1^2 + ed.Myy * ey1^2 + 2 * ed.Mxy * ex1 * ey1
        Myy_g = ed.Mxx * ex2^2 + ed.Myy * ey2^2 + 2 * ed.Mxy * ex2 * ey2
        Mxy_g = ed.Mxx * ex1 * ex2 + ed.Myy * ey1 * ey2 + ed.Mxy * (ex1 * ey2 + ex2 * ey1)

        for j in 1:3
            nid = nids[j]
            # Accumulate weighted global moments
            sum_Mxx[nid] += A * Mxx_g
            sum_Myy[nid] += A * Myy_g
            sum_Mxy[nid] += A * Mxy_g
            sum_A[nid]   += A

            # Cache node position (idempotent)
            if !node_set[nid]
                pos = tri.nodes[j].position
                node_x[nid] = ustrip(u"m", pos[1])
                node_y[nid] = ustrip(u"m", pos[2])
                node_set[nid] = true
            end
        end
    end

    # Normalize: divide weighted sums by total area
    out_Mxx = zeros(Float64, max_nid)
    out_Myy = zeros(Float64, max_nid)
    out_Mxy = zeros(Float64, max_nid)

    @inbounds for nid in 1:max_nid
        A_total = sum_A[nid]
        A_total > 0 || continue
        inv_A = 1.0 / A_total
        out_Mxx[nid] = sum_Mxx[nid] * inv_A
        out_Myy[nid] = sum_Myy[nid] * inv_A
        out_Mxy[nid] = sum_Mxy[nid] * inv_A
    end

    return NodalMomentField(out_Mxx, out_Myy, out_Mxy, node_x, node_y, tri_node_ids, max_nid)
end

"""
    SeparateFaceFields

Pair of nodal moment fields smoothed independently by sign, preventing
cross-sign cancellation at inflection-point nodes.

- `hogging`: field built only from elements where the projected Mₙ > 0
  (Asap convention: tension on top face).
- `sagging`: field built only from elements where the projected Mₙ ≤ 0
  (Asap convention: tension on bottom face).

See Skorpen & Dekker (2014), Pacoste & Plos (2006) for why sign-separated
smoothing improves hogging-moment accuracy near inflection points.
"""
struct SeparateFaceFields
    hogging::NodalMomentField
    sagging::NodalMomentField
end

"""
    build_separate_face_fields(cache, span_axis) -> SeparateFaceFields

Build two independent nodal moment fields — one from elements whose
span-projected Mₙ is positive (hogging in Asap convention), one from
elements whose Mₙ is non-positive (sagging).

At each node, only elements with the matching sign contribute to the
area-weighted average.  This prevents opposite-sign moments from cancelling
at nodes near inflection points, which is the main failure mode of standard
signed averaging in hogging regions.

Nodes that receive no contributions from a given sign get zero moments in
that field (safe default — no reinforcement demand).
"""
function build_separate_face_fields(
    cache::FEAModelCache,
    span_axis::NTuple{2, Float64},
)::SeparateFaceFields
    model = cache.model
    shell_vec = model.shell_elements
    n_elem = length(shell_vec)
    ax, ay = span_axis
    max_nid = length(model.nodes)

    # Flat accumulators for hogging (Mn > 0) and sagging (Mn ≤ 0) fields
    hog_Mxx = zeros(Float64, max_nid)
    hog_Myy = zeros(Float64, max_nid)
    hog_Mxy = zeros(Float64, max_nid)
    hog_A   = zeros(Float64, max_nid)

    sag_Mxx = zeros(Float64, max_nid)
    sag_Myy = zeros(Float64, max_nid)
    sag_Mxy = zeros(Float64, max_nid)
    sag_A   = zeros(Float64, max_nid)

    node_x  = zeros(Float64, max_nid)
    node_y  = zeros(Float64, max_nid)
    node_set = falses(max_nid)
    tri_node_ids = Vector{NTuple{3, Int}}(undef, n_elem)

    @inbounds for k in 1:n_elem
        tri = shell_vec[k]
        tri isa Asap.ShellTri3 || continue
        ed = cache.element_data[k]
        A = ed.area
        A > 0 || continue

        nids = (tri.nodes[1].nodeID, tri.nodes[2].nodeID, tri.nodes[3].nodeID)
        tri_node_ids[k] = nids

        # Rotate element-local moments to global frame
        ex1, ex2 = ed.ex
        ey1, ey2 = ed.ey
        Mxx_g = ed.Mxx * ex1^2 + ed.Myy * ey1^2 + 2 * ed.Mxy * ex1 * ey1
        Myy_g = ed.Mxx * ex2^2 + ed.Myy * ey2^2 + 2 * ed.Mxy * ex2 * ey2
        Mxy_g = ed.Mxx * ex1 * ex2 + ed.Myy * ey1 * ey2 + ed.Mxy * (ex1 * ey2 + ex2 * ey1)

        # Classify by sign of projected Mn (Asap: positive = hogging)
        Mn = Mxx_g * ax^2 + Myy_g * ay^2 + 2 * Mxy_g * ax * ay
        is_hog = Mn > 0.0

        for j in 1:3
            nid = nids[j]
            if is_hog
                hog_Mxx[nid] += A * Mxx_g
                hog_Myy[nid] += A * Myy_g
                hog_Mxy[nid] += A * Mxy_g
                hog_A[nid]   += A
            else
                sag_Mxx[nid] += A * Mxx_g
                sag_Myy[nid] += A * Myy_g
                sag_Mxy[nid] += A * Mxy_g
                sag_A[nid]   += A
            end

            if !node_set[nid]
                pos = tri.nodes[j].position
                node_x[nid] = ustrip(u"m", pos[1])
                node_y[nid] = ustrip(u"m", pos[2])
                node_set[nid] = true
            end
        end
    end

    # Normalize each field independently into flat arrays
    h_Mxx = zeros(Float64, max_nid)
    h_Myy = zeros(Float64, max_nid)
    h_Mxy = zeros(Float64, max_nid)
    s_Mxx_n = zeros(Float64, max_nid)
    s_Myy_n = zeros(Float64, max_nid)
    s_Mxy_n = zeros(Float64, max_nid)

    @inbounds for nid in 1:max_nid
        A_h = hog_A[nid]
        if A_h > 0
            inv_A = 1.0 / A_h
            h_Mxx[nid] = hog_Mxx[nid] * inv_A
            h_Myy[nid] = hog_Myy[nid] * inv_A
            h_Mxy[nid] = hog_Mxy[nid] * inv_A
        end
        A_s = sag_A[nid]
        if A_s > 0
            inv_A = 1.0 / A_s
            s_Mxx_n[nid] = sag_Mxx[nid] * inv_A
            s_Myy_n[nid] = sag_Myy[nid] * inv_A
            s_Mxy_n[nid] = sag_Mxy[nid] * inv_A
        end
    end

    hogging_field = NodalMomentField(h_Mxx, h_Myy, h_Mxy, node_x, node_y, tri_node_ids, max_nid)
    sagging_field = NodalMomentField(s_Mxx_n, s_Myy_n, s_Mxy_n, node_x, node_y, tri_node_ids, max_nid)

    return SeparateFaceFields(hogging_field, sagging_field)
end

# =============================================================================
# Interpolation
# =============================================================================

"""
    _barycentric_coords(px, py, x1, y1, x2, y2, x3, y3) -> (λ1, λ2, λ3)

Barycentric coordinates of point (px, py) in triangle (1, 2, 3).
Returns values that sum to 1.0; all ∈ [0, 1] if point is inside.
"""
@inline function _barycentric_coords(
    px::Float64, py::Float64,
    x1::Float64, y1::Float64,
    x2::Float64, y2::Float64,
    x3::Float64, y3::Float64,
)
    denom = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    abs(denom) < 1e-20 && return (1/3, 1/3, 1/3)  # degenerate triangle
    λ1 = ((y2 - y3) * (px - x3) + (x3 - x2) * (py - y3)) / denom
    λ2 = ((y3 - y1) * (px - x3) + (x1 - x3) * (py - y3)) / denom
    λ3 = 1.0 - λ1 - λ2
    return (λ1, λ2, λ3)
end

"""
    interpolate_moments(field, elem_idx, px, py) -> (Mxx, Myy, Mxy)

Interpolate the smoothed moment field at point (px, py) inside element
`elem_idx` using barycentric coordinates and the nodal values.

Returns `(Mxx, Myy, Mxy)` in N·m/m.
"""
function interpolate_moments(
    field::NodalMomentField,
    elem_idx::Int,
    px::Float64, py::Float64,
)
    nids = field.tri_node_ids[elem_idx]
    n1, n2, n3 = nids

    λ1, λ2, λ3 = _barycentric_coords(
        px, py,
        field.node_x[n1], field.node_y[n1],
        field.node_x[n2], field.node_y[n2],
        field.node_x[n3], field.node_y[n3],
    )

    Mxx = λ1 * field.node_Mxx[n1] + λ2 * field.node_Mxx[n2] + λ3 * field.node_Mxx[n3]
    Myy = λ1 * field.node_Myy[n1] + λ2 * field.node_Myy[n2] + λ3 * field.node_Myy[n3]
    Mxy = λ1 * field.node_Mxy[n1] + λ2 * field.node_Mxy[n2] + λ3 * field.node_Mxy[n3]

    return (Mxx, Myy, Mxy)
end

"""
    interpolate_Mn(field, elem_idx, px, py, span_axis; include_torsion=true)

Interpolate the span-direction moment Mₙ at point (px, py) inside element
`elem_idx`.  Uses Mohr's circle projection of the smoothed **global-frame**
(Mxx, Myy, Mxy) onto the span axis.

When `include_torsion=false`, the Mxy cross-term is dropped from the
projection (intentionally unconservative baseline).

Returns Mₙ in N·m/m.  Sign follows Asap convention: positive = hogging
(tension on top), negative = sagging (tension on bottom).
"""
function interpolate_Mn(
    field::NodalMomentField,
    elem_idx::Int,
    px::Float64, py::Float64,
    span_axis::NTuple{2, Float64};
    include_torsion::Bool = true,
)
    Mxx, Myy, Mxy = interpolate_moments(field, elem_idx, px, py)
    ax, ay = span_axis
    # Mohr's circle: Mₙ = Mxx·cos²θ + Myy·sin²θ + 2·Mxy·cosθ·sinθ
    Mn = Mxx * ax^2 + Myy * ay^2
    if include_torsion
        Mn += 2 * Mxy * ax * ay
    end
    return Mn
end

# =============================================================================
# Peak Nodal Extraction — DEPRECATED
# =============================================================================
# Only used by _extract_peak_nodal_strip_moments (also deprecated).
# Retained for backward compatibility.
# =============================================================================

"""
    peak_nodal_Mn(field, node_ids, span_axis) -> (max_pos, max_neg)

⚠ **DEPRECATED** — Only used by the deprecated `_extract_peak_nodal_strip_moments`.

Find the peak positive (sagging) and negative (hogging) span-direction
moment intensity Mₙ among a set of nodes.

`node_ids` should be an iterable of `nodeID` values (e.g., all nodes in a
strip polygon).

Returns `(max_positive_Mn, max_negative_Mn)` in N·m/m.
Both are returned as non-negative values (absolute magnitudes).
"""
function peak_nodal_Mn(
    field::NodalMomentField,
    node_ids,
    span_axis::NTuple{2, Float64},
)
    ax, ay = span_axis
    max_pos = 0.0  # peak sagging (Mₙ > 0)
    max_neg = 0.0  # peak hogging (Mₙ < 0, stored as |Mₙ|)

    for nid in node_ids
        (nid < 1 || nid > field.max_node_id) && continue
        Mxx = field.node_Mxx[nid]
        Myy = field.node_Myy[nid]
        Mxy = field.node_Mxy[nid]
        Mn = Mxx * ax^2 + Myy * ay^2 + 2 * Mxy * ax * ay
        if Mn > max_pos
            max_pos = Mn
        elseif -Mn > max_neg
            max_neg = -Mn
        end
    end

    return (max_pos, max_neg)
end
