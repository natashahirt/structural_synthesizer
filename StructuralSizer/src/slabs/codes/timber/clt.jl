# Cross-Laminated Timber (CLT) Panel Sizing
# Catalog-based selection from manufacturer tables

# TODO: Load CLT manufacturer data (Nordic, Structurlam, etc.)
# Key parameters: span, load, fire rating, acoustic requirements
# Common thicknesses: 3-ply (105mm), 5-ply (175mm), 7-ply (245mm), 9-ply (315mm)

"""
Select CLT panel for given span and load.

# Arguments
- `span`: Clear span
- `load`: Superimposed load (factored)
- `fire_rating`: Required fire rating in hours (default 1)

# Returns
- `TimberPanelSection` with panel specification
"""
function size_floor(::CLT, span::Real, load::Real; fire_rating::Int=1)
    # STUB: Replace with catalog lookup
    
    # CLT span/depth ratio typically 25-35 for floors
    depth = span / 30.0
    
    # Round to standard ply configurations
    ply_thickness = 0.035  # ~35mm per ply
    ply_count = max(3, 2 * ceil(Int, depth / (2 * ply_thickness)) + 1)  # odd number
    depth = ply_count * ply_thickness
    
    # Fire rating adjustment (add sacrificial layer)
    char_rate = 0.0007  # ~0.7mm/min for CLT
    fire_depth = fire_rating * 60 * char_rate
    depth = depth + fire_depth
    
    # Panel ID (e.g., "CLT-5-175" = 5-ply, 175mm)
    panel_id = "CLT-$(ply_count)-$(round(Int, depth * 1000))"
    
    # Self-weight: CLT ~5.0 kN/m³
    self_weight = depth * 5.0
    
    return TimberPanelSection(panel_id, depth, ply_count, self_weight)
end

# Unitful overload
function size_floor(st::CLT, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
