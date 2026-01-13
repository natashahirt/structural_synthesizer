# Dowel-Laminated Timber (DLT) Panel Sizing
# Hardwood dowels connect softwood laminations (no adhesive)

# TODO: Load DLT manufacturer data (StructureCraft, etc.)
# Typically one-way spanning, similar depths to CLT

"""
Select DLT panel for given span and load.

# Arguments
- `span`: Clear span
- `load`: Superimposed load
- `fire_rating`: Required fire rating in hours

# Returns
- `TimberPanelSection` with panel specification
"""
function size_floor(::DLT, span::Real, load::Real; fire_rating::Int=1)
    # STUB: Replace with catalog lookup
    
    # DLT span/depth similar to CLT (~25-30)
    depth = span / 28.0
    depth = max(0.10, depth)  # minimum 100mm
    
    # DLT typically uses 2x lumber (~38mm)
    lam_thickness = 0.038
    ply_count = max(3, ceil(Int, depth / lam_thickness))
    depth = ply_count * lam_thickness
    
    # Fire adjustment
    char_rate = 0.0007
    fire_depth = fire_rating * 60 * char_rate
    depth = depth + fire_depth
    
    panel_id = "DLT-$(ply_count)-$(round(Int, depth * 1000))"
    self_weight = depth * 5.5  # slightly heavier than CLT
    
    return TimberPanelSection(panel_id, depth, ply_count, self_weight)
end

# Unitful overload
function size_floor(st::DLT, span::Unitful.Length, load; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result
end
