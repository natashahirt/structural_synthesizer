# =============================================================================
# One-Way Directed Tributary Areas
# =============================================================================

"""
    get_tributary_polygons_one_way(vertices::Vector{<:Point}; weights=nothing, axis)

Compute tributary polygons using one-way directed partitioning along the specified axis.

Each interior point is assigned to the edge closest along ±axis direction.
Edges parallel to axis get zero area (they're never "closest" in this metric).

Algorithm:
1. Transform to (s,t) coordinates where t is perpendicular to the load-span axis
2. Sweep horizontal strips between consecutive vertex t-values  
3. Within each strip, partition the interior via weighted split between bounding edges
4. Sum trapezoid areas directly (exact, no polygon union needed)
5. Reconstruct polygons by tracing segment boundaries

Key insight: At any point (s,t) inside the polygon, exactly one edge "owns" it via
the weighted split rule. This guarantees a partition (no overlaps, no gaps) when
areas are computed directly from trapezoids.
"""
function get_tributary_polygons_one_way(vertices::Vector{<:Point}; weights=nothing, axis)
    m = length(vertices)
    m >= 3 || return TributaryResult[]
    
    # Convert to 2D coords and ensure CCW
    pts_orig = [_to_2d(v) for v in vertices]
    pts_orig = _ensure_ccw(pts_orig)
    
    # Normalize axis: u = load direction, n = perpendicular (sweep direction)
    vx, vy = Float64(axis[1]), Float64(axis[2])
    vlen = hypot(vx, vy)
    vlen < 1e-12 && error("axis must be non-zero")
    u = (vx / vlen, vy / vlen)
    n = (-u[2], u[1])
    
    # Handle weights
    w = isnothing(weights) ? ones(m) : Float64.(weights)
    
    # Transform to (s,t) coordinates
    pts_st = [_to_st(p, u, n) for p in pts_orig]
    
    # Get critical t-values (vertex t's) - these define strip boundaries
    t_vals = sort(unique([p[2] for p in pts_st]))
    length(t_vals) < 2 && return [TributaryResult(i, NTuple{2,Float64}[], 0.0, 0.0) for i in 1:m]
    
    # Accumulate area and boundary segments per edge
    # Each segment: (s_left_bot, s_right_bot, s_left_top, s_right_top, t_bot, t_top)
    edge_areas = zeros(m)
    edge_segments = [NTuple{6,Float64}[] for _ in 1:m]
    
    # Process each horizontal strip
    for k in 1:(length(t_vals) - 1)
        t0, t1 = t_vals[k], t_vals[k + 1]
        height = t1 - t0
        height < 1e-12 && continue
        
        # Get intervals at strip boundaries (slightly inside to avoid vertex issues)
        intervals_0 = _scanline_intervals(pts_st, t0 + 1e-12)
        intervals_1 = _scanline_intervals(pts_st, t1 - 1e-12)
        
        # Process each interval at t0 and find corresponding interval at t1
        for ((sL0, edgeL0), (sR0, edgeR0)) in intervals_0
            # Find matching interval at t1 (by midpoint containment)
            s_mid = (sL0 + sR0) / 2
            match_idx = findfirst(intervals_1) do int1
                (sL1, _), (sR1, _) = int1
                sL1 - 1e-9 <= s_mid <= sR1 + 1e-9
            end
            
            if isnothing(match_idx)
                # No match - use t0 interval for both (conservative)
                sL1, sR1 = sL0, sR0
            else
                (sL1, _), (sR1, _) = intervals_1[match_idx]
            end
            
            # Compute weighted splits
            split0 = _weighted_split(sL0, sR0, w[edgeL0], w[edgeR0])
            split1 = _weighted_split(sL1, sR1, w[edgeL0], w[edgeR0])  # Use same weights for consistency
            
            # Left region → attribute to edgeL0
            width_L0 = max(0.0, split0 - sL0)
            width_L1 = max(0.0, split1 - sL1)
            if width_L0 > 1e-12 || width_L1 > 1e-12
                area_L = (width_L0 + width_L1) / 2 * height
                edge_areas[edgeL0] += area_L
                push!(edge_segments[edgeL0], (sL0, split0, sL1, split1, t0, t1))
            end
            
            # Right region → attribute to edgeR0
            width_R0 = max(0.0, sR0 - split0)
            width_R1 = max(0.0, sR1 - split1)
            if width_R0 > 1e-12 || width_R1 > 1e-12
                area_R = (width_R0 + width_R1) / 2 * height
                edge_areas[edgeR0] += area_R
                push!(edge_segments[edgeR0], (split0, sR0, split1, sR1, t0, t1))
            end
        end
    end
    
    # Compute total area for fractions
    total_area = abs(_polygon_area(pts_orig))
    
    # Build results
    results = TributaryResult[]
    
    for i in 1:m
        if edge_areas[i] < 1e-12
            push!(results, TributaryResult(i, NTuple{2,Float64}[], 0.0, 0.0))
            continue
        end
        
        # Reconstruct polygon from segments
        poly_xy = _segments_to_polygon(edge_segments[i], u, n)
        
        # Use directly computed area (exact, not affected by polygon reconstruction)
        area = edge_areas[i]
        frac = total_area > 0 ? area / total_area : 0.0
        
        push!(results, TributaryResult(i, poly_xy, area, frac))
    end
    
    return results
