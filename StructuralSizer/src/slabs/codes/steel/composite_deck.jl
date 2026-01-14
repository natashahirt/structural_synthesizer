# Composite Steel Deck Sizing
# Steel deck + concrete fill acting compositely

# TODO: Load Vulcraft/ASC deck span tables
# Key parameters: deck profile, gauge, span, construction load, composite capacity

"""
Select composite deck system for given span and load.

# Arguments
- `span`: Clear span (unshored construction assumed)
- `load`: Superimposed dead + live load
- `material`: Primary material (concrete fill, default: NWC_4000)
- `deck_mat`: Steel material for deck (default: A992_Steel)

# Returns
- `CompositeDeckResult` with deck and fill parameters
"""
function size_floor(::CompositeDeck, span::Real, load::Real;
                    material::Concrete=NWC_4000,
                    deck_mat::Metal=A992_Steel)
    error("CompositeDeck sizing not yet implemented")
end
