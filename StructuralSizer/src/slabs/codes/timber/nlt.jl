# Nail-Laminated Timber (NLT) Panel Sizing
# Traditional nail-lam decking (2x lumber nailed together)

# NLT is often site-built from standard dimension lumber

"""
Select NLT panel for given span and load.

# Arguments
- `span`: Clear span (typically shorter than CLT/DLT)
- `load`: Superimposed load
- `lumber_size`: Lumber nominal size (:2x6, :2x8, :2x10, :2x12)

# Returns
- `TimberPanelSection` with panel specification
"""
function size_floor(::NLT, span::Real, load::Real; 
                    lumber_size::Symbol=:auto,
                    fire_rating::Int=1)
    # STUB: Replace with engineering calculation
    
    # Standard lumber depths (actual dimensions)
    lumber_depths = Dict(
        :lumber_2x6 => 0.140,   # 5.5"
        :lumber_2x8 => 0.184,   # 7.25"
        :lumber_2x10 => 0.235,  # 9.25"
        :lumber_2x12 => 0.286   # 11.25"
    )

    if lumber_size == :auto
        # Select based on span (NLT typically shorter spans)
        depth_needed = span / 20.0
        if depth_needed < 0.15
            lumber_size = :lumber_2x6
        elseif depth_needed < 0.19
            lumber_size = :lumber_2x8
        elseif depth_needed < 0.24
            lumber_size = :lumber_2x10
        else
            lumber_size = :lumber_2x12
        end
    end


    depth = get(lumber_depths, lumber_size, 0.184)
    
    # Fire adjustment
    char_rate = 0.0007
    fire_depth = fire_rating * 60 * char_rate
    # NLT char is from bottom only typically
    
    panel_id = "NLT-$(lumber_size)"
    ply_count = 1  # single layer of lumber
    self_weight = depth * 5.0
    
    return TimberPanelSection(panel_id, depth, ply_count, self_weight)
end

# Unitful overload
function size_floor(st::NLT, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
