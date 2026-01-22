# Foundation visualization utilities

"""
    draw_spread_footing!(ax, fdn::Foundation, struc::BuildingStructure; kwargs...)

Draw a spread footing as a 3D box at the support location.

# Arguments
- `ax`: Makie Axis3
- `fdn`: Foundation with SpreadFootingResult
- `struc`: BuildingStructure (for support positions)
- `color`: Footing color (default: concrete gray)
- `alpha`: Transparency (default: 0.7)
- `show_rebar`: Whether to show rebar pattern (default: false)
"""
function draw_spread_footing!(ax, fdn::Foundation, struc::BuildingStructure;
                               color=:gray70, alpha=0.7, show_rebar=false)
    result = fdn.result
    result isa StructuralSizer.SpreadFootingResult || return
    
    # Get footing dimensions
    B = ustrip(u"m", result.B)
    L = ustrip(u"m", result.L_ftg)
    D = ustrip(u"m", result.D)
    
    # Get support position (centroid if multiple supports)
    positions = [struc.asap_model.nodes[struc.supports[i].node_idx].position 
                 for i in fdn.support_indices]
    centroid = sum(positions) ./ length(positions)
    cx, cy, cz = ustrip(u"m", centroid[1]), ustrip(u"m", centroid[2]), ustrip(u"m", centroid[3])
    
    # Footing bottom is at grade (z=0) or below
    z_top = 0.0  # Top of footing at grade
    z_bot = z_top - D
    
    # Create box vertices (8 corners)
    x_min, x_max = cx - B/2, cx + B/2
    y_min, y_max = cy - L/2, cy + L/2
    
    vertices = GLMakie.Point3f[
        (x_min, y_min, z_bot), (x_max, y_min, z_bot),
        (x_max, y_max, z_bot), (x_min, y_max, z_bot),
        (x_min, y_min, z_top), (x_max, y_min, z_top),
        (x_max, y_max, z_top), (x_min, y_max, z_top),
    ]
    
    # Box faces (triangulated)
    faces = GLMakie.TriangleFace[
        # Bottom
        (1, 2, 3), (1, 3, 4),
        # Top
        (5, 7, 6), (5, 8, 7),
        # Front (y_min)
        (1, 6, 2), (1, 5, 6),
        # Back (y_max)
        (3, 8, 4), (3, 7, 8),
        # Left (x_min)
        (1, 4, 8), (1, 8, 5),
        # Right (x_max)
        (2, 6, 7), (2, 7, 3),
    ]
    
    mesh = GLMakie.GeometryBasics.Mesh(vertices, faces)
    GLMakie.mesh!(ax, mesh, color=(color, alpha), transparency=true)
    
    # Outline edges for clarity
    edges = [
        # Bottom
        [vertices[1], vertices[2]], [vertices[2], vertices[3]],
        [vertices[3], vertices[4]], [vertices[4], vertices[1]],
        # Top
        [vertices[5], vertices[6]], [vertices[6], vertices[7]],
        [vertices[7], vertices[8]], [vertices[8], vertices[5]],
        # Verticals
        [vertices[1], vertices[5]], [vertices[2], vertices[6]],
        [vertices[3], vertices[7]], [vertices[4], vertices[8]],
    ]
    
    for edge in edges
        GLMakie.lines!(ax, edge, color=:gray40, linewidth=0.5)
    end
    
    # Optional: show rebar pattern on top face
    if show_rebar && result.rebar_count > 0
        _draw_footing_rebar!(ax, cx, cy, z_top, B, L, result)
    end
end

"""Draw rebar grid on top of footing."""
function _draw_footing_rebar!(ax, cx, cy, z_top, B, L, result::StructuralSizer.SpreadFootingResult)
    n_bars = result.rebar_count
    n_bars <= 0 && return
    
    # Cover offset
    cover = 0.075  # 75mm typical
    
    # Rebar in X direction
    y_positions = range(cy - L/2 + cover, cy + L/2 - cover, length=n_bars)
    for y in y_positions
        pts = [GLMakie.Point3f(cx - B/2 + cover, y, z_top + 0.01),
               GLMakie.Point3f(cx + B/2 - cover, y, z_top + 0.01)]
        GLMakie.lines!(ax, pts, color=:brown, linewidth=1.5)
    end
    
    # Rebar in Y direction
    x_positions = range(cx - B/2 + cover, cx + B/2 - cover, length=n_bars)
    for x in x_positions
        pts = [GLMakie.Point3f(x, cy - L/2 + cover, z_top + 0.01),
               GLMakie.Point3f(x, cy + L/2 - cover, z_top + 0.01)]
        GLMakie.lines!(ax, pts, color=:brown, linewidth=1.5)
    end
end

"""
    draw_foundations!(ax, struc::BuildingStructure; kwargs...)

Draw all foundations in the structure.

# Arguments
- `color`: Foundation color (default: :gray70)
- `alpha`: Transparency (default: 0.7)
- `show_rebar`: Show rebar pattern (default: false)
"""
function draw_foundations!(ax, struc::BuildingStructure;
                           color=:gray70, alpha=0.7, show_rebar=false)
    isempty(struc.foundations) && return
    
    for fdn in struc.foundations
        if fdn.result isa StructuralSizer.SpreadFootingResult
            draw_spread_footing!(ax, fdn, struc; color=color, alpha=alpha, show_rebar=show_rebar)
        elseif fdn.result isa StructuralSizer.CombinedFootingResult
            # TODO: Implement combined footing visualization
            draw_spread_footing!(ax, fdn, struc; color=color, alpha=alpha, show_rebar=show_rebar)
        elseif fdn.result isa StructuralSizer.PileCapResult
            # TODO: Implement pile cap visualization
            @warn "Pile cap visualization not yet implemented"
        end
    end
end
