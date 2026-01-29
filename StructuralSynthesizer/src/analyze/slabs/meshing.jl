# =============================================================================
# Meshing Utilities for Shell Elements
# =============================================================================
# Convert skeleton faces (Meshes.Polygon) to shell element meshes

using LinearAlgebra: dot, norm
using Unitful: ustrip

"""
    coords_to_vec(point) -> Vector{Float64}

Convert a Meshes.Point to a plain Float64 vector (unitless, in base units).
"""
function coords_to_vec(point)
    c = Meshes.coords(point)
    # Access x, y, z properties and strip units
    x = c.x isa Number ? Float64(c.x) : Float64(ustrip(c.x))
    y = c.y isa Number ? Float64(c.y) : Float64(ustrip(c.y))
    z = c.z isa Number ? Float64(c.z) : Float64(ustrip(c.z))
    return [x, y, z]
end

"""
    is_quad_suitable(polygon::Meshes.Polygon) -> Bool

Check if a polygon is suitable for a single Quad4 element:
- Has exactly 4 vertices
- Is reasonably rectangular (angles close to 90°)
"""
function is_quad_suitable(polygon::Meshes.Polygon; angle_tolerance=15.0)
    verts = Meshes.vertices(polygon)
    length(verts) != 4 && return false
    
    # Check internal angles are close to 90°
    for i in 1:4
        p1 = coords_to_vec(verts[mod1(i-1, 4)])
        p2 = coords_to_vec(verts[i])
        p3 = coords_to_vec(verts[mod1(i+1, 4)])
        
        v1 = p1 - p2
        v2 = p3 - p2
        
        # Compute angle in degrees
        cos_angle = dot(v1, v2) / (norm(v1) * norm(v2))
        angle = acosd(clamp(cos_angle, -1.0, 1.0))
        
        # Check if close to 90°
        abs(angle - 90.0) > angle_tolerance && return false
    end
    
    return true
end

"""
    triangulate_polygon_fan(polygon::Meshes.Polygon) -> Vector{NTuple{3, Int}}

Simple fan triangulation from first vertex.
Returns vector of (i, j, k) vertex index tuples.
Works for convex polygons.
"""
function triangulate_polygon_fan(polygon::Meshes.Polygon)
    verts = Meshes.vertices(polygon)
    n = length(verts)
    n < 3 && return NTuple{3, Int}[]
    
    # Fan from vertex 1
    triangles = NTuple{3, Int}[]
    for i in 2:n-1
        push!(triangles, (1, i, i+1))
    end
    
    return triangles
end

"""
    triangulate_polygon_ear(polygon::Meshes.Polygon) -> Vector{NTuple{3, Int}}

Ear-clipping triangulation for general (possibly non-convex) polygons.
Returns vector of (i, j, k) vertex index tuples.
"""
function triangulate_polygon_ear(polygon::Meshes.Polygon)
    verts = collect(Meshes.vertices(polygon))
    n = length(verts)
    n < 3 && return NTuple{3, Int}[]
    n == 3 && return [(1, 2, 3)]
    
    # For simplicity, use fan triangulation (works for convex)
    # TODO: Implement proper ear-clipping for non-convex
    return triangulate_polygon_fan(polygon)
end

"""
    ElementSpec

Specification for a shell element to be created.
"""
struct ElementSpec
    type::Symbol         # :tri3 or :quad4
    vertex_indices::Vector{Int}  # indices into skeleton vertices
end

"""
    mesh_face(skel::BuildingSkeleton, face_idx::Int; 
              prefer_quad=true, quad_angle_tol=15.0) -> Vector{ElementSpec}

Mesh a skeleton face into shell element specifications.

# Arguments
- `skel`: Building skeleton
- `face_idx`: Index of face to mesh
- `prefer_quad`: If true, use single Quad4 for suitable 4-vertex faces
- `quad_angle_tol`: Angle tolerance (degrees) for quad suitability

# Returns
Vector of ElementSpec describing elements to create.
"""
function mesh_face(skel::BuildingSkeleton, face_idx::Int; 
                   prefer_quad=true, quad_angle_tol=15.0)
    polygon = skel.faces[face_idx]
    vert_indices = skel.face_vertex_indices[face_idx]
    n_verts = length(vert_indices)
    
    # Try quad if suitable
    if prefer_quad && n_verts == 4 && is_quad_suitable(polygon; angle_tolerance=quad_angle_tol)
        return [ElementSpec(:quad4, copy(vert_indices))]
    end
    
    # Otherwise triangulate
    tri_local = triangulate_polygon_fan(polygon)
    
    return [ElementSpec(:tri3, [vert_indices[i], vert_indices[j], vert_indices[k]]) 
            for (i, j, k) in tri_local]
end

"""
    mesh_faces(skel::BuildingSkeleton, face_indices::Vector{Int}; kwargs...) -> Vector{ElementSpec}

Mesh multiple skeleton faces.
"""
function mesh_faces(skel::BuildingSkeleton, face_indices::Vector{Int}; kwargs...)
    specs = ElementSpec[]
    for face_idx in face_indices
        append!(specs, mesh_face(skel, face_idx; kwargs...))
    end
    return specs
end

# =============================================================================
# Create Shell Elements from Specs
# =============================================================================

"""
    create_shell_elements(specs::Vector{ElementSpec}, nodes::Vector{Asap.Node},
                          thickness, E, ν) -> Vector{<:Asap.ShellElement}

Create Asap shell elements from element specifications.

# Arguments
- `specs`: Vector of ElementSpec from meshing
- `nodes`: Asap nodes (indexed same as skeleton vertices)
- `thickness`: Element thickness (Unitful)
- `E`: Young's modulus (Unitful)
- `ν`: Poisson's ratio
"""
function create_shell_elements(specs::Vector{ElementSpec}, nodes::Vector{Asap.Node},
                               thickness, E, ν)
    elements = Asap.ShellElement[]
    
    for spec in specs
        if spec.type == :tri3
            i, j, k = spec.vertex_indices
            elem = Asap.ShellTri3((nodes[i], nodes[j], nodes[k]), thickness, E, ν)
        elseif spec.type == :quad4
            i, j, k, l = spec.vertex_indices
            elem = Asap.ShellQuad4((nodes[i], nodes[j], nodes[k], nodes[l]), thickness, E, ν)
        else
            error("Unknown element type: $(spec.type)")
        end
        
        Asap.process!(elem)
        push!(elements, elem)
    end
    
    return elements
end

"""
    create_diaphragm_elements(skel::BuildingSkeleton, face_indices::Vector{Int},
                              nodes::Vector{Asap.Node}, thickness, E, ν;
                              prefer_quad=true) -> Vector{<:Asap.ShellElement}

Create shell elements for a floor diaphragm from skeleton faces.

# Arguments
- `skel`: Building skeleton
- `face_indices`: Indices of faces comprising the diaphragm
- `nodes`: Asap nodes (indexed same as skeleton vertices)
- `thickness`: Slab thickness
- `E`: Young's modulus (typically concrete)
- `ν`: Poisson's ratio
"""
function create_diaphragm_elements(skel::BuildingSkeleton, face_indices::Vector{Int},
                                   nodes::Vector{Asap.Node}, thickness, E, ν;
                                   prefer_quad=true)
    specs = mesh_faces(skel, face_indices; prefer_quad=prefer_quad)
    return create_shell_elements(specs, nodes, thickness, E, ν)
end
