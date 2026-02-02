# ACI Strip Geometry
#
# Splits tributary polygons at half-depth for ACI column/middle strip definitions.
# This generalizes ACI 318's l2/4 column strip width to arbitrary polygon shapes.

using Asap: TributaryPolygon
import Asap: vertices  # Extend with methods for strip types

"""
    ColumnStripPolygon

The inner portion of a tributary polygon (from edge to d/2).
Used for column strip moment distribution per ACI 318.

# Fields
- `local_edge_idx::Int`: Edge index within cell (1..n_edges)
- `s::Vector{Float64}`: Normalized positions along beam [0,1]
- `d::Vector{Float64}`: Perpendicular distances from beam (meters), all ≤ d_max/2
- `area::Float64`: Column strip area contribution from this edge (m²)
"""
struct ColumnStripPolygon
    local_edge_idx::Int
    s::Vector{Float64}
    d::Vector{Float64}
    area::Float64
end

"""
    MiddleStripPolygon

The outer portion of a tributary polygon (from d/2 to skeleton ridge).
Used for middle strip moment distribution per ACI 318.

# Fields
- `local_edge_idx::Int`: Edge index within cell (same as source tributary)
- `s::Vector{Float64}`: Normalized positions along beam [0,1]
- `d::Vector{Float64}`: Perpendicular distances from beam (meters), all ≥ d_max/2
- `area::Float64`: Middle strip area contribution from this edge (m²)
"""
struct MiddleStripPolygon
    local_edge_idx::Int
    s::Vector{Float64}
    d::Vector{Float64}
    area::Float64
end

"""
    PanelStripGeometry

Complete strip geometry for a panel (cell), derived from tributary polygons.

Per ACI 318, moments are distributed differently to column strips vs middle strips.
This struct holds the geometric information needed for that distribution.

# Fields
- `column_strips::Vector{ColumnStripPolygon}`: One per edge (inner half of each tributary)
- `middle_strips::Vector{MiddleStripPolygon}`: One per edge (outer half of each tributary)
- `total_column_strip_area::Float64`: Sum of all column strip areas (m²)
- `total_middle_strip_area::Float64`: Sum of all middle strip areas (m²)
- `total_area::Float64`: Total panel area (should equal sum of column + middle)

# ACI Context
For a rectangular panel of width l2:
- Column strip width = l2/4 on each side of column line
- Middle strip width = l2/2 (remainder)
- Column strip area ≈ 50% of total, Middle strip area ≈ 50%

This implementation generalizes to irregular shapes using the "d/2" rule:
- Column strip = portion of each tributary from edge to half its max depth
"""
struct PanelStripGeometry
    column_strips::Vector{ColumnStripPolygon}
    middle_strips::Vector{MiddleStripPolygon}
    total_column_strip_area::Float64
    total_middle_strip_area::Float64
    total_area::Float64
end

