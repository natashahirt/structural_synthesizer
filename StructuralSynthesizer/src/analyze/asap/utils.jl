"""
    to_asap!(struc; diaphragms=:none, shell_props=nothing)

Converts a BuildingStructure into an Asap.Model.
Uses TributaryLoads for accurate load distribution based on tributary polygons.

# Arguments
- `struc`: BuildingStructure to convert
- `diaphragms::Symbol=:none`: Diaphragm modeling approach
  - `:none` — No diaphragm modeling (default)
  - `:rigid` — Rigid diaphragm (very stiff shell elements, E=1e15 Pa)
  - `:shell` — Semi-rigid shell elements from slab geometry
- `shell_props::Union{Nothing, NamedTuple}=nothing`: Custom shell properties for `:shell` or `:rigid`
  - `E`: Young's modulus (default: 30 GPa for `:shell`, 1e15 Pa for `:rigid`)
  - `ν`: Poisson's ratio (default: 0.2)
  - `t_factor`: Thickness multiplier (default: 1.0)

# Examples
```julia
# No diaphragm (fastest, for gravity-only)
to_asap!(struc)

# Rigid diaphragm (typical for lateral analysis)
to_asap!(struc; diaphragms=:rigid)

# Shell diaphragm with custom properties
to_asap!(struc; diaphragms=:shell, shell_props=(E=25e9u"Pa", ν=0.15))

# Override rigid diaphragm stiffness
to_asap!(struc; diaphragms=:rigid, shell_props=(E=1e12u"Pa",))
```
"""
function to_asap!(struc::BuildingStructure{T, A, P}; 
                  diaphragms::Symbol=:none,
                  shell_props::Union{Nothing, NamedTuple}=nothing) where {T, A, P}
    
    diaphragms in (:none, :rigid, :shell) || error("diaphragms must be :none, :rigid, or :shell")
    
    skel = struc.skeleton
    
    # 1. Nodes
    support_indices = get(skel.groups_vertices, :support, Int[])
    
    nodes = map(enumerate(skel.vertices)) do (v_idx, v)
        coords = Meshes.coords(v)
        x = uconvert(u"m", coords.x)
        y = uconvert(u"m", coords.y)
        z = uconvert(u"m", coords.z)
        
        is_support = v_idx in support_indices
        dofs = is_support ? [false, false, false, false, false, false] : [true, true, true, false, false, false]
        return Asap.Node([x, y, z], dofs)
    end

    # 2. Frame Elements
    default_section = AsapToolkit.toASAPframe("W10x22", unit=u"m")
    frame_elements = map(skel.edge_indices) do (v1, v2)
        return Asap.Element(nodes[v1], nodes[v2], default_section, release=:fixedfixed)
    end
    
    # 3. Shell Diaphragm elements (for both :rigid and :shell)
    shell_elements = Asap.ShellElement[]
    
    if diaphragms in (:rigid, :shell) && !isempty(struc.slabs)
        shell_elements = _create_shell_diaphragms(struc, nodes; 
                                                   mode=diaphragms, props=shell_props)
        @debug "Created diaphragm shells" mode=diaphragms n_shells=length(shell_elements)
    end
    
    # 4. Compute tributaries if not done
    isempty(struc.cell_groups) && build_cell_groups!(struc)
    compute_cell_tributaries!(struc)  # Cache handles deduplication
    
    # 5. Create loads using TributaryLoad
    loads = Asap.AbstractLoad[]
    empty!(struc.cell_tributary_loads)
    
    for (cell_idx, cell) in enumerate(struc.cells)
        cell_loads = _create_cell_tributary_loads!(loads, frame_elements, skel, struc, cell, cell_idx)
        struc.cell_tributary_loads[cell_idx] = cell_loads
    end
    
    # 6. Add structural effects (e.g., vault thrust)
    for slab in struc.slabs
        for spec in slab_edge_line_loads(struc, slab)
            el = frame_elements[spec.edge_idx]
            push_asap_loads!(loads, el, spec)
        end
    end

    # 7. Build model (frame elements only for now - shells contribute to K separately)
    struc.asap_model = Asap.Model(nodes, frame_elements, loads)
    
    @debug "Converted to Asap.Model" nodes=length(nodes) frame_elements=length(frame_elements) shell_elements=length(shell_elements) loads=length(loads)

    Asap.process!(struc.asap_model)
    Asap.solve!(struc.asap_model)

    return struc.asap_model
end

