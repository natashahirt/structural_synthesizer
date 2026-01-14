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
- `material`: Concrete material (default: NWC_4000)
- `fire_rating`: Required fire rating in hours (default 2)

# Returns
- `ProfileResult` with selected profile
"""
function size_floor(::HollowCore, span::Real, load::Real;
                    material::Concrete=NWC_4000,
                    fire_rating::Int=2)
    error("HollowCore sizing not yet implemented")
end
