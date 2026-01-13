# Cell and Slab initialization from skeleton faces

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

"""
Compute slab thickness using StructuralSizer.min_thickness.
Dispatches on slab_type symbol → AbstractSlabType.
"""
function compute_thickness(slab_type_sym::Symbol, span_short::Real, material::AbstractMaterial)
    st = slab_type(slab_type_sym)  # Symbol → dispatch type
    return min_thickness(st, span_short, material)
end

"""Initialize cells from skeleton faces (geometry + loads, no thickness)."""
function initialize_cells!(struc::BuildingStructure{T, A, P}; 
                           material::AbstractMaterial=NWC_4000) where {T, A, P}
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
            l_short = min(ustrip(span_x), ustrip(span_y))
            
            # Estimate thickness for self-weight calc
            thickness_est = max(0.125, l_short / 28.0)
            sw = thickness_est * u"m" * material.ρ * Constants.GRAVITY
            sw_f = uconvert(Constants.STANDARD_PRESSURE, sw * Constants.DL_FACTOR)
            total_dl_f = sdl_f + sw_f
            
            cell = Cell(face_idx, area, span_x, span_y, total_dl_f, ll_f)
            push!(struc.cells, cell)
        end
    end
    
    @debug "Initialized $(length(struc.cells)) cells"
end

"""
Initialize slabs from cells.

# Arguments
- `struc`: BuildingStructure to populate
- `material`: Concrete material for thickness calculation (default: NWC_4000)
- `default_slab_type`: Override auto-inference (:one_way, :two_way, :flat_plate, etc.)
- `cell_groupings`: Explicit cell→slab mappings for PT/continuous slabs

# Slab type inference
If `default_slab_type` is `:auto`, infers from aspect ratio:
- ratio > 2.0 → :one_way
- else → :two_way
"""
function initialize_slabs!(struc::BuildingStructure{T};
                           material::AbstractMaterial=NWC_4000,
                           default_slab_type::Symbol=:auto,
                           cell_groupings::Union{Nothing, Vector{Vector{Int}}}=nothing) where T
    empty!(struc.slabs)
    
    if isnothing(cell_groupings)
        # Default: 1 slab per cell
        for (cell_idx, cell) in enumerate(struc.cells)
            span_x, span_y = ustrip(cell.span_x), ustrip(cell.span_y)
            l_short = min(span_x, span_y)
            
            # Determine slab type
            st_sym = default_slab_type == :auto ? infer_slab_type(span_x, span_y) : default_slab_type
            
            # Compute thickness via StructuralSizer
            thickness_val = compute_thickness(st_sym, l_short, material)
            thickness = T <: Unitful.Quantity ? thickness_val * u"m" : T(thickness_val)
            
            span_axis = span_x <= span_y ? (1.0, 0.0, 0.0) : (0.0, 1.0, 0.0)
            slab = Slab(cell_idx, thickness; slab_type=st_sym, span_axis=span_axis)
            push!(struc.slabs, slab)
        end
    else
        # Explicit groupings: combine cells into slabs (PT, etc.)
        for cell_indices in cell_groupings
            cells = [struc.cells[i] for i in cell_indices]
            
            # Governing span for thickness
            l_short_gov = maximum(min(ustrip(c.span_x), ustrip(c.span_y)) for c in cells)
            
            # For grouped slabs, default to :pt_banded unless specified
            st_sym = default_slab_type == :auto ? :pt_banded : default_slab_type
            
            thickness_val = compute_thickness(st_sym, l_short_gov, material)
            thickness = T <: Unitful.Quantity ? thickness_val * u"m" : T(thickness_val)
            
            slab = Slab(cell_indices, thickness; slab_type=st_sym)
            push!(struc.slabs, slab)
        end
    end
    
    @debug "Initialized $(length(struc.slabs)) slabs from $(length(struc.cells)) cells"
end
