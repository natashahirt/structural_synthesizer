# Top-level initialization for BuildingStructure

"""
Initialize all structural components of a BuildingStructure.

# Arguments
- `slab_material`: Concrete for slab thickness calc (default: NWC_4000)
- `slab_type`: Slab type (:auto, :one_way, :two_way, :flat_plate, :pt_banded, etc.)
- `default_Lb_ratio`: Unbraced length ratio for members
"""
function initialize!(struc::BuildingStructure; 
                     slab_material::AbstractMaterial=NWC_4000,
                     slab_type::Symbol=:auto,
                     default_Lb_ratio=1.0)
    skel = struc.skeleton
    
    find_faces!(skel)
    # Slabs: cells → slabs
    initialize_cells!(struc; material=slab_material)
    initialize_slabs!(struc; material=slab_material, default_slab_type=slab_type)
    # Framing: segments → members
    initialize_segments!(struc; default_Lb_ratio=default_Lb_ratio)
    initialize_members!(struc)
    
    @debug "Initialized BuildingStructure" cells=length(struc.cells) slabs=length(struc.slabs) segments=length(struc.segments) members=length(struc.members)
    return struc
end
