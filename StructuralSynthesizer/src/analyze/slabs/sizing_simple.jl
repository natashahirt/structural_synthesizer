# simple sizing of the slabs based on maximum span

# unique identifier for individual slabs
function get_slab_hash(skel::BuildingSkeleton{T}, face_idx::Int, span_axis::Union{Meshes.Vec{3, T}, Nothing}) where T
    polygon = skel.faces[face_idx]
    pts = Meshes.vertices(polygon)

    # span dimensions
    # perpendicular axis is 90 degrees to span_axis in xy plane
    perp_axis = !isnothing(span_axis) ? Meshes.Vec{-span_axis.y, span_axis.x, 0.0} : nothing
    projections_along = [ustrip(Meshes.coords(p).x * span_axis.x + Meshes.coords(p).y * span_axis.y) for p in pts]
    projections_perp = [ustrip(Meshes.coords(p).x * perp_axis.x + Meshes.coords(p).y * perp_axis.y) for p in pts]
    span_l = round(maximum(projections_along) - minimum(projections_along), digits=2)
    span_w = round(maximum(projections_perp) - minimum(projections_perp), digits=2)

    # geometry
    area = round(ustrip(Meshes.measure(polygon)), digits=2)
    n_vertices = length(pts)

    # edge lengths (shape invariant)
    edges = Meshes.segments(polygon)
    lengths = sort([round(ustrip(Meshes.measure(e)), digits=2) for e in edges])
    
    # combine into tuple
    return hash((n_vertices, area, lengths, span_l, span_w))
end

