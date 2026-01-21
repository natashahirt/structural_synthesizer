using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))  # Activate root project
Pkg.instantiate()

using Revise
using Unitful
using StructuralBase      # Shared types & constants
using StructuralBase: StructuralUnits  # Custom unit definitions (kip, ksi, psf)
using StructuralSizer     # Member-level sizing (materials)
using StructuralSynthesizer  # Geometry & BIM logic
using Asap

# =============================================================================
# Generate building geometry
# =============================================================================
skel = gen_medium_office(160.0u"ft", 110.0u"ft", 13.0u"ft", 4, 3, 4, irregular=:shift_x, offset=1.0u"m");
struc = BuildingStructure(skel);

# =============================================================================
# Initialize structure with floor options
# =============================================================================
opts = FloorOptions(
    cip=CIPOptions(;
        support=ONE_END_CONT,
        rebar_material=Rebar_60,
        has_edge_beam=false,
        has_drop_panels=false,
    ),
);

initialize!(struc; floor_type=:two_way, floor_kwargs=(options=opts,));

# =============================================================================
# Convert to Asap model with TributaryLoads
# =============================================================================
# This computes tributary polygons and creates TributaryLoad for each cell-edge
to_asap!(struc);

# Summary of tributary loads per cell
println("\n--- Tributary Load Summary ---")
total_trib_loads = 0
for (cell_idx, cell_loads) in struc.cell_tributary_loads
    n_loads = length(cell_loads)
    total_trib_loads += n_loads
    if n_loads > 0
        println("Cell $cell_idx: $n_loads TributaryLoads")
    end
end
println("Total TributaryLoads: $total_trib_loads")

# =============================================================================
# Slab summary
# =============================================================================
println("\n--- Slab Summary ---")
for (i, slab) in enumerate(struc.slabs)
    t = StructuralSynthesizer.thickness(slab)
    println("Slab $i: type=$(slab.floor_type), thickness=$t")
end

# =============================================================================
# Size members with deflection limit
# =============================================================================
size_members_discrete!(struc; deflection_limit=1/360);

println("\n--- Member Groups ---")
for (gid, group) in struc.member_groups
    if !isnothing(group.section)
        println("  $(group.section.name)")
    end
end

# =============================================================================
# Example: Update loads after changing floor conditions
# =============================================================================
# Uncomment to demonstrate load updates:
#
# # Increase live load for a specific cell (e.g., storage area)
# struc.cells[1].live_load = 100.0u"psf"
# update_slab_loads!(struc, 1)
#
# # Or update all slabs after global floor type change
# # update_all_slab_loads!(struc)

# =============================================================================
# Visualize
# =============================================================================
visualize(skel)
visualize(struc, mode=:deflected, color_by=:displacement_global, show_original_geometry=false)
visualize(struc, mode=:deflected, color_by=:tributary, show_original_geometry=false)
visualize_cell_tributaries(struc)