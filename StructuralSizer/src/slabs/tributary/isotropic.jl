# =============================================================================
# Straight Skeleton for Convex Polygons (Isotropic Tributary Areas)
# =============================================================================

"""
    get_tributary_polygons_isotropic(vertices::Vector{<:Point})

Compute tributary polygons for each edge using straight skeleton (wavefront) algorithm.
Returns Vector{TributaryResult}, one per original edge.

For convex polygons only—no split events handled.
"""
function get_tributary_polygons_isotropic(vertices::Vector{<:Point})
    n = length(vertices)
    n >= 3 || return TributaryResult[]
    
    # Convert to simple 2D coords (strip units, work in meters)
    pts = [_to_2d(v) for v in vertices]
    original_pts = copy(pts)
    
    # Track edges at each wavefront level
    # edge_levels[level] = vector of edges, where edge[i] = (start_pt, end_pt)
    edge_levels = Vector{Vector{NTuple{2, NTuple{2,Float64}}}}()
    
    # Initial edges (level 0) - edge i goes from vertex i to vertex i+1
    initial_edges = [(pts[i], pts[mod1(i + 1, n)]) for i in 1:n]
    push!(edge_levels, initial_edges)
    
    # Current polygon state
    current_pts = copy(pts)
    n_active = n
    
    # Map from current vertex index to original edge index
    # edge starting at current vertex i corresponds to original edge edge_map[i]
    edge_map = collect(1:n)
    
    while n_active > 2
        # Compute bisectors at each active vertex
        bisectors, speeds = _compute_bisectors_active(current_pts, n_active)
        
        # Find next edge collapse
        t_min, collapse_idx = _find_next_collapse_active(current_pts, n_active, bisectors, speeds)
        
        if t_min == Inf || t_min <= 1e-10
            break
        end
        
        # Advance all vertices to time t_min
        new_pts = Vector{NTuple{2,Float64}}(undef, n_active)
        for i in 1:n_active
            bx, by = bisectors[i]
            s = speeds[i]
            px, py = current_pts[i]
            new_pts[i] = (px + bx * s * t_min, py + by * s * t_min)
        end
        
        # Record edges at this level
        level_edges = Vector{NTuple{2, NTuple{2,Float64}}}(undef, n)
        # Initialize with empty edges for original edges no longer active
        for i in 1:n
            level_edges[i] = ((0.0, 0.0), (0.0, 0.0))
        end
        # Fill in active edges
        for i in 1:n_active
            next_i = mod1(i + 1, n_active)
            orig_edge = edge_map[i]
            level_edges[orig_edge] = (new_pts[i], new_pts[next_i])
        end
        push!(edge_levels, level_edges)
        
        # Collapse: remove vertex at collapse_idx+1 (the edge at collapse_idx shrinks to zero)
        next_idx = mod1(collapse_idx + 1, n_active)
        merged_pt = new_pts[collapse_idx]
        
        # Build new vertex list and edge map (removing next_idx)
        new_current_pts = NTuple{2,Float64}[]
        new_edge_map = Int[]
        for i in 1:n_active
            if i == next_idx
                continue  # Skip the collapsed vertex
            end
            push!(new_current_pts, new_pts[i])
            push!(new_edge_map, edge_map[i])
        end
        
        # Update state
        current_pts = new_current_pts
        edge_map = new_edge_map
        n_active = length(current_pts)
    end
    
    # Final convergence for remaining 2-3 vertices
    if n_active >= 2
        bisectors, speeds = _compute_bisectors_active(current_pts, n_active)
        t_min, _ = _find_next_collapse_active(current_pts, n_active, bisectors, speeds)
        
        if t_min < Inf && t_min > 1e-10
            # Advance to final meeting point
            final_pts = Vector{NTuple{2,Float64}}(undef, n_active)
            for i in 1:n_active
                bx, by = bisectors[i]
                s = speeds[i]
                px, py = current_pts[i]
                final_pts[i] = (px + bx * s * t_min, py + by * s * t_min)
            end
            
            # Record final level
            level_edges = Vector{NTuple{2, NTuple{2,Float64}}}(undef, n)
            for i in 1:n
                level_edges[i] = ((0.0, 0.0), (0.0, 0.0))
            end
            for i in 1:n_active
                next_i = mod1(i + 1, n_active)
                orig_edge = edge_map[i]
                level_edges[orig_edge] = (final_pts[i], final_pts[next_i])
            end
            push!(edge_levels, level_edges)
        end
    end
    
    # Reorganize: edge_levels[level][edge] → sorted_by_edge[edge][level]
    sorted_by_edge = _reorganize_edge_levels(edge_levels, n)
    
    # Convert edges to polygon vertices
    tributary_polygons = _convert_edges_to_polygons(sorted_by_edge)
    
    # Build results
    total_area = abs(_polygon_area(original_pts))
    results = TributaryResult[]
    for i in 1:n
        poly_verts = tributary_polygons[i]
        area = abs(_polygon_area(poly_verts))
        frac = total_area > 0 ? area / total_area : 0.0
        push!(results, TributaryResult(i, poly_verts, area, frac))
    end
    
    return results
