# ACI 318-19 Minimum Slab Thickness
# Tables 7.3.1.1 (one-way) and 8.3.1.1 (two-way)

using StructuralUnits: ksi  # Import ksi directly for precompile-safe use

# =============================================================================
# Table 7.3.1.1 - One-way slabs
# =============================================================================

const ACI_ONE_WAY_DIVISORS = Dict(
    SIMPLE => 20.0,
    ONE_END_CONT => 24.0,
    BOTH_ENDS_CONT => 28.0,
    CANTILEVER => 10.0
)

"""Yield strength modification factor per ACI 7.3.1.1.1."""
fy_factor_one_way(fy) = 0.4 + ustrip(ksi, fy) / 100.0

"""ACI 318-19 Table 7.3.1.1: One-way slab minimum thickness."""
function min_thickness(::OneWay, span, material::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy=Rebar_60.Fy)
    divisor = get(ACI_ONE_WAY_DIVISORS, support, 28.0)
    h = span * fy_factor_one_way(fy) / divisor
    # Ensure thickness uses the same length unit as `span` (avoids unit-mismatch
    # when the minimum thickness governs).
    return uconvert(unit(span), max(5.0u"inch", h))
end

# =============================================================================
# Table 8.3.1.1 - Two-way slabs without interior beams
# =============================================================================

const ACI_TWO_WAY_TABLE = Dict(
    40 => Dict(:interior => 36, :exterior_with_beam => 36, :exterior_no_beam => 33),
    60 => Dict(:interior => 33, :exterior_with_beam => 33, :exterior_no_beam => 30),
    80 => Dict(:interior => 30, :exterior_with_beam => 30, :exterior_no_beam => 27)
)

const ACI_TWO_WAY_DROP_TABLE = Dict(
    40 => Dict(:interior => 40, :exterior_with_beam => 40, :exterior_no_beam => 36),
    60 => Dict(:interior => 36, :exterior_with_beam => 36, :exterior_no_beam => 33),
    80 => Dict(:interior => 33, :exterior_with_beam => 33, :exterior_no_beam => 30)
)

const MIN_TWO_WAY_NO_DROP = 5.0u"inch"
const MIN_TWO_WAY_WITH_DROP = 4.0u"inch"

"""Map support condition to panel type for two-way lookup."""
function get_panel_type(support::SupportCondition, has_edge_beam::Bool)
    support == BOTH_ENDS_CONT ? :interior : 
        (has_edge_beam ? :exterior_with_beam : :exterior_no_beam)
end

"""Get divisor from two-way table with fy interpolation."""
function get_two_way_divisor(table::Dict, fy, panel_type::Symbol)
    fy_ksi = ustrip(ksi, fy)
    fy_clamped = clamp(fy_ksi, 40.0, 80.0)
    
    fy_clamped in keys(table) && return Float64(table[Int(fy_clamped)][panel_type])
    
    if fy_clamped < 60.0
        d40, d60 = table[40][panel_type], table[60][panel_type]
        return d40 + (fy_clamped - 40.0) / 20.0 * (d60 - d40)
    else
        d60, d80 = table[60][panel_type], table[80][panel_type]
        return d60 + (fy_clamped - 60.0) / 20.0 * (d80 - d60)
    end
end

"""ACI 318-19 Table 8.3.1.1: Two-way slab minimum thickness."""
function min_thickness(::TwoWay, span_long, material::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy=Rebar_60.Fy,
                       has_edge_beam::Bool=false)
    panel_type = get_panel_type(support, has_edge_beam)
    divisor = get_two_way_divisor(ACI_TWO_WAY_TABLE, fy, panel_type)
    return uconvert(unit(span_long), max(MIN_TWO_WAY_NO_DROP, span_long / divisor))
end

"""ACI 318-19 Table 8.3.1.1: Flat plate (two-way, no drop panels)."""
function min_thickness(::FlatPlate, span_long, material::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy=Rebar_60.Fy,
                       has_edge_beam::Bool=false)
    panel_type = get_panel_type(support, has_edge_beam)
    divisor = get_two_way_divisor(ACI_TWO_WAY_TABLE, fy, panel_type)
    return uconvert(unit(span_long), max(MIN_TWO_WAY_NO_DROP, span_long / divisor))
end

"""ACI 318-19 Table 8.3.1.1: Flat slab (two-way with drop panels)."""
function min_thickness(::FlatSlab, span_long, material::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy=Rebar_60.Fy,
                       has_edge_beam::Bool=false)
    panel_type = get_panel_type(support, has_edge_beam)
    divisor = get_two_way_divisor(ACI_TWO_WAY_DROP_TABLE, fy, panel_type)
    return uconvert(unit(span_long), max(MIN_TWO_WAY_WITH_DROP, span_long / divisor))
end

"""PT slab minimum thickness per ACI 318-19 Section 8.6.2.2."""
function min_thickness(::PTBanded, span_long, material::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       has_drop_panels::Bool=false)
    divisor = has_drop_panels ? 50.0 : 45.0
    min_h = has_drop_panels ? MIN_TWO_WAY_WITH_DROP : MIN_TWO_WAY_NO_DROP
    return uconvert(unit(span_long), max(min_h, span_long / divisor))
end

"""Waffle slab minimum thickness (ACI two-way joist system)."""
function min_thickness(::Waffle, span_long, material::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy=Rebar_60.Fy)
    divisor = get_two_way_divisor(ACI_TWO_WAY_TABLE, fy, :interior)
    return uconvert(unit(span_long), max(MIN_TWO_WAY_NO_DROP, span_long / divisor))
end

# =============================================================================
# size_floor implementation
# =============================================================================

const CIPSlabType = Union{OneWay, TwoWay, FlatPlate, FlatSlab, PTBanded, Waffle}

"""
Size CIP concrete slab per ACI 318-19 minimum thickness tables.
Returns `CIPSlabResult{L,F}` preserving input unit types.
"""
function size_floor(
    st::CIPSlabType,
    span::L,
    sdl::F,
    live::F;
    material::Concrete=NWC_4000,
    options::FloorOptions=FloorOptions(),
    kwargs...,
) where {L, F}
    cip = options.cip
    fy = cip.rebar_material.Fy

    # Route only the relevant options to each min_thickness implementation.
    h = if st isa OneWay
        min_thickness(st, span, material; support=cip.support, fy=fy)
    elseif st isa PTBanded
        min_thickness(st, span, material; support=cip.support, has_drop_panels=cip.has_drop_panels)
    elseif st isa Waffle
        min_thickness(st, span, material; support=cip.support, fy=fy)
    else
        # TwoWay, FlatPlate, FlatSlab
        min_thickness(st, span, material; support=cip.support, fy=fy, has_edge_beam=cip.has_edge_beam)
    end
    
    # Self-weight: thickness × density × g
    ρ = ustrip(u"kg/m^3", material.ρ)
    h_m = ustrip(u"m", h)
    sw = h_m * ρ * 9.81  # N/m² = Pa
    
    # Convert to same unit system as load
    sw_unit = uconvert(unit(sdl), sw * u"Pa")
    # Keep `thickness` and `volume_per_area` in the same length unit/type.
    return CIPSlabResult(h, h, sw_unit)
end
