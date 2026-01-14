# Top-level initialization for BuildingStructure

"""
Initialize all structural components of a BuildingStructure.

# Arguments
- `material`: Material for slab sizing and self-weight (default: NWC_4000)
- `floor_type`: Floor type (:auto, :one_way, :two_way, :flat_plate, :pt_banded, :vault, etc.)
- `floor_kwargs`: Extra kwargs forwarded to `StructuralSizer.size_floor` (e.g. `(lambda=10.0,)` for vaults)
- `cell_groupings`: Optional explicit slab groupings (vector of cell index vectors)
- `default_Lb_ratio`: Unbraced length ratio for members
"""
function initialize!(struc::BuildingStructure; 
                     material::AbstractMaterial=NWC_4000,
                     floor_type::Symbol=:auto,
                     floor_kwargs::NamedTuple=NamedTuple(),
                     cell_groupings::Union{Nothing, Vector{Vector{Int}}}=nothing,
                     default_Lb_ratio=1.0)
    skel = struc.skeleton
    
    find_faces!(skel)
    # Slabs: cells → slabs (material only needed for slabs)
    initialize_cells!(struc)
    initialize_slabs!(struc; material=material, floor_type=floor_type, floor_kwargs=floor_kwargs, cell_groupings=cell_groupings)
    # Framing: segments → members
    initialize_segments!(struc; default_Lb_ratio=default_Lb_ratio)
    initialize_members!(struc)
    
    @debug "Initialized BuildingStructure" cells=length(struc.cells) slabs=length(struc.slabs) segments=length(struc.segments) members=length(struc.members)
    return struc
end
