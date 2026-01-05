function gen_medium_office(x::Unitful.Length, y::Unitful.Length, floor_height::Unitful.Length, x_bays::Int64, y_bays::Int64, n_floors::Int64)::BuildingSkeleton
    # expect linear values
    # convert everything to meters internally
    x = uconvert(u"m", x)
    y = uconvert(u"m", y)
    floor_height = uconvert(u"m", floor_height)

    T = typeof(x)
    skel = BuildingSkeleton{T}()
    
    # get bay spans
    x_span = round(ustrip(x/x_bays), digits=2) * unit(x)
    y_span = round(ustrip(y/y_bays), digits=2) * unit(y)

    # get stories_z (starting from 0.0)
    push!(skel.stories_z, round(ustrip(0.0*floor_height), digits=2) * unit(floor_height))
    for k in 1:n_floors
        push!(skel.stories_z, round(ustrip(k*floor_height), digits=2) * unit(floor_height))
    end

    # helper function (k is now 0-indexed offset for stories_z vector)
    get_pt(i, j, k) = Meshes.Point(i*x_span, j*y_span, skel.stories_z[k+1])

    # get elements
    for k in 1:n_floors
        # x direction beams
        for j in 0:y_bays, i in 0:(x_bays-1)
            p1 = get_pt(i, j, k)
            p2 = get_pt(i+1, j, k)
            add_element!(skel, Meshes.Segment(p1, p2), group=:beams, level_idx=k)
        end
        # y direction beams
        for i in 0:x_bays, j in 0:(y_bays-1)
            p1 = get_pt(i, j, k)
            p2 = get_pt(i, j+1, k)
            add_element!(skel, Meshes.Segment(p1, p2), group=:beams, level_idx=k)
        end
        # columns
        for i in 0:x_bays, j in 0:y_bays
            p_bot = get_pt(i, j, k-1)
            p_top = get_pt(i, j, k)
            add_element!(skel, Meshes.Segment(p_bot, p_top), group=:columns, level_idx=k)
        end
    end

    # designate points (add_vertex! will assign known points to a group)
    for i in 0:x_bays, j in 0:y_bays
        # story 0 points are support nodes
        add_vertex!(skel, get_pt(i, j, 0), group=:support)
        # story n_floors points are the roof (no DOF implications but nice to have)
        add_vertex!(skel, get_pt(i, j, n_floors), group=:roof)
    end

    # postprocessing - find the faces
    find_faces!(skel)

    return skel
end