# Cell and Slab initialization from skeleton faces

# =============================================================================
# Geometry Helpers
# =============================================================================

"""
    get_cell_spans(skel, face_idx)

Return `(span_x, span_y)` as the axis-aligned bounding-box spans of a face.
This assumes the slab bay is roughly aligned to global X/Y (good enough for sizing).
"""
function get_cell_spans(skel::BuildingSkeleton{T}, face_idx::Int) where T
    polygon = skel.faces[face_idx]
    pts = Meshes.vertices(polygon)
    
    xs = [Meshes.coords(p).x for p in pts]
    ys = [Meshes.coords(p).y for p in pts]
    
    span_x = maximum(xs) - minimum(xs)
    span_y = maximum(ys) - minimum(ys)
    
    return span_x, span_y
end

"""Initialize cells from skeleton faces (geometry + service SDL/LL)."""
function initialize_cells!(struc::BuildingStructure{T, A, P}) where {T, A, P}
    skel = struc.skeleton
    empty!(struc.cells)
    
    load_map = [
        :grade => (Constants.LL_GRADE, Constants.SDL_FLOOR),
        :floor => (Constants.LL_FLOOR, Constants.SDL_FLOOR),
        :roof  => (Constants.LL_ROOF,  Constants.SDL_ROOF)
    ]
    
    processed_faces = Set{Int}()
    
    for (grp_name, loads) in load_map
        face_indices = get(skel.groups_faces, grp_name, Int[])
        ll, sdl = loads
        
        for face_idx in face_indices
            face_idx in processed_faces && continue
            push!(processed_faces, face_idx)
            
            polygon = skel.faces[face_idx]
            area = Meshes.measure(polygon)
            span_x, span_y = get_cell_spans(skel, face_idx)
            
            # Store service loads
            cell = Cell(face_idx, area, span_x, span_y, sdl, ll)
            push!(struc.cells, cell)
        end
    end
    
    @debug "Initialized $(length(struc.cells)) cells"
end

"""
Initialize slabs from cells using `StructuralSizer.size_floor`.

Notes:
- `Cell` stores **service** `sdl`/`live_load`. Slab sizing computes service self-weight.
- The `span` passed to `size_floor(ft, span, ...)` depends on floor type; see `_sizing_span`.
"""
function initialize_slabs!(struc::BuildingStructure{T};
                           material::AbstractMaterial=NWC_4000,
                           floor_type::Symbol=:auto,
                           floor_kwargs::NamedTuple=NamedTuple(),
                           cell_groupings::Union{Nothing, Vector{Vector{Int}}}=nothing) where T
    empty!(struc.slabs)
    
    if isnothing(cell_groupings)
        # Default: 1 slab per cell
        for (cell_idx, cell) in enumerate(struc.cells)
            span_x, span_y = cell.span_x, cell.span_y
            
            # Determine floor type
            ft_sym = floor_type == :auto ? infer_floor_type(span_x, span_y) : floor_type
            ft = StructuralSizer.floor_type(ft_sym)

            if ft isa Vault
                _assert_rectangular_vault_face!(struc, cell.face_idx)
            end

            # Choose the governing span expected by each sizing implementation.
            span_for_sizing = _sizing_span(ft, span_x, span_y)
            
            # Build kwargs with type-specific defaults
            kwargs = _build_floor_kwargs(ft, span_for_sizing, floor_kwargs)
            
            # Size floor via unified API (using service loads)
            result = size_floor(ft, span_for_sizing, cell.sdl, cell.live_load; material=material, kwargs...)
            cell.self_weight = StructuralSizer.self_weight(result)
            
            span_axis = span_x <= span_y ? (1.0, 0.0, 0.0) : (0.0, 1.0, 0.0)
            slab = Slab(cell_idx, result; floor_type=ft_sym, span_axis=span_axis)
            push!(struc.slabs, slab)
        end
    else
        # Explicit groupings: combine cells into slabs (PT, etc.)
        for cell_indices in cell_groupings
            cells = [struc.cells[i] for i in cell_indices]
            
            # Governing spans for sizing (using service loads)
            span_x_gov = maximum(c.span_x for c in cells)
            span_y_gov = maximum(c.span_y for c in cells)
            sdl_gov = maximum(c.sdl for c in cells)
            live_gov = maximum(c.live_load for c in cells)
            
            # For grouped slabs, default to :pt_banded unless specified
            ft_sym = floor_type == :auto ? :pt_banded : floor_type
            ft = StructuralSizer.floor_type(ft_sym)

            if ft isa Vault
                throw(ArgumentError("Vault slabs must be a single rectangular face; got a grouped slab with $(length(cell_indices)) cells."))
            end

            span_for_sizing = _sizing_span(ft, span_x_gov, span_y_gov)
            
            # Build kwargs with type-specific defaults
            kwargs = _build_floor_kwargs(ft, span_for_sizing, floor_kwargs)
            
            result = size_floor(ft, span_for_sizing, sdl_gov, live_gov; material=material, kwargs...)
            sw_service = StructuralSizer.self_weight(result)
            
            for c in cells
                c.self_weight = sw_service
            end
            
            slab = Slab(cell_indices, result; floor_type=ft_sym)
            push!(struc.slabs, slab)
        end
    end
    
    @debug "Initialized $(length(struc.slabs)) slabs from $(length(struc.cells)) cells"
