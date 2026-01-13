# Mass Timber Joist Floor Sizing
# Glulam or LVL joists with panel/deck topping

# Similar concept to steel joist + deck but with timber

"""
Select mass timber joist floor system.

# Arguments
- `span`: Clear span of joists
- `load`: Total superimposed load
- `spacing`: Joist spacing (default 1.2m / 4')
- `deck_type`: Topping (:plywood, :osb, :nlt, :clt)

# Returns
- `TimberJoistSpec` with joist and deck parameters
"""
function size_floor(::MassTimberJoist, span::Real, load::Real;
                    spacing::Real=1.2,
                    deck_type::Symbol=:plywood)
    # STUB: Replace with glulam/LVL selection tables
    
    # Glulam floor joist: span/15 to span/20
    joist_depth = span / 17.0
    joist_depth = max(0.20, joist_depth)  # minimum 200mm
    
    # Standard glulam widths: 80, 130, 175, 215, 265mm
    joist_width = joist_depth < 0.30 ? 0.130 :
                  joist_depth < 0.45 ? 0.175 : 0.215
    
    # Joist designation (e.g., "GL-130x300")
    joist_size = "GL-$(round(Int, joist_width*1000))x$(round(Int, joist_depth*1000))"
    
    # Deck depths by type
    deck_depths = Dict(
        :plywood => 0.019,  # 3/4"
        :osb => 0.019,
        :nlt => 0.140,      # 2x6 NLT
        :clt => 0.105       # 3-ply CLT
    )
    
    deck_d = get(deck_depths, deck_type, 0.019)
    total_depth = joist_depth + deck_d
    
    # Self-weight
    joist_vol_ratio = joist_width / spacing
    joist_sw = joist_depth * joist_vol_ratio * 5.0  # glulam ~5 kN/m³
    deck_sw = deck_d * 5.5
    self_weight = joist_sw + deck_sw
    
    return TimberJoistSpec(joist_size, joist_depth, spacing, 
                           string(deck_type), total_depth, self_weight)
end

# Unitful overload
function size_floor(st::MassTimberJoist, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
