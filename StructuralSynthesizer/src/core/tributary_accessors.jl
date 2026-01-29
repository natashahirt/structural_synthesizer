# =============================================================================
# Tributary Accessors for BuildingStructure
# =============================================================================
#
# Higher-level convenience functions for accessing tributary data stored in
# BuildingStructure.tributaries (TributaryCache).
#
# These operate on BuildingStructure and provide a clean API for:
# - Column tributary areas (Voronoi)
# - Cell edge tributaries (straight skeleton / directed)
# - Strip geometry (column/middle strip split)
# =============================================================================

"""
    tributary_cache_key(behavior, axis) -> TributaryCacheKey

Create a cache key for tributary lookup.

# Examples
```julia
key = tributary_cache_key(:one_way, [1.0, 0.0])  # One-way along X
key = tributary_cache_key(:two_way, nothing)     # Isotropic
key = tributary_cache_key(OneWaySpanning(), [0.0, 1.0])  # One-way along Y
```
"""
tributary_cache_key(behavior::Symbol, axis) = TributaryCacheKey(behavior, 
    isnothing(axis) ? UInt64(0) : hash((round(axis[1], digits=6), round(axis[2], digits=6))))
tributary_cache_key(behavior::SpanningBehavior, axis) = TributaryCacheKey(behavior, axis)

# =============================================================================
# Column (Vertex) Tributary Accessors
# =============================================================================

"""
    get_cached_column_tributary(struc, story, vertex_idx)

Get cached Voronoi tributary for a column, or nothing if not cached.
"""
function get_cached_column_tributary(struc::BuildingStructure, story::Int, vertex_idx::Int)
    return get_vertex_tributary(struc.tributaries, story, vertex_idx)
end

"""
    cache_column_tributary!(struc, story, vertex_idx, total_area, by_cell, polygons)

Store column Voronoi tributary in the cache.
"""
function cache_column_tributary!(struc::BuildingStructure, story::Int, vertex_idx::Int,
                                  total_area::Float64,
                                  by_cell::Dict{Int, Float64},
                                  polygons::Dict{Int, Vector{NTuple{2,Float64}}})
    result = ColumnTributaryResult(total_area, by_cell, polygons)
    set_vertex_tributary!(struc.tributaries, story, vertex_idx, result)
    return result
end

"""
    column_tributary_area(struc, col)

Get total tributary area for a column from the cache.
Returns area in m² as Float64, or nothing if not computed.
"""
function column_tributary_area(struc::BuildingStructure, col)
    cached = get_vertex_tributary(struc.tributaries, col.story, col.vertex_idx)
    isnothing(cached) && return nothing
    return cached.total_area
end

"""
    column_tributary_by_cell(struc, col)

Get per-cell tributary area breakdown for a column from the cache.
Returns Dict{Int, Float64} (cell_idx → area in m²), or empty Dict if not computed.
"""
function column_tributary_by_cell(struc::BuildingStructure, col)
    cached = get_vertex_tributary(struc.tributaries, col.story, col.vertex_idx)
    isnothing(cached) && return Dict{Int, Float64}()
    return cached.by_cell
end

"""
    column_tributary_polygons(struc, col)

Get tributary polygon vertices for a column from the cache (for visualization).
Returns Dict{Int, Vector{NTuple{2,Float64}}} (cell_idx → polygon vertices), or empty Dict if not computed.
"""
function column_tributary_polygons(struc::BuildingStructure, col)
    cached = get_vertex_tributary(struc.tributaries, col.story, col.vertex_idx)
    isnothing(cached) && return Dict{Int, Vector{NTuple{2,Float64}}}()
    return cached.polygons
end

# =============================================================================
# Cell Edge Tributary Accessors
# =============================================================================

"""
    get_cached_edge_tributaries(struc, behavior, axis, cell_idx)

Get cached edge tributaries for a cell, or nothing if not cached.

# Arguments
- `struc`: BuildingStructure
- `behavior`: :one_way, :two_way, :beamless (or SpanningBehavior type)
- `axis`: Direction vector [vx, vy] or nothing for isotropic
- `cell_idx`: Cell index
"""
function get_cached_edge_tributaries(struc::BuildingStructure, behavior, axis, cell_idx::Int)
    key = tributary_cache_key(behavior, axis)
    return get_edge_tributaries(struc.tributaries, key, cell_idx)
end

"""
    cache_edge_tributaries!(struc, behavior, axis, cell_idx, tributaries; strip_geometry=nothing)

Store edge tributaries in the cache.
"""
function cache_edge_tributaries!(struc::BuildingStructure, behavior, axis, cell_idx::Int, 
                                  tributaries::Vector{<:TributaryPolygon};
                                  strip_geometry::Union{PanelStripGeometry, Nothing}=nothing)
    key = tributary_cache_key(behavior, axis)
    result = CellTributaryResult(tributaries, strip_geometry)
    set_edge_tributaries!(struc.tributaries, key, cell_idx, result)
    return result
end

"""
    cell_edge_tributaries(struc, cell_idx, behavior, axis)

Get edge tributaries for a cell from the cache.
Returns Vector{TributaryPolygon} or nothing if not computed.
"""
function cell_edge_tributaries(struc::BuildingStructure, cell_idx::Int, behavior, axis)
    cached = get_cached_edge_tributaries(struc, behavior, axis, cell_idx)
    isnothing(cached) && return nothing
    return cached.edge_tributaries
end

"""
    cell_edge_tributaries(struc, cell_idx)

Get edge tributaries for a cell using its floor_type to determine behavior/axis.
Returns Vector{TributaryPolygon} or nothing if not computed.
"""
function cell_edge_tributaries(struc::BuildingStructure, cell_idx::Int)
    cell = struc.cells[cell_idx]
    ft = StructuralSizer.floor_type(cell.floor_type)
    behavior = StructuralSizer.spanning_behavior(ft)
    axis = StructuralSizer.resolve_tributary_axis(ft, cell.spans)
    return cell_edge_tributaries(struc, cell_idx, behavior, axis)
end

"""
    cell_strip_geometry(struc, cell_idx, behavior, axis)

Get strip geometry (column/middle strip split) for a cell from the cache.
Returns PanelStripGeometry or nothing if not computed.
"""
function cell_strip_geometry(struc::BuildingStructure, cell_idx::Int, behavior, axis)
    cached = get_cached_edge_tributaries(struc, behavior, axis, cell_idx)
    isnothing(cached) && return nothing
    return cached.strip_geometry
end

"""
    has_cell_tributaries(struc, cell_idx, behavior, axis)

Check if edge tributaries are cached for a cell.
"""
function has_cell_tributaries(struc::BuildingStructure, cell_idx::Int, behavior, axis)
    return !isnothing(get_cached_edge_tributaries(struc, behavior, axis, cell_idx))
end

# =============================================================================
# Cache Management
# =============================================================================

"""
    clear_tributary_cache!(struc)

Clear all cached tributaries. Forces recalculation on next access.
"""
clear_tributary_cache!(struc::BuildingStructure) = clear!(struc.tributaries)

"""
    list_cached_tributary_keys(struc)

List all cached tributary configuration keys.
"""
function list_cached_tributary_keys(struc::BuildingStructure)
    return collect(keys(struc.tributaries.edge))
end
