# =============================================================================
# Tributary Area Types and Utilities (Straight Skeleton)
# =============================================================================

import Meshes: Point, coords
using Unitful: ustrip, @u_str

"""Result of tributary area computation for one edge."""
struct TributaryResult
    edge_idx::Int
    vertices::Vector{NTuple{2, Float64}}  # polygon vertices (m)
    area::Float64                          # tributary area (m²)
    fraction::Float64                      # fraction of total cell area
end

"""Convert Meshes.Point to (x, y) tuple in meters."""
function _to_2d(p::Point)
    c = coords(p)
    x = Float64(ustrip(u"m", c.x))
    y = Float64(ustrip(u"m", c.y))
    return (x, y)
end

"""Compute bisector directions and speed factors for active vertices."""
function _compute_bisectors_with_speed(pts::Vector{NTuple{2,Float64}}, active::Vector{Int})
    n = length(active)
    bisectors = Vector{NTuple{2,Float64}}(undef, n)
    speeds = Vector{Float64}(undef, n)
    
    for i in 1:n
        prev_i = mod1(i - 1, n)
        next_i = mod1(i + 1, n)
        
        p_prev = pts[active[prev_i]]
        p_curr = pts[active[i]]
        p_next = pts[active[next_i]]
        
        # Edge vectors
        v_in = (p_curr[1] - p_prev[1], p_curr[2] - p_prev[2])
        v_out = (p_next[1] - p_curr[1], p_next[2] - p_curr[2])
        
        len_in = hypot(v_in...)
        len_out = hypot(v_out...)
        
        if len_in < 1e-10 || len_out < 1e-10
            bisectors[i] = (0.0, 0.0)
            speeds[i] = 0.0
            continue
        end
        
        # Normalize
        v_in = v_in ./ len_in
        v_out = v_out ./ len_out
        
        # Inward normals (90° CCW rotation for CCW polygon - interior is on LEFT)
        n_in = (-v_in[2], v_in[1])
        n_out = (-v_out[2], v_out[1])
        
        # Bisector direction
        bx, by = n_in[1] + n_out[1], n_in[2] + n_out[2]
        blen = hypot(bx, by)
        
        if blen < 1e-10
            bisectors[i] = (0.0, 0.0)
            speeds[i] = 0.0
        else
            bisectors[i] = (bx / blen, by / blen)
            # Speed = 1/sin(half interior angle)
            # sin(half_angle) = blen / 2
            speeds[i] = 2.0 / blen
        end
    end
    
    return bisectors, speeds
end

"""Find the next edge collapse event (smallest positive time)."""
function _find_next_collapse(pts, active, bisectors, speeds)
    n = length(active)
    t_min = Inf
    collapse_idx = 0
    
    for i in 1:n
        next_i = mod1(i + 1, n)
        
        # Ray-ray intersection: when do vertices i and next_i meet?
        p1 = pts[active[i]]
        p2 = pts[active[next_i]]
        d1 = bisectors[i] .* speeds[i]
        d2 = bisectors[next_i] .* speeds[next_i]
        
        t = _ray_ray_intersect_time(p1, d1, p2, d2)
        
        if t > 1e-10 && t < t_min
            t_min = t
            collapse_idx = i
        end
    end
    
    return t_min, collapse_idx
end

"""Find time t where two rays intersect (returns Inf if parallel/diverging)."""
function _ray_ray_intersect_time(p1, d1, p2, d2)
    # p1 + t*d1 = p2 + t*d2
    # (d1 - d2) * t = p2 - p1
    dx = d1[1] - d2[1]
    dy = d1[2] - d2[2]
    px = p2[1] - p1[1]
    py = p2[2] - p1[2]
    
    # Solve for t using both equations, check consistency
    denom = dx * dx + dy * dy
    if denom < 1e-20
        return Inf  # Parallel rays
    end
    
    t = (px * dx + py * dy) / denom
    return t
end

"""Compute centroid of active polygon."""
function _polygon_centroid(pts, active)
    cx, cy = 0.0, 0.0
    for ai in active
        cx += pts[ai][1]
        cy += pts[ai][2]
    end
    n = length(active)
    return (cx / n, cy / n)
end

"""Finalize tributary polygon: close it and compute area."""
function _finalize_tributary(edge_idx::Int, verts::Vector{NTuple{2,Float64}}, 
                             original_pts::Vector{NTuple{2,Float64}}, n_orig::Int)
    # Compute polygon area using shoelace formula
    area = _polygon_area(verts)
    total = _polygon_area(original_pts)
    frac = total > 0 ? abs(area) / total : 0.0
    
    return TributaryResult(edge_idx, verts, abs(area), frac)
end

"""Shoelace formula for polygon area."""
function _polygon_area(pts::Vector{NTuple{2,Float64}})
    n = length(pts)
    n >= 3 || return 0.0
    
    area = 0.0
    for i in 1:n
        j = mod1(i + 1, n)
        area += pts[i][1] * pts[j][2]
        area -= pts[j][1] * pts[i][2]
    end
    return area / 2
end
