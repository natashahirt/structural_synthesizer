# Non-Composite Steel Deck Sizing
# Steel deck only (roof deck, form deck)

"""
Select non-composite deck for given span and load.

# Arguments
- `span`: Clear span
- `load`: Total factored load
- `material`: Steel material (default: A992_Steel)

# Returns
- `ProfileResult` with deck profile
"""
function size_floor(::NonCompositeDeck, span::Real, load::Real;
                    material::Metal=A992_Steel)
    error("NonCompositeDeck sizing not yet implemented")
end
