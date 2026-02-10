# Embodied Carbon (EC) calculation utilities
#
# EC = Σ(volume × density × embodied_carbon_coefficient) for each material

"""
    element_ec(volumes::MaterialVolumes) -> Float64

Compute total embodied carbon (kgCO₂e) for an element from its material volumes dict.

## Example
```julia
slab_ec = element_ec(slab.volumes)  # → kgCO₂e
```
"""
function element_ec(volumes::MaterialVolumes)
    sum(
        ustrip(u"kg", vol * mat.ρ) * mat.ecc 
        for (mat, vol) in volumes;
        init=0.0
    )
end

"""
    ElementECResult

Breakdown of EC for a single element.
"""
struct ElementECResult
    element_type::Symbol       # :slab, :member, :foundation
    element_id::Int
    ec::Float64               # Total kgCO₂e
    volume_total::VolumeType  # Total volume
    mass_total::typeof(1.0u"kg")
end

"""
    compute_element_ec(elem, element_type::Symbol, idx::Int) -> ElementECResult

Compute EC for a single element (slab, member, or foundation).
"""
function compute_element_ec(elem, element_type::Symbol, idx::Int)
    vols = elem.volumes
    ec = element_ec(vols)
    vol_total = sum(values(vols); init=0.0u"m^3")
    mass_total = sum(vol * mat.ρ for (mat, vol) in vols; init=0.0u"kg")
    ElementECResult(element_type, idx, ec, vol_total, mass_total)
end

"""
    BuildingECResult

Complete EC breakdown for a building structure.
"""
struct BuildingECResult
    # Per-element breakdowns
    slabs::Vector{ElementECResult}
    members::Vector{ElementECResult}
    foundations::Vector{ElementECResult}
    # Totals by system
    slab_ec::Float64
    member_ec::Float64
    foundation_ec::Float64
    total_ec::Float64
    # Intensity metrics
    floor_area::typeof(1.0u"m^2")
    ec_per_floor_area::Float64  # kgCO₂e/m²
end

"""
    compute_building_ec(struc::BuildingStructure) -> BuildingECResult

Compute complete embodied carbon breakdown for a building structure.

## Returns
Named tuple with:
- `slabs`, `members`, `foundations`: Per-element EC breakdowns
- `slab_ec`, `member_ec`, `foundation_ec`: Total EC by system (kgCO₂e)
- `total_ec`: Grand total EC (kgCO₂e)
- `floor_area`: Total floor area
- `ec_per_floor_area`: EC intensity (kgCO₂e/m²)

## Example
```julia
ec = compute_building_ec(struc)
println("Total EC: \$(ec.total_ec) kgCO₂e")
println("Intensity: \$(ec.ec_per_floor_area) kgCO₂e/m²")
```
"""
function compute_building_ec(struc::BuildingStructure)
    # Compute per-element EC
    slab_results = [compute_element_ec(s, :slab, i) for (i, s) in enumerate(struc.slabs)]
    
    # Compute member EC for all member types (beams, columns, struts)
    member_results = ElementECResult[]
    for (i, m) in enumerate(struc.beams)
        !isempty(volumes(m)) && push!(member_results, compute_element_ec_member(m, :beam, i))
    end
    for (i, m) in enumerate(struc.columns)
        !isempty(volumes(m)) && push!(member_results, compute_element_ec_member(m, :column, i))
    end
    for (i, m) in enumerate(struc.struts)
        !isempty(volumes(m)) && push!(member_results, compute_element_ec_member(m, :strut, i))
    end
    
    fdn_results = [compute_element_ec(f, :foundation, i) for (i, f) in enumerate(struc.foundations) if !isempty(f.volumes)]
    
    # Sum by system
    slab_ec = sum(r.ec for r in slab_results; init=0.0)
    member_ec = sum(r.ec for r in member_results; init=0.0)
    fdn_ec = sum(r.ec for r in fdn_results; init=0.0)
    total_ec = slab_ec + member_ec + fdn_ec
    
    # Floor area (sum of cell areas)
    floor_area = sum(c.area for c in struc.cells; init=0.0u"m^2")
    ec_intensity = floor_area > 0.0u"m^2" ? total_ec / ustrip(u"m^2", floor_area) : 0.0
    
    BuildingECResult(
        slab_results, member_results, fdn_results,
        slab_ec, member_ec, fdn_ec, total_ec,
        floor_area, ec_intensity
    )
end

"""Compute EC for a member (uses volumes accessor)."""
function compute_element_ec_member(m::AbstractMember, element_type::Symbol, idx::Int)
    vols = volumes(m)
    ec = element_ec(vols)
    vol_total = sum(values(vols); init=0.0u"m^3")
    mass_total = sum(vol * mat.ρ for (mat, vol) in vols; init=0.0u"kg")
    ElementECResult(element_type, idx, ec, vol_total, mass_total)
end

"""
    ec_summary(design::BuildingDesign)
    ec_summary(struc::BuildingStructure; du=imperial)

Print a summary of embodied carbon for a building structure.
Display units controlled by `du` (default: `imperial`).
"""
function ec_summary(design::BuildingDesign)
    ec_summary(design.structure; du=design.params.display_units)
end

function ec_summary(struc::BuildingStructure; du::DisplayUnits=imperial)
    ec = compute_building_ec(struc)
    
    println("\n=== Embodied Carbon Summary ===")
    println("─" ^ 50)
    
    # System breakdown
    println("System Breakdown:")
    Printf.@printf("  Slabs:       %10.1f kgCO₂e  (%4.1f%%)\n", ec.slab_ec, 100*ec.slab_ec/ec.total_ec)
    Printf.@printf("  Members:     %10.1f kgCO₂e  (%4.1f%%)\n", ec.member_ec, 100*ec.member_ec/ec.total_ec)
    Printf.@printf("  Foundations: %10.1f kgCO₂e  (%4.1f%%)\n", ec.foundation_ec, 100*ec.foundation_ec/ec.total_ec)
    println("─" ^ 50)
    Printf.@printf("  TOTAL:       %10.1f kgCO₂e\n", ec.total_ec)
    println()
    
    # Intensity
    Printf.@printf("Floor Area:    %10.1f %s\n", ustrip(du.units[:area], ec.floor_area), du.units[:area])
    Printf.@printf("EC Intensity:  %10.1f kgCO₂e/m²\n", ec.ec_per_floor_area)
    
    return ec
end
