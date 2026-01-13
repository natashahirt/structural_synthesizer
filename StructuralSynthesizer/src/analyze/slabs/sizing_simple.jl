# Simple slab sizing based on maximum span

"""Generate unique hash for face based on geometry and loads."""
function get_slab_hash(skel::BuildingSkeleton{T}, face_idx::Int, span_axis::Union{Meshes.Vec{3, T}, Nothing}, total_dl, total_ll) where T
    polygon = skel.faces[face_idx]
    pts = Meshes.vertices(polygon)

    if !isnothing(span_axis)
        u_axis = [ustrip(span_axis[1]), ustrip(span_axis[2]), ustrip(span_axis[3])]
        mag = sqrt(sum(u_axis.^2))
        u_axis ./= mag
        perp_axis = [-u_axis[2], u_axis[1], 0.0]
        
        projections_along = [ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).x)) * u_axis[1] + ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).y)) * u_axis[2] for p in pts]
        projections_perp = [ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).x)) * perp_axis[1] + ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).y)) * perp_axis[2] for p in pts]
        
        span_l = round(maximum(projections_along) - minimum(projections_along), digits=3)
        span_w = round(maximum(projections_perp) - minimum(projections_perp), digits=3)
    else
        span_l = round(maximum([ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.dist(p1, p2))) for p1 in pts, p2 in pts]), digits=3)
        span_w = span_l
    end

    area = round(ustrip(uconvert(Constants.STANDARD_AREA, Meshes.measure(polygon))), digits=3)
    n_v = length(pts)
    dl_metric = round(ustrip(uconvert(Constants.STANDARD_PRESSURE, total_dl)), digits=3)
    ll_metric = round(ustrip(uconvert(Constants.STANDARD_PRESSURE, total_ll)), digits=3)
    
    return hash((n_v, area, span_l, span_w, dl_metric, ll_metric))
end

"""Initialize slabs using L/28 thickness rule and auto-detected span axes."""
function initialize_slabs!(struc::BuildingStructure{T}; material=:concrete) where T
    skel = struc.skeleton
    empty!(struc.slabs)

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
            pts = Meshes.vertices(polygon)

            xs = [ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).x)) for p in pts]
            ys = [ustrip(uconvert(Constants.STANDARD_LENGTH, Meshes.coords(p).y)) for p in pts]
            lx, ly = maximum(xs)-minimum(xs), maximum(ys)-minimum(ys)
            l_short = min(lx, ly)
            
            span_axis = lx <= ly ? Meshes.Vec{3, T}(T(1.0), T(0.0), T(0.0)) : Meshes.Vec{3, T}(T(0.0), T(1.0), T(0.0))
            
            # L/28 rule
            thickness_val = max(0.125, l_short / 28.0)
            thickness = T <: Unitful.Quantity ? thickness_val * u"m" : T(thickness_val)

            sw = thickness_val * u"m" * Constants.ρ_CONCRETE * Constants.GRAVITY
            sw_f = uconvert(Constants.STANDARD_PRESSURE, sw * Constants.DL_FACTOR)
            total_dl_f = sdl_f + sw_f

            h = get_slab_hash(skel, face_idx, span_axis, total_dl_f, ll_f)

            if !haskey(struc.slab_sections, h)
                struc.slab_sections[h] = SlabSection(
                    h, thickness, material, Meshes.measure(polygon),
                    :one_way, span_axis, total_dl_f, ll_f
                )
            end

            push!(struc.slabs, Slab(face_idx, struc.slab_sections[h]))
        end
    end
    @debug "Initialized $(length(struc.slabs)) slabs into $(length(struc.slab_sections)) unique sections"
end
