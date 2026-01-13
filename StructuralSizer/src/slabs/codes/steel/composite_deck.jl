# Composite Steel Deck Sizing
# Steel deck + concrete fill acting compositely

# Deck depth options
@enum DeckDepth begin
    DECK_1_5    # 1.5" deck (short spans)
    DECK_2      # 2" deck (medium spans)
    DECK_3      # 3" deck (long spans)
end

# TODO: Load Vulcraft/ASC deck span tables
# Key parameters: deck profile, gauge, span, construction load, composite capacity

"""
Select composite deck system for given span and load.

# Arguments
- `span`: Clear span (unshored construction assumed)
- `load`: Superimposed dead + live load
- `deck_mat`: Steel material for deck
- `fill_mat`: Concrete material for fill

# Returns
- `CompositeDeckSpec` with deck and fill parameters
"""
function size_floor(::CompositeDeck, span::Real, load::Real;
                    deck_mat::Metal=A992_Steel,
                    fill_mat::Concrete=NWC_4000)
    # STUB: Replace with catalog lookup
    
    # Select deck depth based on span (simplified)
    deck_depth = span < 2.5 ? 0.038 :  # 1.5"
                 span < 3.5 ? 0.051 :  # 2"
                 0.076                  # 3"
    
    # Gauge selection (simplified - heavier for longer spans)
    gauge = span < 2.0 ? 22 :
            span < 3.0 ? 20 :
            span < 4.0 ? 18 : 16
    
    # Fill depth above deck flutes (typically 2.5" to 4.5" total slab)
    fill_depth = max(0.065, span / 45.0)  # rough approximation
    total_depth = deck_depth + fill_depth
    
    # Deck profile ID (e.g., "2VLI20" = 2" Verco Lock-In 20 gauge)
    deck_id = "$(round(Int, deck_depth * 39.37))VL$(gauge)"
    
    # Self-weight: deck (~0.15 kN/m² for 20ga) + concrete fill
    deck_sw = 0.15  # approximate
    fill_sw = fill_depth * ustrip(fill_mat.ρ) * 9.81 / 1000
    self_weight = deck_sw + fill_sw
    
    return CompositeDeckSpec(deck_id, deck_depth, gauge, fill_depth, 
                             total_depth, self_weight)
end

# Unitful overload
function size_floor(st::CompositeDeck, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