"""
    split_tributary_at_half_depth(trib::TributaryPolygon) -> (ColumnStripPolygon, MiddleStripPolygon)

Split a tributary polygon at its half-depth line.

The column strip is the inner half (d ∈ [0, d_max/2]).
The middle strip is the outer half (d ∈ [d_max/2, d_max]).

For rectangular panels, this matches ACI's l2/4 column strip width because:
- Tributary max depth d_max = l2/2 (half the transverse span)
- Half-depth = l2/4 = ACI column strip width

# Arguments
- `trib::TributaryPolygon`: Edge tributary from straight skeleton

# Returns
- `(column_strip::ColumnStripPolygon, middle_strip::MiddleStripPolygon)`
"""
function split_tributary_at_half_depth(trib::TributaryPolygon)
    s, d = trib.s, trib.d
    n = length(s)
    
    # Handle degenerate cases
    if n < 3
        empty_col = ColumnStripPolygon(trib.local_edge_idx, Float64[], Float64[], 0.0)
        empty_mid = MiddleStripPolygon(trib.local_edge_idx, Float64[], Float64[], 0.0)
        return (empty_col, empty_mid)
    end
    
    # Find max depth (distance to skeleton ridge)
    d_max = maximum(d)
    d_half = d_max / 2
    
    # Handle case where d_max is very small (thin sliver)
    if d_max < 1e-6
        # Entire tributary is column strip
        col = ColumnStripPolygon(trib.local_edge_idx, copy(s), copy(d), trib.area)
        mid = MiddleStripPolygon(trib.local_edge_idx, Float64[], Float64[], 0.0)
        return (col, mid)
    end
    
    # Clip polygon at d = d_half
    col_s, col_d = _clip_polygon_below(s, d, d_half)
    mid_s, mid_d = _clip_polygon_above(s, d, d_half)
    
    # Compute areas using shoelace formula in (s, d) space
    # Note: This gives area in beam-normalized coords, need to scale by beam length
    # For now, estimate by ratio of d values (simpler and works for typical shapes)
    col_area = _polygon_area_sd(col_s, col_d)
    mid_area = _polygon_area_sd(mid_s, mid_d)
    
    # Scale to match original tributary area
    total_computed = col_area + mid_area
    if total_computed > 1e-12
        scale = trib.area / total_computed
        col_area *= scale
        mid_area *= scale
    else
        col_area = trib.area / 2
        mid_area = trib.area / 2
    end
    
    col = ColumnStripPolygon(trib.local_edge_idx, col_s, col_d, col_area)
    mid = MiddleStripPolygon(trib.local_edge_idx, mid_s, mid_d, mid_area)
    
    return (col, mid)
end

"""
    compute_panel_strips(tributaries::Vector{TributaryPolygon}) -> PanelStripGeometry

Compute ACI strip geometry for a panel from its edge tributaries.

Each tributary is split at half-depth. Column strips are the inner halves,
middle strips are the outer halves.

# Arguments
- `tributaries`: Edge tributaries from `get_tributary_polygons()` (one per edge)

# Returns
- `PanelStripGeometry` with column and middle strip definitions
"""
function compute_panel_strips(tributaries::Vector{TributaryPolygon})
    column_strips = ColumnStripPolygon[]
    middle_strips = MiddleStripPolygon[]
    
    for trib in tributaries
        col, mid = split_tributary_at_half_depth(trib)
        push!(column_strips, col)
        push!(middle_strips, mid)
    end
    
    total_col = sum(cs.area for cs in column_strips)
    total_mid = sum(ms.area for ms in middle_strips)
    total_area = total_col + total_mid
    
    return PanelStripGeometry(column_strips, middle_strips, total_col, total_mid, total_area)
end

# =============================================================================
# Internal Polygon Clipping Helpers
# =============================================================================

"""Clip polygon to region where d ≤ d_cut (column strip)."""
function _clip_polygon_below(s::Vector{Float64}, d::Vector{Float64}, d_cut::Float64)
    return _clip_polygon_at_d(s, d, d_cut, :below)
end

"""Clip polygon to region where d ≥ d_cut (middle strip)."""
function _clip_polygon_above(s::Vector{Float64}, d::Vector{Float64}, d_cut::Float64)
    return _clip_polygon_at_d(s, d, d_cut, :above)
end

"""
Sutherland-Hodgman style clipping at d = d_cut.

For :below, keeps region where d ≤ d_cut
For :above, keeps region where d ≥ d_cut
"""
function _clip_polygon_at_d(s::Vector{Float64}, d::Vector{Float64}, d_cut::Float64, 
                            side::Symbol)
    n = length(s)
    n < 3 && return (Float64[], Float64[])
    
    out_s = Float64[]
    out_d = Float64[]
    
    for i in 1:n
        j = mod1(i + 1, n)
        
        s1, d1 = s[i], d[i]
        s2, d2 = s[j], d[j]
        
        inside1 = side == :below ? (d1 <= d_cut + 1e-10) : (d1 >= d_cut - 1e-10)
        inside2 = side == :below ? (d2 <= d_cut + 1e-10) : (d2 >= d_cut - 1e-10)
        
        if inside1 && inside2
            # Both inside - add second point
            push!(out_s, s2)
            push!(out_d, d2)
        elseif inside1 && !inside2
            # Going out - add intersection
            t = (d_cut - d1) / (d2 - d1)
            t = clamp(t, 0.0, 1.0)
            push!(out_s, s1 + t * (s2 - s1))
            push!(out_d, d_cut)
        elseif !inside1 && inside2
            # Coming in - add intersection then second point
            t = (d_cut - d1) / (d2 - d1)
            t = clamp(t, 0.0, 1.0)
            push!(out_s, s1 + t * (s2 - s1))
            push!(out_d, d_cut)
            push!(out_s, s2)
            push!(out_d, d2)
        end
        # Both outside - add nothing
    end
    
    return (out_s, out_d)
