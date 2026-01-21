# Tributary Area Types and Utilities

import Meshes: Point, coords
using Unitful: ustrip, @u_str

"""
Parametric tributary polygon relative to a beam edge.

All length values are in **meters** (SI base unit).

Fields:
- `local_edge_idx`: Edge index within cell (1..n_edges)
- `s`: Normalized positions along beam [0,1] (unitless)
- `d`: Perpendicular distances from beam (meters)
- `area`: Tributary area (m²)
- `fraction`: Fraction of total cell area (unitless)
"""
struct TributaryPolygon
    local_edge_idx::Int
    s::Vector{Float64}
    d::Vector{Float64}
    area::Float64
    fraction::Float64
end

"""
Convert parametric (s,d) to absolute (x,y) coordinates in meters.

beam_start and beam_end must be in meters.
"""
function vertices(trib::TributaryPolygon, beam_start::NTuple{2,Float64}, 
                  beam_end::NTuple{2,Float64})::Vector{NTuple{2,Float64}}
    beam_vec = (beam_end[1] - beam_start[1], beam_end[2] - beam_start[2])
    beam_len = hypot(beam_vec...)
    beam_len < 1e-12 && return NTuple{2, Float64}[]
    
    beam_dir = (beam_vec[1] / beam_len, beam_vec[2] / beam_len)
    beam_normal = (-beam_dir[2], beam_dir[1])
    
    return [(beam_start[1] + s * beam_len * beam_dir[1] + d * beam_normal[1],
             beam_start[2] + s * beam_len * beam_dir[2] + d * beam_normal[2])
            for (s, d) in zip(trib.s, trib.d)]
end

"""Convert Meshes.Point to (x,y) tuple in meters."""
function _to_2d(p::Point)
    c = coords(p)
    (Float64(ustrip(u"m", c.x)), Float64(ustrip(u"m", c.y)))
end

"""Convert absolute vertices to parametric (s,d) relative to beam."""
function _to_parametric(abs_verts::Vector{NTuple{2,Float64}}, beam_start::NTuple{2,Float64},
                        beam_end::NTuple{2,Float64})::Tuple{Vector{Float64}, Vector{Float64}}
    isempty(abs_verts) && return (Float64[], Float64[])
    
    beam_vec = (beam_end[1] - beam_start[1], beam_end[2] - beam_start[2])
    beam_len = hypot(beam_vec...)
    beam_len < 1e-12 && return (zeros(length(abs_verts)), zeros(length(abs_verts)))
    
    beam_dir = (beam_vec[1] / beam_len, beam_vec[2] / beam_len)
    beam_normal = (-beam_dir[2], beam_dir[1])
    
    s_vals, d_vals = Float64[], Float64[]
    for v in abs_verts
        rel = (v[1] - beam_start[1], v[2] - beam_start[2])
        push!(s_vals, (rel[1] * beam_dir[1] + rel[2] * beam_dir[2]) / beam_len)
        push!(d_vals, rel[1] * beam_normal[1] + rel[2] * beam_normal[2])
    end
    
    _rotate_to_beam_first(s_vals, d_vals)
end

"""Rotate (s,d) arrays so beam edge vertices come first."""
function _rotate_to_beam_first(s::Vector{Float64}, d::Vector{Float64})
    n = length(s)
    n < 2 && return (s, d)
    
    tol = 1e-6
    best_idx, best_score = 1, Inf
    for i in 1:n
        j = mod1(i + 1, n)
        score = abs(d[i]) + abs(d[j])
        if score < best_score && s[i] <= s[j] + tol
            best_score, best_idx = score, i
        end
    end
    
    best_idx == 1 && return (s, d)
    (vcat(s[best_idx:end], s[1:best_idx-1]), vcat(d[best_idx:end], d[1:best_idx-1]))
end

"""Create TributaryPolygon from absolute vertices (in meters) with precomputed area/frac."""
function _make_tributary(edge_idx::Int, verts::Vector{NTuple{2,Float64}}, 
                         original_pts::Vector{NTuple{2,Float64}}, area::Float64, 
                         frac::Float64)::TributaryPolygon
    isempty(verts) && return TributaryPolygon(edge_idx, Float64[], Float64[], area, frac)
    
    n = length(original_pts)
    s, d = _to_parametric(verts, original_pts[edge_idx], original_pts[mod1(edge_idx + 1, n)])
    TributaryPolygon(edge_idx, s, d, area, frac)
end

"""Shoelace formula for signed polygon area."""
function _polygon_area(pts::Vector{NTuple{2,Float64}})
    n = length(pts)
    n < 3 && return 0.0
    sum(pts[i][1] * pts[mod1(i+1,n)][2] - pts[mod1(i+1,n)][1] * pts[i][2] for i in 1:n) / 2
end

_is_ccw(pts::Vector{NTuple{2,Float64}}) = _polygon_area(pts) > 0

"""Ensure polygon is CCW oriented."""
_ensure_ccw(pts::Vector{NTuple{2,Float64}}) = _is_ccw(pts) ? pts : reverse(pts)

"""Simplify polygon by dropping collinear vertices."""
function simplify_collinear_polygon(pts::Vector{NTuple{2,Float64}}; tol=1e-12)
    n = length(pts)
    n ≤ 3 && return pts, collect(1:n)
    
    is_collinear(i) = begin
        p_prev, p, p_next = pts[mod1(i-1,n)], pts[i], pts[mod1(i+1,n)]
        abs((p[1]-p_prev[1])*(p_next[2]-p[2]) - (p[2]-p_prev[2])*(p_next[1]-p[1])) ≤ tol
    end
    
    keep = [i for i in 1:n if !is_collinear(i)]
    simp = [pts[i] for i in keep]
    
    if _polygon_area(simp) < 0
        reverse!(simp)
        reverse!(keep)
    end
    
    simp, keep
end
