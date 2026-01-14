# ACI 318-19 Minimum Slab Thickness
# Tables 7.3.1.1 (one-way) and 8.3.1.1 (two-way)

# =============================================================================
# Table 7.3.1.1 - One-way slabs
# =============================================================================

const ACI_ONE_WAY_DIVISORS = Dict(
    SIMPLE => 20.0,
    ONE_END_CONT => 24.0,
    BOTH_ENDS_CONT => 28.0,
    CANTILEVER => 10.0
)

# Yield strength modification factor per ACI 7.3.1.1.1 (one-way only)
fy_factor_one_way(fy_ksi::Real) = 0.4 + fy_ksi / 100.0

"""
ACI 318-19 Table 7.3.1.1: One-way slab minimum thickness.
For solid one-way slabs of normal-weight concrete.
"""
function min_thickness(::OneWay, span::Real, mat::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy_ksi::Real=60.0)
    divisor = get(ACI_ONE_WAY_DIVISORS, support, 28.0)
    h = span * fy_factor_one_way(fy_ksi) / divisor
    return max(MIN_SLAB_THICKNESS, h)
end

# =============================================================================
# Table 8.3.1.1 - Two-way slabs without interior beams
# =============================================================================
# Structure: [fy_ksi][panel_type][drop_panels] => divisor
# Panel types: :interior, :exterior_with_beam, :exterior_no_beam

const ACI_TWO_WAY_TABLE = Dict(
    # Without drop panels
    40 => Dict(
        :interior => 36, :exterior_with_beam => 36, :exterior_no_beam => 33
    ),
    60 => Dict(
        :interior => 33, :exterior_with_beam => 33, :exterior_no_beam => 30
    ),
    80 => Dict(
        :interior => 30, :exterior_with_beam => 30, :exterior_no_beam => 27
    )
)

const ACI_TWO_WAY_DROP_TABLE = Dict(
    # With drop panels
    40 => Dict(
        :interior => 40, :exterior_with_beam => 40, :exterior_no_beam => 36
    ),
    60 => Dict(
        :interior => 36, :exterior_with_beam => 36, :exterior_no_beam => 33
    ),
    80 => Dict(
        :interior => 33, :exterior_with_beam => 33, :exterior_no_beam => 30
    )
)

# Minimum thicknesses per ACI 8.3.1.1
const MIN_TWO_WAY_NO_DROP = 0.127    # 5 inches in meters
const MIN_TWO_WAY_WITH_DROP = 0.102  # 4 inches in meters

"""Map support condition to panel type for two-way lookup."""
function get_panel_type(support::SupportCondition, has_edge_beam::Bool)
    if support == BOTH_ENDS_CONT
        return :interior
    else
        return has_edge_beam ? :exterior_with_beam : :exterior_no_beam
    end
end

"""Get divisor from two-way table with fy interpolation."""
function get_two_way_divisor(table::Dict, fy_ksi::Real, panel_type::Symbol)
    # Clamp to table bounds
    fy_clamped = clamp(fy_ksi, 40.0, 80.0)
    
    if fy_clamped in keys(table)
        return Float64(table[Int(fy_clamped)][panel_type])
    end
    
    # Linear interpolation between table values
    if fy_clamped < 60.0
        d40 = table[40][panel_type]
        d60 = table[60][panel_type]
        t = (fy_clamped - 40.0) / 20.0
        return d40 + t * (d60 - d40)
    else
        d60 = table[60][panel_type]
        d80 = table[80][panel_type]
        t = (fy_clamped - 60.0) / 20.0
        return d60 + t * (d80 - d60)
    end
end

"""
ACI 318-19 Table 8.3.1.1: Two-way slab minimum thickness.
Uses longer clear span ln.
"""
function min_thickness(::TwoWay, span_long::Real, mat::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy_ksi::Real=60.0,
                       has_edge_beam::Bool=false)
    panel_type = get_panel_type(support, has_edge_beam)
    divisor = get_two_way_divisor(ACI_TWO_WAY_TABLE, fy_ksi, panel_type)
    h = span_long / divisor
    return max(MIN_TWO_WAY_NO_DROP, h)
end

"""
ACI 318-19 Table 8.3.1.1: Flat plate (two-way, no drop panels).
"""
function min_thickness(::FlatPlate, span_long::Real, mat::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy_ksi::Real=60.0,
                       has_edge_beam::Bool=false)
    panel_type = get_panel_type(support, has_edge_beam)
    divisor = get_two_way_divisor(ACI_TWO_WAY_TABLE, fy_ksi, panel_type)
    h = span_long / divisor
    return max(MIN_TWO_WAY_NO_DROP, h)
end

"""
ACI 318-19 Table 8.3.1.1: Flat slab (two-way with drop panels).
"""
function min_thickness(::FlatSlab, span_long::Real, mat::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy_ksi::Real=60.0,
                       has_edge_beam::Bool=false)
    panel_type = get_panel_type(support, has_edge_beam)
    divisor = get_two_way_divisor(ACI_TWO_WAY_DROP_TABLE, fy_ksi, panel_type)
    h = span_long / divisor
    return max(MIN_TWO_WAY_WITH_DROP, h)
end

"""
PT slab minimum thickness per ACI 318-19 Section 8.6.2.2.
Post-tensioned slabs: ln/45 for spans ≤ 35 ft, larger for longer spans.
"""
function min_thickness(::PTBanded, span_long::Real, mat::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       has_drop_panels::Bool=false)
    divisor = has_drop_panels ? 50.0 : 45.0
    h = span_long / divisor
    min_h = has_drop_panels ? MIN_TWO_WAY_WITH_DROP : MIN_TWO_WAY_NO_DROP
    return max(min_h, h)
end

"""
Waffle slab minimum thickness.
ACI treats as two-way joist system; use interior panel values.
"""
function min_thickness(::Waffle, span_long::Real, mat::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT,
                       fy_ksi::Real=60.0)
    divisor = get_two_way_divisor(ACI_TWO_WAY_TABLE, fy_ksi, :interior)
    h = span_long / divisor
    return max(MIN_TWO_WAY_NO_DROP, h)
end

# =============================================================================
# size_floor implementation (unified public API)
# =============================================================================

# Union type for all CIP concrete slabs (excludes HollowCore, Vault, ShapedSlab)
const CIPSlabType = Union{OneWay, TwoWay, FlatPlate, FlatSlab, PTBanded, Waffle}

"""
Size CIP concrete slab. Returns CIPSlabResult with thickness and self-weight.

Note: `load` is accepted for interface consistency but not used for thickness
calculation. ACI 318-19 minimum thickness tables are span-governed, not load-governed.
Future: may be used for deflection checks under heavy loads.
"""
function size_floor(st::CIPSlabType, span::Real, load::Real; 
                    material::Concrete=NWC_4000, kwargs...)
    h = min_thickness(st, span, material; kwargs...)
    sw = h * ustrip(material.ρ) * 9.81 / 1000  # kN/m²
    return CIPSlabResult(h, sw)
end