end

# =============================================================================
# Sizing span conventions
# =============================================================================

"""
Pick the `span` passed into `size_floor(ft, span, ...)`.

- Default: short span (`min(span_x, span_y)`)
- Two-way/plate/PT/waffle ACI thickness rules: long span (`max(span_x, span_y)`)
"""
_sizing_span(::AbstractFloorSystem, span_x, span_y) = min(span_x, span_y)

# ACI two-way / plate / waffle / PT thickness rules are based on the long span.
_sizing_span(::TwoWay, span_x, span_y) = max(span_x, span_y)
_sizing_span(::FlatPlate, span_x, span_y) = max(span_x, span_y)
_sizing_span(::FlatSlab, span_x, span_y) = max(span_x, span_y)
_sizing_span(::PTBanded, span_x, span_y) = max(span_x, span_y)
_sizing_span(::Waffle, span_x, span_y) = max(span_x, span_y)

# =============================================================================
# Structural Effects Application
# =============================================================================

"""
Apply vault thrust effects to the building structure model.
Identifies support edges and applies outward horizontal LineLoads to ASAP members.
"""
function StructuralSizer.apply_effects!(::Vault, struc::BuildingStructure, slab::Slab)
    # Keep this method for compatibility, but delegate to the unified edge-load interface.
    _assert_rectangular_vault_face!(struc, struc.cells[first(slab.cell_indices)].face_idx)

    for ll in slab_edge_line_loads(struc, slab)
        el = struc.asap_model.elements[ll.edge_idx]
        push!(struc.asap_model.loads, Asap.LineLoad(el, collect(ll.w)))
    end
end

# --- Vault geometry guard ---
function _assert_rectangular_vault_face!(struc::BuildingStructure, face_idx::Int; tol=1e-8)
    skel = struc.skeleton
    poly = skel.faces[face_idx]
    pts = Meshes.vertices(poly)

    length(pts) == 4 || throw(ArgumentError("Vault requires a rectangular face (4 vertices); face $face_idx has $(length(pts)) vertices."))

    cs = Meshes.coords.(pts)
    vs = [(cs[2].x - cs[1].x, cs[2].y - cs[1].y),
          (cs[3].x - cs[2].x, cs[3].y - cs[2].y),
          (cs[4].x - cs[3].x, cs[4].y - cs[3].y),
          (cs[1].x - cs[4].x, cs[1].y - cs[4].y)]

    norms = [sqrt(v[1]^2 + v[2]^2) for v in vs]
    # `norms` carries length units (Unitful); interpret `tol` in the same length unit.
    # (Default `tol=1e-8` means ~1e-8 of the coordinate length unit, typically meters.)
    norm_unit = unit(first(norms))
    tol_len = tol * norm_unit
    all(n -> n > tol_len, norms) || throw(ArgumentError("Vault face $face_idx is degenerate (zero-length edge)."))

    dot12 = abs((vs[1][1]*vs[2][1] + vs[1][2]*vs[2][2]) / (norms[1]*norms[2]))
    dot23 = abs((vs[2][1]*vs[3][1] + vs[2][2]*vs[3][2]) / (norms[2]*norms[3]))
    dot34 = abs((vs[3][1]*vs[4][1] + vs[3][2]*vs[4][2]) / (norms[3]*norms[4]))
    dot41 = abs((vs[4][1]*vs[1][1] + vs[4][2]*vs[1][2]) / (norms[4]*norms[1]))

    (dot12 < 1e-6 && dot23 < 1e-6 && dot34 < 1e-6 && dot41 < 1e-6) ||
        throw(ArgumentError("Vault requires an orthogonal rectangular face; face $face_idx is not orthogonal within tolerance."))
end

# =============================================================================
# Type-specific Default Kwargs
# =============================================================================

"""
Build kwargs for size_floor with type-specific defaults.
"""
function _build_floor_kwargs(ft::AbstractFloorSystem, span, user_kwargs::NamedTuple)
    defaults = _default_floor_kwargs(ft, span, user_kwargs)
    return merge(defaults, user_kwargs)
end

# Default: no extra kwargs needed
_default_floor_kwargs(::AbstractFloorSystem, span, user_kwargs::NamedTuple) = NamedTuple()

# Vault: default lambda = 10 (span/rise = 10) unless user provides rise or lambda
function _default_floor_kwargs(::Vault, span, user_kwargs::NamedTuple)
    # Only add lambda if user hasn't provided rise or lambda
    has_rise = haskey(user_kwargs, :rise) && !isnothing(user_kwargs.rise)
    has_lambda = haskey(user_kwargs, :lambda) && !isnothing(user_kwargs.lambda)
    
    if !has_rise && !has_lambda
        return (lambda=10.0,)
    end
    return NamedTuple()
end
