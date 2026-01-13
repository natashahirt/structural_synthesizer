# Segment and Member initialization from skeleton edges

"""Compute segment length from skeleton edge."""
function get_segment_length(skel::BuildingSkeleton{T}, edge_idx::Int) where T
    seg = skel.edges[edge_idx]
    L = Meshes.measure(seg)
    return T <: Unitful.Quantity ? L : ustrip(L)
end

"""Initialize segments from all skeleton edges."""
function initialize_segments!(struc::BuildingStructure{T}; 
                              default_Lb_ratio=1.0, default_Cb=1.0) where T
    skel = struc.skeleton
    empty!(struc.segments)
    
    for edge_idx in eachindex(skel.edges)
        L = get_segment_length(skel, edge_idx)
        Lb = L * default_Lb_ratio
        
        segment = Segment(edge_idx, L; Lb=Lb, Cb=default_Cb)
        push!(struc.segments, segment)
    end
    
    @debug "Initialized $(length(struc.segments)) segments"
end

"""
Initialize members from segments.
Default: each segment becomes its own member (1:1 mapping).
Override by passing explicit segment groupings.
"""
function initialize_members!(struc::BuildingStructure{T}; 
                             segment_groupings::Union{Nothing, Vector{Vector{Int}}}=nothing,
                             default_Kx=1.0, default_Ky=1.0) where T
    empty!(struc.members)
    
    if isnothing(segment_groupings)
        # Default: 1 member per segment
        for (seg_idx, seg) in enumerate(struc.segments)
            member = Member(seg_idx, seg.L; Lb=seg.Lb, Kx=default_Kx, Ky=default_Ky, Cb=seg.Cb)
            push!(struc.members, member)
        end
    else
        # Explicit groupings: combine segments into members
        for seg_indices in segment_groupings
            segs = [struc.segments[i] for i in seg_indices]
            # Governing values
            L_gov = sum(s.L for s in segs)
            Lb_gov = maximum(s.Lb for s in segs)
            Cb_gov = minimum(s.Cb for s in segs)  # conservative
            
            member = Member(seg_indices, L_gov; Lb=Lb_gov, Kx=default_Kx, Ky=default_Ky, Cb=Cb_gov)
            push!(struc.members, member)
        end
    end
    
    @debug "Initialized $(length(struc.members)) members from $(length(struc.segments)) segments"
end

"""Update Lb for segments based on bracing conditions."""
function update_bracing!(struc::BuildingStructure{T}; braced_by_slabs=true) where T
    if braced_by_slabs
        # TODO: compute Lb from slab attachment points
    end
    @debug "Updated bracing for $(length(struc.segments)) segments"
end
