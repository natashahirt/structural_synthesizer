# Tributary Area Computation (Straight Skeleton via DCEL and One-Way Directed)

include("utils.jl")
include("dcel.jl")
include("isotropic.jl")
include("one_way.jl")
include("spans.jl")

# =============================================================================
# Main Dispatch Function
# =============================================================================

"""
    get_tributary_polygons(vertices; weights=nothing, axis=nothing)

Compute tributary polygons for each edge of the polygon.

## Arguments
- `vertices::Vector{<:Point}`: Polygon vertices as Meshes.Point objects
- `weights::Union{Nothing, AbstractVector{<:Real}}`: Optional edge weights (one per edge)
- `axis::Union{Nothing, AbstractVector{<:Real}}`: Optional direction vector [vx, vy].
  If `nothing`, uses isotropic straight skeleton. If provided, partitions along that direction.

## Examples
```julia
# Isotropic (default)
results = get_tributary_polygons(vertices)

# Isotropic with weights
results = get_tributary_polygons(vertices; weights=[1.0, 2.0, 1.0, 2.0])

# Partition along x-axis
results = get_tributary_polygons(vertices; axis=[1.0, 0.0])

# Directed with weights
results = get_tributary_polygons(vertices; weights=[1.0, 2.0, 1.0, 2.0], axis=[1.0, 0.0])
```
"""
function get_tributary_polygons(
    vertices::Vector{<:Point};
    weights::Union{Nothing, AbstractVector{<:Real}} = nothing,
    axis::Union{Nothing, AbstractVector{<:Real}} = nothing
)
    if isnothing(axis) || hypot(axis[1], axis[2]) < 1e-12
        return get_tributary_polygons_isotropic(vertices; weights=weights)
    else
        return get_tributary_polygons_one_way(vertices; weights=weights, axis=axis)
    end
end