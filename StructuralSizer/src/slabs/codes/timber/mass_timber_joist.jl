# Mass Timber Joist Floor Sizing
# Glulam or LVL joists with panel/deck topping

# Similar concept to steel joist + deck but with timber

"""
Select mass timber joist floor system.

# Arguments
- `span`: Clear span of joists
- `load`: Total superimposed load
- `material`: Timber material (placeholder for future timber material types)
- `spacing`: Joist spacing (default 1.2m / 4')
- `deck_type`: Topping (:plywood, :osb, :nlt, :clt)

# Returns
- `TimberJoistResult` with joist and deck parameters
"""
function size_floor(::MassTimberJoist, span::Real, load::Real;
                    material::AbstractMaterial=NWC_4000,  # placeholder until Timber type exists
                    spacing::Real=1.2,
                    deck_type::Symbol=:plywood)
    error("MassTimberJoist sizing not yet implemented")
end
