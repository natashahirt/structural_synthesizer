# Hollow Core Precast Slab Sizing
# Catalog-based selection from manufacturer tables

# TODO: Load hollow core catalog data
# Typical depths: 6", 8", 10", 12", 16"
# Key parameters: span, superimposed load, fire rating

"""
Select hollow core profile for given span and load.

# Arguments
- `span`: Clear span length
- `load`: Superimposed dead + live load (factored)
- `fire_rating`: Required fire rating in hours (default 2)

# Returns
- `ProfileSection` with selected profile
"""
function size_floor(::HollowCore, span::Real, load::Real; fire_rating::Int=2)
    # STUB: Replace with catalog lookup
    # Approximate: depth ≈ span/30 for typical loads
    depth = span / 30.0
    depth = clamp(depth, 0.15, 0.40)  # 6" to 16"
    
    profile_id = "HC-$(round(Int, depth * 39.37))"  # e.g., "HC-8"
    self_weight = depth * 14.0  # ~14 kN/m³ for hollow core
    
    return ProfileSection(profile_id, depth, self_weight)
end

# Unitful overload
function size_floor(st::HollowCore, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
