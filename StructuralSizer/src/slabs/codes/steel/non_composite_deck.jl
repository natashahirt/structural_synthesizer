# Non-Composite Steel Deck Sizing
# Steel deck only (roof deck, form deck)

"""
Select non-composite deck for given span and load.

# Arguments
- `span`: Clear span
- `load`: Total factored load
- `deck_mat`: Steel material

# Returns
- `ProfileSection` with deck profile
"""
function size_floor(::NonCompositeDeck, span::Real, load::Real;
                    deck_mat::Metal=A992_Steel)
    # STUB: Replace with catalog lookup
    
    # Non-composite deck typically limited to shorter spans
    # Depth selection based on span
    depth = span < 1.5 ? 0.038 :  # 1.5" (Type B)
            span < 2.5 ? 0.051 :  # 2"
            span < 3.5 ? 0.076 :  # 3"
            0.190                  # 7.5" (long span roof)
    
    gauge = span < 2.0 ? 22 : span < 3.0 ? 20 : 18
    
    profile_id = "$(round(Int, depth * 39.37))B$(gauge)"
    self_weight = 0.10 + depth * 5.0  # approximate
    
    return ProfileSection(profile_id, depth, self_weight)
end

# Unitful overload
function size_floor(st::NonCompositeDeck, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
