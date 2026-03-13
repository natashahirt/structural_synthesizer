# =============================================================================
# Spatial Lookup Utilities for BuildingSkeleton
# =============================================================================
# Provides O(1) vertex/edge/face lookups via hash tables.
# The SkeletonLookup struct is defined in types.jl and stored in skel.lookup.

# =============================================================================
# Key Generation
# =============================================================================

"""Round point coordinates for hash key (handles both Unitful and plain Float64)."""
@inline function _coord_key(pt::Meshes.Point)::NTuple{3, Float64}
    c = Meshes.coords(pt)
    x = to_meters(c.x)
    y = to_meters(c.y)
    z = to_meters(c.z)
    (round(x, digits=COORD_DIGITS),
     round(y, digits=COORD_DIGITS),
     round(z, digits=COORD_DIGITS))
end

"""Canonical face key (sorted vertex indices for order-independent lookup)."""
@inline function _face_key(v_indices::AbstractVector{Int})::Vector{Int}
    sort(v_indices)
end

# =============================================================================
# Enable/Build Lookup
# =============================================================================

"""
    enable_lookup!(skel::BuildingSkeleton)

Enable O(1) lookups for a skeleton. Call BEFORE adding vertices/edges/faces
to get automatic incremental updates. For existing skeletons, use `build_lookup!`.

# Example
```julia
skel = BuildingSkeleton{typeof(1.0u"m")}()
enable_lookup!(skel)  # Enable before building
# Now add_vertex!, add_element!, add_face! are O(1)
```
"""
function enable_lookup!(skel::BuildingSkeleton)
    skel.lookup = SkeletonLookup()
    return skel
end

"""
    build_lookup!(skel::BuildingSkeleton)

Build lookup tables from existing skeleton data. Call AFTER skeleton is built
if lookups weren't enabled during construction.

# Example
```julia
# Skeleton already has vertices/edges/faces
build_lookup!(skel)  # Build lookup from existing data
```
"""
function build_lookup!(skel::BuildingSkeleton)
    lookup = SkeletonLookup()
    
    # Vertices
    for (i, pt) in enumerate(skel.vertices)
        lookup.vertex_index[_coord_key(pt)] = i
    end
    
    # Edges (both orderings for direction-independent lookup)
    for (i, (v1, v2)) in enumerate(skel.edge_indices)
        lookup.edge_index[(v1, v2)] = i
        lookup.edge_index[(v2, v1)] = i
    end
    
    # Faces
    for (i, v_indices) in enumerate(skel.face_vertex_indices)
        lookup.face_index[_face_key(v_indices)] = i
    end
    
    lookup.version = 1
    skel.lookup = lookup
    return skel
end

"""
    disable_lookup!(skel::BuildingSkeleton)

Disable lookups (frees memory). Skeleton functions fall back to O(n) search.
"""
function disable_lookup!(skel::BuildingSkeleton)
    skel.lookup = nothing
    return skel
end

# =============================================================================
# Lookup Functions (used internally by skeleton functions)
# =============================================================================

"""O(1) lookup of vertex index by coordinates. Returns `nothing` if not found."""
function find_vertex(skel::BuildingSkeleton, pt::Meshes.Point)::Union{Int, Nothing}
    isnothing(skel.lookup) && return findfirst(v -> v == pt, skel.vertices)
    get(skel.lookup.vertex_index, _coord_key(pt), nothing)
end

"""O(1) lookup of edge index by vertex indices (order-independent)."""
function find_edge(skel::BuildingSkeleton, v1::Int, v2::Int)::Union{Int, Nothing}
    isnothing(skel.lookup) && return findfirst(e -> e == (v1, v2) || e == (v2, v1), skel.edge_indices)
    get(skel.lookup.edge_index, (v1, v2), nothing)
end

"""O(1) lookup of face index by vertex indices (order-independent)."""
function find_face(skel::BuildingSkeleton, v_indices::AbstractVector{Int})::Union{Int, Nothing}
    isnothing(skel.lookup) && return findfirst(f -> sort(f) == sort(v_indices), skel.face_vertex_indices)
    get(skel.lookup.face_index, _face_key(v_indices), nothing)
end

# =============================================================================
# Registration Functions (called automatically by add_* functions)
# =============================================================================

"""Register a new vertex in the lookup (if enabled)."""
function _register_vertex!(skel::BuildingSkeleton, idx::Int, pt::Meshes.Point)
    isnothing(skel.lookup) && return
    skel.lookup.vertex_index[_coord_key(pt)] = idx
    skel.lookup.version += 1
end

"""Register a new edge in the lookup (if enabled)."""
function _register_edge!(skel::BuildingSkeleton, idx::Int, v1::Int, v2::Int)
    isnothing(skel.lookup) && return
    skel.lookup.edge_index[(v1, v2)] = idx
    skel.lookup.edge_index[(v2, v1)] = idx
    skel.lookup.version += 1
end

"""Register a new face in the lookup (if enabled)."""
function _register_face!(skel::BuildingSkeleton, idx::Int, v_indices::AbstractVector{Int})
    isnothing(skel.lookup) && return
    skel.lookup.face_index[_face_key(v_indices)] = idx
    skel.lookup.version += 1
end

# =============================================================================
# Validation
# =============================================================================

"""Check that lookup tables are consistent with skeleton (for debugging)."""
function validate_lookup(skel::BuildingSkeleton)::Bool
    isnothing(skel.lookup) && return true
    
    for (i, pt) in enumerate(skel.vertices)
        find_vertex(skel, pt) == i || (@warn "Vertex mismatch" i; return false)
    end
    
    for (i, (v1, v2)) in enumerate(skel.edge_indices)
        find_edge(skel, v1, v2) == i || (@warn "Edge mismatch" i; return false)
    end
    
    for (i, v_indices) in enumerate(skel.face_vertex_indices)
        find_face(skel, v_indices) == i || (@warn "Face mismatch" i; return false)
    end
    
    return true
end