end

"""Compute bisectors and speeds for active vertices (simple array, 1:n_active)."""
function _compute_bisectors_active(pts::Vector{NTuple{2,Float64}}, n::Int)
    bisectors = Vector{NTuple{2,Float64}}(undef, n)
    speeds = Vector{Float64}(undef, n)
    
    for i in 1:n
        prev_i = mod1(i - 1, n)
        next_i = mod1(i + 1, n)
        
        p_prev = pts[prev_i]
        p_curr = pts[i]
        p_next = pts[next_i]
        
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
            speeds[i] = 2.0 / blen
        end
    end
    
    return bisectors, speeds
end

"""Find next edge collapse for active polygon."""
function _find_next_collapse_active(pts::Vector{NTuple{2,Float64}}, n::Int, bisectors, speeds)
    t_min = Inf
    collapse_idx = 0
    
    for i in 1:n
        next_i = mod1(i + 1, n)
        
        p1 = pts[i]
        p2 = pts[next_i]
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

"""Reorganize edge_levels[level][edge] → sorted_by_edge[edge][level]."""
function _reorganize_edge_levels(edge_levels, n_edges::Int)
    sorted_by_edge = [Vector{NTuple{2, NTuple{2,Float64}}}() for _ in 1:n_edges]
    
    for level in edge_levels
        for (edge_idx, edge) in enumerate(level)
            push!(sorted_by_edge[edge_idx], edge)
        end
    end
    
    return sorted_by_edge
end

"""Convert edge history to closed polygon vertices."""
function _convert_edges_to_polygons(sorted_by_edge)
    polygons = Vector{Vector{NTuple{2,Float64}}}()
    
    for edge_history in sorted_by_edge
        # Filter out zero/placeholder edges
        valid_edges = filter(e -> _dist(e[1], e[2]) > 1e-6 || 
                                   (_dist(e[1], (0.0,0.0)) > 1e-6), edge_history)
        
        if isempty(valid_edges)
            push!(polygons, NTuple{2,Float64}[])
            continue
        end
        
        nodes = NTuple{2,Float64}[]
        
        # Forward: collect start points (node 1) of each level
        for edge in valid_edges
            pt = edge[1]
            if isempty(nodes) || _dist(pt, nodes[end]) > 1e-6
                push!(nodes, pt)
            end
        end
        
        # Backward: collect end points (node 2) in reverse
        for edge in reverse(valid_edges)
            pt = edge[2]
            if isempty(nodes) || _dist(pt, nodes[end]) > 1e-6
                push!(nodes, pt)
            end
        end
        
        # Remove collinear points
        smoothed = _smooth_nodes(nodes)
        push!(polygons, smoothed)
    end
    
    return polygons
end

"""Remove collinear and duplicate points."""
function _smooth_nodes(nodes::Vector{NTuple{2,Float64}}; tol::Float64 = 0.01)
    length(nodes) <= 2 && return nodes
    
    result = [nodes[1]]
    
    for i in 2:length(nodes)
        pt = nodes[i]
        
        # Skip if too close to previous point
        if _dist(pt, result[end]) < tol
            continue
        end
        
        # Check collinearity with last two points
        if length(result) >= 2 && _is_collinear(result[end-1], result[end], pt; tol=tol)
            result[end] = pt  # Replace middle point
        else
            push!(result, pt)
        end
    end
    
    return result
end

"""Euclidean distance between two points."""
_dist(p1, p2) = hypot(p1[1] - p2[1], p1[2] - p2[2])

"""Check if three points are collinear within tolerance."""
function _is_collinear(p1, p2, p3; tol::Float64 = 0.01)
    cross = (p2[1] - p1[1]) * (p3[2] - p1[2]) - (p2[2] - p1[2]) * (p3[1] - p1[1])
    len = _dist(p1, p3)
    len < tol && return true
    return abs(cross) / len < tol
end