# =============================================================================
# Shell Diaphragm Implementation
# =============================================================================

"""
Create shell diaphragms for all slabs.

For `:rigid` mode: uses very high E (1e15 Pa) for effectively infinite in-plane stiffness.
For `:shell` mode: uses actual slab properties or custom overrides.
"""
function _create_shell_diaphragms(struc::BuildingStructure, nodes::Vector{Asap.Node};
                                   mode::Symbol=:shell,
                                   props::Union{Nothing, NamedTuple}=nothing)
    shells = Asap.ShellElement[]
    
    # Default properties based on mode
    if mode == :rigid
        # Rigid diaphragm: very high stiffness (effectively infinite)
        E_default = 1e15u"Pa"
        ν_default = 0.0  # No Poisson effect for rigid
        t_factor = 1.0
    else  # :shell
        # Semi-rigid: actual concrete properties
        E_default = 30e9u"Pa"
        ν_default = 0.2
        t_factor = 1.0
    end
    
    # Override with custom properties if provided
    if props !== nothing
        E_default = get(props, :E, E_default)
        ν_default = get(props, :ν, ν_default)
        t_factor = get(props, :t_factor, t_factor)
    end
    
    for slab in struc.slabs
        slab_shells = create_slab_diaphragm_shells(struc, slab, nodes; 
                                                    E=E_default, ν=ν_default, t_factor=t_factor)
        append!(shells, slab_shells)
    end
    
    return shells
end

"""Create TributaryLoads for a single cell from its tributary polygons."""
function _create_cell_tributary_loads!(
    loads::Vector{Asap.AbstractLoad},
    elements::Vector{<:Asap.Element},
    skel::BuildingSkeleton,
    struc::BuildingStructure,
    cell::Cell,
    cell_idx::Int
)::Vector{Asap.TributaryLoad}
    cell_loads = Asap.TributaryLoad[]
    
    # Get tributaries from cache
    tribs = cell_edge_tributaries(struc, cell_idx)
    isnothing(tribs) && return cell_loads
    
    face_edges = skel.face_edge_indices[cell.face_idx]
    face_verts = skel.face_vertex_indices[cell.face_idx]
    pressure = uconvert(u"Pa", total_factored_pressure(cell))
    n_verts = length(face_verts)
    
    for trib in tribs
        # Skip empty tributaries
        trib.area < 1e-12 && continue
        length(trib.s) < 2 && continue
        
        # Extract width profile from tributary polygon
        positions, widths_m = _extract_width_profile(trib)
        length(positions) < 2 && continue
        
        # Map local edge index to global edge/element
        local_idx = trib.local_edge_idx
        global_edge_idx = face_edges[local_idx]
        el = elements[global_edge_idx]
        
        # Check if edge direction matches face CCW order
        # Face expects: face_verts[local_idx] → face_verts[local_idx+1]
        # Edge stored as: skel.edge_indices[global_edge_idx] = (v1, v2)
        expected_v1 = face_verts[local_idx]
        expected_v2 = face_verts[mod1(local_idx + 1, n_verts)]
        actual_v1, actual_v2 = skel.edge_indices[global_edge_idx]
        
        # If edge is reversed relative to face CCW order, flip the parametric positions
        edge_reversed = (actual_v1 == expected_v2 && actual_v2 == expected_v1)
        
        if edge_reversed
            # Flip: s → 1-s, and reverse the arrays to maintain sorted order
            positions = reverse(1.0 .- positions)
            widths_m = reverse(widths_m)
        end
        
        # Convert widths to Unitful
        widths = [w * u"m" for w in widths_m]
        
        # Create TributaryLoad (gravity direction)
        tload = Asap.TributaryLoad(el, positions, widths, pressure, (0.0, 0.0, -1.0))
        
        push!(loads, tload)
        push!(cell_loads, tload)
    end
    
    return cell_loads
end

"""
Extract a sorted width profile from a TributaryPolygon.

The polygon vertices trace the boundary, but TributaryLoad needs positions
sorted along the beam with corresponding widths.

Returns (positions, widths) where positions are in [0,1] sorted order.
"""
function _extract_width_profile(trib::TributaryPolygon)
    isempty(trib.s) && return (Float64[], Float64[])
    
    # Collect (s, |d|) pairs and sort by s
    pairs = [(trib.s[i], abs(trib.d[i])) for i in eachindex(trib.s)]
    sort!(pairs, by=first)
    
    # Remove duplicates (keep max width at each position)
    merged = Tuple{Float64, Float64}[]
    for (s, w) in pairs
        if isempty(merged) || abs(s - merged[end][1]) > 1e-9
            push!(merged, (s, w))
        else
            # Same position - keep max width
            merged[end] = (merged[end][1], max(merged[end][2], w))
        end
    end
    
    # Extract separate vectors
    positions = [p[1] for p in merged]
    widths = [p[2] for p in merged]
    
    # Ensure positions are clamped to [0, 1]
    positions = clamp.(positions, 0.0, 1.0)
    
    return (positions, widths)
