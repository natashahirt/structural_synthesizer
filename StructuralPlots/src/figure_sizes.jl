# ============================================================================
# Figure Size Generators
# Designed for common journal publishing guidelines (e.g., Elsevier)
# ============================================================================

const pts_per_cm = 28.3465

"""
    fullwidth(ratio = 1.0; factor = 2, textwidth = 16.9)

Generate figure dimensions for full-width figures.
- `ratio`: height/width ratio (default 1.0 = square)
- `factor`: resolution multiplier (default 2)
- `textwidth`: text width in cm (default 16.9 for Elsevier)
"""
function fullwidth(ratio = 1.0; factor = 2, textwidth = 16.9)
    x = Int(round(factor * textwidth * pts_per_cm, RoundUp))
    y = Int(round(x * ratio, RoundUp))
    return (x, y)
end

"""
    halfwidth(ratio = 1.0; factor = 2, textwidth = 16.9)

Generate figure dimensions for half-width figures.
- `ratio`: height/width ratio (default 1.0 = square)
- `factor`: resolution multiplier (default 2)
- `textwidth`: text width in cm (default 16.9 for Elsevier)
"""
function halfwidth(ratio = 1.0; factor = 2, textwidth = 16.9)
    x = Int(round(factor * textwidth / 2 * pts_per_cm, RoundUp))
    y = Int(round(x * ratio, RoundUp))
    return (x, y)
end

"""
    customwidth(widthfactor, ratio = 1.0; factor = 2, textwidth = 16.9)

Generate custom figure dimensions.
- `widthfactor`: fraction of textwidth (e.g., 0.75 for 75%)
- `ratio`: height/width ratio (default 1.0 = square)
- `factor`: resolution multiplier (default 2)
- `textwidth`: text width in cm (default 16.9 for Elsevier)
"""
function customwidth(widthfactor, ratio = 1.0; factor = 2, textwidth = 16.9)
    x = Int(round(factor * widthfactor * textwidth * pts_per_cm, RoundUp))
    y = Int(round(x * ratio, RoundUp))
    return (x, y)
end

"""
    thirdwidth(ratio = 1.0; factor = 2, textwidth = 16.9)

Generate figure dimensions for one-third width figures.
"""
function thirdwidth(ratio = 1.0; factor = 2, textwidth = 16.9)
    x = Int(round(factor * textwidth / 3 * pts_per_cm, RoundUp))
    y = Int(round(x * ratio, RoundUp))
    return (x, y)
end

"""
    quarterwidth(ratio = 1.0; factor = 2, textwidth = 16.9)

Generate figure dimensions for quarter width figures.
"""
function quarterwidth(ratio = 1.0; factor = 2, textwidth = 16.9)
    x = Int(round(factor * textwidth / 4 * pts_per_cm, RoundUp))
    y = Int(round(x * ratio, RoundUp))
    return (x, y)
end
