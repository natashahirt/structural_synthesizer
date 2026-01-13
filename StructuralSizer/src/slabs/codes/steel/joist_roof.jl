# Steel Joist + Roof Deck Sizing
# Open-web steel joists with metal deck

# TODO: Load SJI joist tables (K-series, LH-series, DLH-series)
# Key parameters: span, spacing, total load

"""
Select steel joist and deck system.

# Arguments
- `span`: Clear span of joists
- `load`: Total superimposed load
- `spacing`: Joist spacing (default 1.5m / 5')

# Returns
- `JoistDeckSpec` with joist and deck parameters
"""
function size_floor(::JoistRoofDeck, span::Real, load::Real;
                    spacing::Real=1.5,
                    deck_mat::Metal=A992_Steel)
    # STUB: Replace with SJI table lookup
    
    # K-series depth approximation: span/20 to span/24
    joist_depth = span / 22.0
    joist_depth = clamp(joist_depth, 0.25, 0.75)  # 10" to 30"
    
    # Joist designation (e.g., "16K3" = 16" K-series, type 3)
    depth_in = round(Int, joist_depth * 39.37)
    joist_id = "$(depth_in)K5"  # simplified
    
    # Roof deck (typically 1.5" Type B)
    deck_profile = "1.5B22"
    deck_depth = 0.038
    
    total_depth = joist_depth + deck_depth
    
    # Self-weight: joist (~0.15-0.30 kN/m²) + deck (~0.10 kN/m²)
    joist_sw = 0.20 + joist_depth * 0.5  # rough
    deck_sw = 0.10
    self_weight = joist_sw + deck_sw
    
    return JoistDeckSpec(joist_id, joist_depth, spacing, deck_profile, 
                         deck_depth, total_depth, self_weight)
end

# Unitful overload
function size_floor(st::JoistRoofDeck, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
