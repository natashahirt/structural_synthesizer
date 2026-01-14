# Cell and Slab initialization from skeleton faces

# =============================================================================
# Unit Conversion Helpers
# =============================================================================

"""Convert thickness from StructuralSizer result (Float64 in m) to typed length."""
function to_thickness(::Type{T}, result::AbstractFloorResult) where T
    h = total_depth(result)
    return T <: Unitful.Quantity ? h * u"m" : T(h)
end

"""Convert self-weight from StructuralSizer result (Float64 in kN/m²) to factored pressure."""
function to_factored_self_weight(result::AbstractFloorResult)
    sw = self_weight(result)
    return sw * u"kN/m^2" * Constants.DL_FACTOR
end

# =============================================================================
# Geometry Helpers
# =============================================================================

"""Compute cell spans from skeleton face."""
function get_cell_spans(skel::BuildingSkeleton{T}, face_idx::Int) where T
    polygon = skel.faces[face_idx]
    pts = Meshes.vertices(polygon)
    
    xs = [ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).x)) for p in pts]
    ys = [ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).y)) for p in pts]
    
    span_x = T <: Unitful.Quantity ? (maximum(xs) - minimum(xs)) * u"m" : T(maximum(xs) - minimum(xs))
    span_y = T <: Unitful.Quantity ? (maximum(ys) - minimum(ys)) * u"m" : T(maximum(ys) - minimum(ys))
    
    return span_x, span_y
end

"""Initialize cells from skeleton faces (geometry + superimposed loads)."""
function initialize_cells!(struc::BuildingStructure{T, A, P}) where {T, A, P}
    skel = struc.skeleton
    empty!(struc.cells)
    
    load_map = [
        :grade => (Constants.LL_GRADE_f, Constants.SDL_FLOOR_f),
        :floor => (Constants.LL_FLOOR_f, Constants.SDL_FLOOR_f),
        :roof  => (Constants.LL_ROOF_f,  Constants.SDL_ROOF_f)
    ]
    
    processed_faces = Set{Int}()
    
    for (grp_name, loads) in load_map
        face_indices = get(skel.groups_faces, grp_name, Int[])
        ll_f, sdl_f = loads
        
        for face_idx in face_indices
            face_idx in processed_faces && continue
            push!(processed_faces, face_idx)
            
            polygon = skel.faces[face_idx]
            area = Meshes.measure(polygon)
            span_x, span_y = get_cell_spans(skel, face_idx)
            
            # Store SDL only; self-weight computed after slab sizing
            cell = Cell(face_idx, area, span_x, span_y, sdl_f, ll_f)
            push!(struc.cells, cell)
        end
    end
    
    @debug "Initialized $(length(struc.cells)) cells"
end

"""
Initialize slabs from cells using unified size_floor API.

# Arguments
- `struc`: BuildingStructure to populate
- `material`: Material for sizing (default: NWC_4000)
- `floor_type`: Override auto-inference (:auto, :one_way, :two_way, :flat_plate, etc.)
- `cell_groupings`: Explicit cell→slab mappings for PT/continuous slabs

# Floor type inference
If `floor_type` is `:auto`, infers from aspect ratio:
- ratio > 2.0 → :one_way
- else → :two_way
"""
function initialize_slabs!(struc::BuildingStructure{T};
                           material::AbstractMaterial=NWC_4000,
                           floor_type::Symbol=:auto,
                           cell_groupings::Union{Nothing, Vector{Vector{Int}}}=nothing) where T
    empty!(struc.slabs)
    
    if isnothing(cell_groupings)
        # Default: 1 slab per cell
        for (cell_idx, cell) in enumerate(struc.cells)
            span_x, span_y = ustrip(cell.span_x), ustrip(cell.span_y)
            l_short = min(span_x, span_y)
            load = ustrip(cell.sdl + cell.live_load)
            
            # Determine floor type
            ft_sym = floor_type == :auto ? infer_floor_type(span_x, span_y) : floor_type
            ft = StructuralSizer.floor_type(ft_sym)
            
            # Size floor via unified API
            result = size_floor(ft, l_short, load; material=material)
            thickness = to_thickness(T, result)
            cell.self_weight = to_factored_self_weight(result)
            
            span_axis = span_x <= span_y ? (1.0, 0.0, 0.0) : (0.0, 1.0, 0.0)
            slab = Slab(cell_idx, thickness; floor_type=ft_sym, span_axis=span_axis)
            push!(struc.slabs, slab)
        end
    else
        # Explicit groupings: combine cells into slabs (PT, etc.)
        for cell_indices in cell_groupings
            cells = [struc.cells[i] for i in cell_indices]
            
            # Governing span for sizing
            l_short_gov = maximum(min(ustrip(c.span_x), ustrip(c.span_y)) for c in cells)
            load_gov = maximum(ustrip(c.sdl + c.live_load) for c in cells)
            
            # For grouped slabs, default to :pt_banded unless specified
            ft_sym = floor_type == :auto ? :pt_banded : floor_type
            ft = StructuralSizer.floor_type(ft_sym)
            
            result = size_floor(ft, l_short_gov, load_gov; material=material)
            thickness = to_thickness(T, result)
            sw_factored = to_factored_self_weight(result)
            
            for c in cells
                c.self_weight = sw_factored
            end
            
            slab = Slab(cell_indices, thickness; floor_type=ft_sym)
            push!(struc.slabs, slab)
        end
    end
    
    @debug "Initialized $(length(struc.slabs)) slabs from $(length(struc.cells)) cells"
end