end

"""Compute area of polygon in (s, d) space using shoelace formula."""
function _polygon_area_sd(s::Vector{Float64}, d::Vector{Float64})
    n = length(s)
    n < 3 && return 0.0
    
    area = 0.0
    for i in 1:n
        j = mod1(i + 1, n)
        area += s[i] * d[j] - s[j] * d[i]
    end
    return abs(area) / 2
end

# =============================================================================
# Conversion to Absolute Coordinates
# =============================================================================

"""
    vertices(strip::ColumnStripPolygon, beam_start, beam_end) -> Vector{NTuple{2,Float64}}

Convert column strip from parametric (s,d) to absolute (x,y) coordinates.
"""
function vertices(strip::ColumnStripPolygon, beam_start::NTuple{2,Float64}, 
                  beam_end::NTuple{2,Float64})
    return _parametric_to_absolute(strip.s, strip.d, beam_start, beam_end)
end

"""
    vertices(strip::MiddleStripPolygon, beam_start, beam_end) -> Vector{NTuple{2,Float64}}

Convert middle strip from parametric (s,d) to absolute (x,y) coordinates.
"""
function vertices(strip::MiddleStripPolygon, beam_start::NTuple{2,Float64}, 
                  beam_end::NTuple{2,Float64})
    return _parametric_to_absolute(strip.s, strip.d, beam_start, beam_end)
end

"""Convert parametric (s,d) to absolute (x,y) coordinates."""
function _parametric_to_absolute(s::Vector{Float64}, d::Vector{Float64},
                                  beam_start::NTuple{2,Float64}, 
                                  beam_end::NTuple{2,Float64})
    isempty(s) && return NTuple{2,Float64}[]
    
    beam_vec = (beam_end[1] - beam_start[1], beam_end[2] - beam_start[2])
    beam_len = hypot(beam_vec...)
    beam_len < 1e-12 && return NTuple{2,Float64}[]
    
    beam_dir = (beam_vec[1] / beam_len, beam_vec[2] / beam_len)
    beam_normal = (-beam_dir[2], beam_dir[1])
    
    return [(beam_start[1] + si * beam_len * beam_dir[1] + di * beam_normal[1],
             beam_start[2] + si * beam_len * beam_dir[2] + di * beam_normal[2])
            for (si, di) in zip(s, d)]
end

# =============================================================================
# Verification Helpers
# =============================================================================

"""
    verify_rectangular_strips(strips::PanelStripGeometry; tol=0.10) -> Bool

Verify that strip geometry is reasonable for a rectangular panel.

For rectangular panels with triangular tributaries:
- Column strip area ≈ 70-75% of total (inner half by depth, but larger area)
- Middle strip area ≈ 25-30% of total

This is geometrically correct: cutting a triangle at half its height retains
~75% of the area in the lower portion.

Note: ACI defines strips by WIDTH (l2/4 from column line), not by area.
Our d/2 split matches the ACI width definition, resulting in unequal areas.

Returns true if areas sum correctly and column strip is in expected range.
"""
function verify_rectangular_strips(strips::PanelStripGeometry; tol=0.10)
    total = strips.total_area
    total < 1e-6 && return false
    
    col_frac = strips.total_column_strip_area / total
    mid_frac = strips.total_middle_strip_area / total
    
    # Check areas sum to total
    sum_frac = col_frac + mid_frac
    abs(sum_frac - 1.0) > 0.01 && return false
    
    # For rectangular panels with triangular tributaries: column strip ≈ 70-75%
    return (0.65 - tol) < col_frac < (0.80 + tol)
end
