using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "StructuralSynthesizer"))
Pkg.instantiate() # Ensure all deps are installed for THIS project

using Revise
using Unitful
using StructuralSynthesizer

skel = gen_medium_office(160.0u"ft", 110.0u"ft", 13.0u"ft", 4, 3, 4);
struc = BuildingStructure(skel);
initialize_slabs!(struc)
asap_model = to_asap(struc);

StructuralSynthesizer.visualize(skel)
StructuralSynthesizer.visualize(skel, asap_model)