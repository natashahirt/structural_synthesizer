# just does geometry, no loads yet
function to_asap(skel::BuildingSkeleton{T};
    default_section::Asap.Section,
    default_dof::Vector{Bool} = [true, true, true, false, false, false]
) where T

nodes = map(enumerate(skel.vertices)) do (idx, pt)
coords = Meshes.coords(pt)
pos = [
   round(ustrip(u"m", coords.x), digits=2), 
   round(ustrip(u"m", coords.y), digits=2), 
   round(ustrip(u"m", coords.z), digits=2)
] 
is_support = idx in get(skel.groups_vertices, :support, Int[])
dof = is_support ? [false, false, false, false, false, false] : default_dof
return Asap.Node(pos, dof)
end

# Build elements from edge_indices to avoid duplicates from groups
elements = [Asap.Element(nodes[v1], nodes[v2], default_section) for (v1, v2) in skel.edge_indices]
println("DEBUG: Converted to Asap model with $(length(nodes)) nodes and $(length(elements)) elements")

return Asap.Model(nodes, elements, Asap.NodeForce[])
end