end

"""
    update_slab_loads!(struc, slab_idx)

Update tributary load pressures when a slab's properties change.
Call this after modifying slab sizing results, then the model will be re-solved.
"""
function update_slab_loads!(struc::BuildingStructure, slab_idx::Int)
    slab = struc.slabs[slab_idx]
    sw = StructuralSizer.self_weight(slab.result)
    
    for cell_idx in slab.cell_indices
        cell = struc.cells[cell_idx]
        cell.self_weight = sw
        
        new_pressure = uconvert(u"Pa", total_factored_pressure(cell))
        
        for tload in get(struc.cell_tributary_loads, cell_idx, Asap.TributaryLoad[])
            tload.pressure = new_pressure
        end
    end
    
    Asap.solve!(struc.asap_model; reprocess=true)
end

"""
    update_all_slab_loads!(struc)

Update all tributary load pressures and re-solve.
"""
function update_all_slab_loads!(struc::BuildingStructure)
    for slab_idx in eachindex(struc.slabs)
        slab = struc.slabs[slab_idx]
        sw = StructuralSizer.self_weight(slab.result)
        
        for cell_idx in slab.cell_indices
            cell = struc.cells[cell_idx]
            cell.self_weight = sw
            
            new_pressure = uconvert(u"Pa", total_factored_pressure(cell))
            
            for tload in get(struc.cell_tributary_loads, cell_idx, Asap.TributaryLoad[])
                tload.pressure = new_pressure
            end
        end
    end
    
    Asap.solve!(struc.asap_model; reprocess=true)
end

# =============================================================================
# Slab → edge load interface
# =============================================================================

"""
    push_asap_loads!(loads, element, spec)

Convert a backend-agnostic edge load spec into ASAP loads.
Assumes `spec` magnitudes are base SI (N, N/m).
"""
function push_asap_loads!(loads::Vector{Asap.AbstractLoad}, el::Asap.Element, spec::AbstractEdgeLoadSpec)
    error("No ASAP conversion defined for $(typeof(spec))")
end

function push_asap_loads!(loads::Vector{Asap.AbstractLoad}, el::Asap.Element, spec::EdgeLineLoadSpec)
    # Convert Float64 line load (assumed SI N/m) to Unitful
    w_unitful = [w * u"N/m" for w in collect(spec.w)]
    push!(loads, Asap.LineLoad(el, w_unitful))
    return loads
end

"""
    slab_face_edge_ids(struc, slab) -> Vector{Int}

Return the unique set of skeleton edges referenced by the slab's faces.
"""
function slab_face_edge_ids(struc::BuildingStructure, slab::Slab)
    skel = struc.skeleton

    edge_set = Set{Int}()
    for cell_idx in slab.cell_indices
        face_idx = struc.cells[cell_idx].face_idx
        for e_idx in skel.face_edge_indices[face_idx]
            push!(edge_set, e_idx)
        end
    end

    edge_ids = collect(edge_set)
    sort!(edge_ids)  # deterministic ordering (useful for reproducibility/debug)
    return edge_ids
end

"""Internal helper: structural effects as `EdgeLineLoadSpec` (e.g. vault thrust)."""
function slab_edge_line_loads(struc::BuildingStructure, slab::Slab)::Vector{EdgeLineLoadSpec}
    effects = StructuralSizer.structural_effects(slab.result)
    isempty(effects) && return EdgeLineLoadSpec[]

    loads = EdgeLineLoadSpec[]

    for eff in effects
        if eff isa StructuralSizer.LateralThrust
            append!(loads, vault_thrust_line_loads(struc, slab, eff))
        end
    end

    return loads
end

