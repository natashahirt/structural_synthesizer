# Steel Joist + Roof Deck Sizing
# Open-web steel joists with metal deck

# TODO: Load SJI joist tables (K-series, LH-series, DLH-series)
# Key parameters: span, spacing, total load

"""
Select steel joist and deck system.

# Arguments
- `span`: Clear span of joists
- `load`: Total superimposed load
- `material`: Steel material (default: A992_Steel)
- `spacing`: Joist spacing (default 1.5m / 5')

# Returns
- `JoistDeckResult` with joist and deck parameters
"""
function size_floor(::JoistRoofDeck, span::Real, load::Real;
                    material::Metal=A992_Steel,
                    spacing::Real=1.5)
    error("JoistRoofDeck sizing not yet implemented")
end
