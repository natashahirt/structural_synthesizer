# Shaped/Custom Slab Sizing
# User provides a sizing function for variable-thickness or complex geometries

# Examples of shaped slabs:
# - Tapered slabs (thicker at supports)
# - Ribbed/coffered slabs with variable depth
# - Sculptural shells
# - Any geometry where thickness isn't constant

"""
Size a custom/shaped slab using user-provided function.

The user's `sizing_fn` should have signature:
    (span_x, span_y, load, material) → ShapedSlabResult

# Arguments
- `slab`: ShapedSlab with user's sizing function
- `span_x`, `span_y`: Panel dimensions
- `load`: Superimposed load
- `material`: Primary material

# Returns
- `ShapedSlabResult` from user's function
"""
function size_floor(slab::ShapedSlab, span_x::Real, span_y::Real, 
                    load::Real, material::AbstractMaterial)
    return slab.sizing_fn(span_x, span_y, load, material)
end

# Unitful overload
function size_floor(slab::ShapedSlab, span_x::Unitful.Length, span_y::Unitful.Length,
                    load, material::AbstractMaterial)
    return slab.sizing_fn(ustrip(u"m", span_x), ustrip(u"m", span_y), load, material)
end

# =============================================================================
# Example shaped slab functions (for reference)
# =============================================================================

"""
Example: Tapered slab (thick at edges, thin at center).

Usage:
    tapered = ShapedSlab(tapered_slab_fn)
    result = size_floor(tapered, 8.0, 8.0, 5.0, NWC_4000)
"""
function tapered_slab_fn(span_x::Real, span_y::Real, load::Real, mat::Concrete)
    # Thick at edges, thin at center
    h_edge = max(span_x, span_y) / 20.0
    h_center = h_edge * 0.6
    
    # Average volume
    avg_thickness = (h_edge + h_center) / 2
    volume_per_area = avg_thickness * 1.05  # ~5% extra for transition
    
    # Thickness function for visualization
    thickness_fn = (x, y) -> begin
        # Distance from center (normalized 0-1)
        dx = abs(x - span_x/2) / (span_x/2)
        dy = abs(y - span_y/2) / (span_y/2)
        d = max(dx, dy)
        return h_center + d * (h_edge - h_center)
    end
    
    self_weight = volume_per_area * ustrip(mat.ρ) * 9.81 / 1000
    
    return ShapedSlabResult(volume_per_area, self_weight, thickness_fn, 
                            Dict(:h_edge => h_edge, :h_center => h_center))
end

"""
Example: Coffered/waffle slab with ribs.

Usage:
    coffered = ShapedSlab(coffered_slab_fn)
    result = size_floor(coffered, 10.0, 10.0, 5.0, NWC_4000)
"""
function coffered_slab_fn(span_x::Real, span_y::Real, load::Real, mat::Concrete;
                          rib_spacing::Real=1.0, rib_width::Real=0.15)
    # Topping slab + ribs
    h_topping = 0.075  # 3" topping
    h_rib = max(span_x, span_y) / 25.0
    
    # Rib volume ratio
    rib_ratio = rib_width / rib_spacing
    rib_vol = rib_ratio * 2 * h_rib  # ribs in both directions (double count at intersections)
    
    volume_per_area = h_topping + rib_vol * 0.9  # ~10% reduction for overlap
    self_weight = volume_per_area * ustrip(mat.ρ) * 9.81 / 1000
    
    return ShapedSlabResult(volume_per_area, self_weight, nothing,
                            Dict(:h_topping => h_topping, :h_rib => h_rib,
                                 :rib_spacing => rib_spacing))
end