# --- Vault thrust → edge line loads (simple implementation) ---
function vault_thrust_line_loads(struc::BuildingStructure, slab::Slab, eff::StructuralSizer.LateralThrust)::Vector{EdgeLineLoadSpec}
    # Factored thrust (consistent with other factored load usage in the model)
    thrust_factored = eff.dead * Constants.DL_FACTOR + eff.live * Constants.LL_FACTOR
    mag_N_m = ustrip(u"N/m", uconvert(u"N/m", thrust_factored))

    # Span axis from slab spans
    span_vec = [slab.spans.axis[1], slab.spans.axis[2], 0.0]

    # Vault slabs are enforced as single rectangular faces; thrust acts on that perimeter.
    face_idx = struc.cells[first(slab.cell_indices)].face_idx
    skel = struc.skeleton
    boundary_edges = skel.face_edge_indices[face_idx]

    out = EdgeLineLoadSpec[]
    for e_idx in boundary_edges
        edge = skel.edges[e_idx]
        p1, p2 = Meshes.vertices(edge)
        c1, c2 = Meshes.coords(p1), Meshes.coords(p2)

        v = [c2.x - c1.x, c2.y - c1.y, c2.z - c1.z]
        v_norm = v / sqrt(sum(v .^ 2))
        is_perpendicular = abs(sum(v_norm .* span_vec)) < 0.1
        is_perpendicular || continue

        # Determine "outward" direction (simple heuristic from previous implementation)
        mid = [(c1.x + c2.x) / 2, (c1.y + c2.y) / 2, (c1.z + c2.z) / 2]
        f_poly = skel.faces[face_idx]
        f_pts = Meshes.vertices(f_poly)
        f_xs = [Meshes.coords(p).x for p in f_pts]
        f_ys = [Meshes.coords(p).y for p in f_pts]
        f_zs = [Meshes.coords(p).z for p in f_pts]
        f_mid = [sum(f_xs) / length(f_pts), sum(f_ys) / length(f_pts), sum(f_zs) / length(f_pts)]

        out_vec = mid .- f_mid
        proj = sum(out_vec .* span_vec)
        # `proj` carries length units; compare against a unit-consistent zero.
        dir = proj > zero(proj) ? span_vec : -span_vec

        w = (dir[1] * mag_N_m, dir[2] * mag_N_m, dir[3] * mag_N_m)
        push!(out, EdgeLineLoadSpec(Int(e_idx), w))
    end

    return out
end

# =============================================================================
# Diaphragm Shell Creation
# =============================================================================

"""
    create_slab_diaphragm_shells(struc, slab, nodes; E, ν, t_factor) -> Vector{<:Asap.ShellElement}

Create shell elements for a slab's diaphragm action from its cell faces.

# Arguments
- `struc`: BuildingStructure containing the slab
- `slab`: Slab object with sizing result
- `nodes`: Vector of Asap.Node (indexed same as skeleton vertices)
- `E`: Young's modulus (default uses slab concrete or 30 GPa)
- `ν`: Poisson's ratio (default 0.2)
- `t_factor`: Thickness multiplier (default 1.0)

# Returns
Vector of ShellTri3 or ShellQuad4 elements.
"""
function create_slab_diaphragm_shells(struc::BuildingStructure, slab::Slab, nodes::Vector{Asap.Node};
                                       E=nothing, ν::Float64=0.2, t_factor::Float64=1.0)
    skel = struc.skeleton
    
    # Get slab thickness (with optional scaling)
    t = thickness(slab) * t_factor
    
    # Determine E: use provided, or try slab concrete, or default
    if E === nothing
        E = 30e9u"Pa"  # default concrete
        if hasfield(typeof(slab.result), :concrete) && slab.result.concrete !== nothing
            if hasfield(typeof(slab.result.concrete), :E)
                E = slab.result.concrete.E
            end
        end
    end
    
    # Collect face indices for this slab
    face_indices = [struc.cells[ci].face_idx for ci in slab.cell_indices]
    
    # Create shells from face meshes
    shells = create_diaphragm_elements(skel, face_indices, nodes, t, E, ν; prefer_quad=true)
    
    # Assign global DOFs to each shell
    for shell in shells
        Asap.populate_globalID!(shell)
    end
    
    return shells
end

# Deprecated: use to_asap!(struc; diaphragms=:shell) instead
function to_asap_with_diaphragms!(struc::BuildingStructure; include_diaphragms::Bool=true)
    @warn "to_asap_with_diaphragms! is deprecated. Use to_asap!(struc; diaphragms=:shell) instead." maxlog=1
    return to_asap!(struc; diaphragms=include_diaphragms ? :shell : :none)
end