end

# =============================================================================
# Coordinate Transforms
# =============================================================================

_to_st(p::NTuple{2,Float64}, u::NTuple{2,Float64}, n::NTuple{2,Float64}) = 
    (p[1]*u[1] + p[2]*u[2], p[1]*n[1] + p[2]*n[2])

_to_xy(s::Float64, t::Float64, u::NTuple{2,Float64}, n::NTuple{2,Float64}) = 
    (s*u[1] + t*n[1], s*u[2] + t*n[2])

# =============================================================================
# Scanline Intersection
# =============================================================================

"""Return intervals as [((sL, edgeL), (sR, edgeR)), ...] for scanline at t."""
function _scanline_intervals(pts_st::Vector{NTuple{2,Float64}}, t::Float64)
    nv = length(pts_st)
    crosses = Tuple{Float64,Int}[]
    
    for i in 1:nv
        j = mod1(i + 1, nv)
        s1, t1 = pts_st[i]
        s2, t2 = pts_st[j]
        
        abs(t2 - t1) < 1e-12 && continue  # skip horizontal edges
        
        # Half-open interval: include lower, exclude upper
        if (t1 <= t < t2) || (t2 <= t < t1)
            α = (t - t1) / (t2 - t1)
            s = s1 + α * (s2 - s1)
            push!(crosses, (s, i))
        end
    end
    
    sort!(crosses, by=x -> x[1])
    
    intervals = Tuple{Tuple{Float64,Int}, Tuple{Float64,Int}}[]
    for k in 1:2:(length(crosses) - 1)
        push!(intervals, (crosses[k], crosses[k+1]))
    end
    
    return intervals
end

# =============================================================================
# Weighted Split
# =============================================================================

"""Compute weighted split point between sL and sR based on edge weights."""
function _weighted_split(sL::Float64, sR::Float64, wL::Float64, wR::Float64)
    denom = wL + wR
    denom < 1e-12 && return (sL + sR) / 2
    # α = wR/(wL+wR) means higher wR pushes split toward sR (giving more area to left edge)
    α = wR / denom
    return (1 - α) * sL + α * sR
end

# =============================================================================
# Polygon Reconstruction from Segments
# =============================================================================

