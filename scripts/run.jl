using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))  # Activate root project
Pkg.instantiate()

using Revise
using Unitful
using StructuralBase      # Shared types & constants
using StructuralSizer     # Member-level sizing (materials)
using StructuralSynthesizer  # Geometry & BIM logic
using Asap

Unitful.register(StructuralBase.Constants)

# Generate building geometry
skel = gen_medium_office(160.0u"ft", 110.0u"ft", 13.0u"ft", 4, 3, 4);
struc = BuildingStructure(skel);

# Fully initialize the structure
# Example: explicitly set slab sizing options (recommended)
# - `CIPOptions` controls ACI min-thickness assumptions for CIP slabs
# - pass through StructuralSynthesizer via `floor_kwargs=(options=..., )`
opts = FloorOptions(
    cip=CIPOptions(;
        support=ONE_END_CONT,                 # SIMPLE, ONE_END_CONT, BOTH_ENDS_CONT, CANTILEVER
        rebar_material=Rebar_60,              # e.g. Rebar_40 / Rebar_60 / Rebar_75 / Rebar_80
        has_edge_beam=false,            # affects two-way/flat plate/slab/waffle exterior panels
        has_drop_panels=false,          # affects PTBanded min thickness
    ),
)

initialize!(struc; floor_type=:two_way, floor_kwargs=(options=opts,));
to_asap!(struc);

for (i, slab) in enumerate(struc.slabs)
    println("slab ", i, "  type=", slab.floor_type, "  thickness=", StructuralSynthesizer.thickness(slab))
end

size_members_discrete!(struc);

for (gid, group) in struc.member_groups
    if !isnothing(group.section)
        println(group.section.name)
    end
end

# Visualize
visualize(skel)
visualize(skel, struc.asap_model, mode=:deflected, color_by=:displacement, show_original_geometry=false)