"""
Build polygon from vertical strip segments.

Each segment is (sL_bot, sR_bot, sL_top, sR_top, t_bot, t_top) representing
a trapezoid strip. Segments are stacked vertically and traced to form
the boundary polygon.

Key: We trace the actual segment boundaries, NOT min/max envelopes, to avoid
bridging across gaps that would cause overlapping polygons.
"""
function _segments_to_polygon(segments::Vector{NTuple{6,Float64}}, u::NTuple{2,Float64}, n::NTuple{2,Float64})
    isempty(segments) && return NTuple{2,Float64}[]
    
    # Sort segments by t_bot (vertical stacking order)
    sorted = sort(segments, by=seg->seg[5])
    
    # Build left and right boundary chains by tracing segment edges
    left_chain = NTuple{2,Float64}[]   # (s, t) left boundary, bottom to top
    right_chain = NTuple{2,Float64}[]  # (s, t) right boundary, bottom to top
    
    for seg in sorted
        sL_bot, sR_bot, sL_top, sR_top, t_bot, t_top = seg
        
        # Add bottom corners
        if isempty(left_chain)
            push!(left_chain, (sL_bot, t_bot))
            push!(right_chain, (sR_bot, t_bot))
        else
            # Check if this segment is contiguous with the previous one
            prev_t = left_chain[end][2]
            if abs(t_bot - prev_t) > 1e-9
                # Gap in t - need to close and restart (shouldn't happen for simple polygons)
                # For now, just add the new points
                push!(left_chain, (sL_bot, t_bot))
                push!(right_chain, (sR_bot, t_bot))
            elseif abs(left_chain[end][1] - sL_bot) > 1e-9
                # Discontinuity in s at same t - add connection point
                push!(left_chain, (sL_bot, t_bot))
            end
            if abs(right_chain[end][1] - sR_bot) > 1e-9
                push!(right_chain, (sR_bot, t_bot))
            end
        end
        
        # Add top corners
        push!(left_chain, (sL_top, t_top))
        push!(right_chain, (sR_top, t_top))
    end
    
    length(left_chain) < 2 && return NTuple{2,Float64}[]
    
    # Build polygon: left boundary (bottom→top), right boundary (top→bottom)
    poly_st = NTuple{2,Float64}[]
    
    for pt in left_chain
        if isempty(poly_st) || !_pts_equal(pt, poly_st[end])
            push!(poly_st, pt)
        end
    end
    
    for i in length(right_chain):-1:1
        pt = right_chain[i]
        if isempty(poly_st) || !_pts_equal(pt, poly_st[end])
            push!(poly_st, pt)
        end
    end
    
    length(poly_st) < 3 && return NTuple{2,Float64}[]
    
    # Close polygon
    if !_pts_equal(poly_st[1], poly_st[end])
        push!(poly_st, poly_st[1])
    end
    
    # Transform to (x,y)
    poly_xy = [_to_xy(s, t, u, n) for (s, t) in poly_st]
    
    # Simplify collinear points and ensure CCW
    poly_xy = _simplify_collinear(poly_xy)
    poly_xy = _ensure_ccw(poly_xy)
    
    return poly_xy
end

"""Remove collinear points from polygon."""
function _simplify_collinear(pts::Vector{NTuple{2,Float64}})
    length(pts) < 4 && return pts
    
    # Check if closed
    closed = _pts_equal(pts[1], pts[end])
    work = closed ? pts[1:end-1] : pts
    
    nv = length(work)
    nv < 3 && return pts
    
    result = NTuple{2,Float64}[]
    
    for i in 1:nv
        prev = work[mod1(i - 1, nv)]
        curr = work[i]
        next = work[mod1(i + 1, nv)]
        
        # Cross product for collinearity
        cross = (curr[1] - prev[1]) * (next[2] - curr[2]) - 
                (curr[2] - prev[2]) * (next[1] - curr[1])
        
        if abs(cross) > 1e-9
            push!(result, curr)
        end
    end
    
    length(result) < 3 && return pts
    
    # Re-close
    push!(result, result[1])
    return result
end

# =============================================================================
# Polygon Utilities  
# =============================================================================

_pts_equal(a::NTuple{2,Float64}, b::NTuple{2,Float64}) = hypot(a[1]-b[1], a[2]-b[2]) < 1e-9
