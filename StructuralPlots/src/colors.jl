# ============================================================================
# Color Palette - 色 (iro)
# ============================================================================

# Primary palette
const sp_powderblue   = colorant"#aeddf5"
const sp_skyblue      = colorant"#70cbfd"
const sp_gold         = colorant"#df7e00"
const sp_magenta      = colorant"#dc267f"
const sp_orange       = colorant"#e04600"
const sp_ceruleanblue = colorant"#00AEEF"
const sp_charcoalgrey = colorant"#3e3e3e"
const sp_irispurple   = colorant"#4c2563"
const sp_darkpurple   = colorant"#130039"
const sp_lilac        = colorant"#A678B5"

# Named palette dictionary for convenience
const 色 = Dict(
    :powderblue   => sp_powderblue,
    :skyblue      => sp_skyblue,
    :gold         => sp_gold,
    :magenta      => sp_magenta,
    :orange       => sp_orange,
    :ceruleanblue => sp_ceruleanblue,
    :charcoalgrey => sp_charcoalgrey,
    :irispurple   => sp_irispurple,
    :darkpurple   => sp_darkpurple,
    :lilac        => sp_lilac,
)

# Neutral tones for light/dark themes
const sp_lightgray  = colorant"#e8e8e8"
const sp_mediumgray = colorant"#a0a0a0"
const sp_darkgray   = colorant"#505050"
const sp_offwhite   = colorant"#f5f5f5"
const sp_nearblack  = colorant"#1a1a1a"

# ============================================================================
# Color Palettes
# ============================================================================

# Harmonic palette - main colors only (no accent colors like gold/orange)
# Good for visualizations where you need multiple distinguishable but cohesive colors
const harmonic = [
    sp_ceruleanblue,
    sp_magenta,
    sp_irispurple,
    sp_lilac,
    sp_skyblue,
    sp_powderblue,
    sp_darkpurple,
]

# ============================================================================
# Color Gradients
# ============================================================================

# Blue-based gradients
const blue2gold     = cgrad([sp_ceruleanblue, :white, sp_gold])
const white2blue    = cgrad([:white, sp_ceruleanblue])
const trans2blue    = cgrad([:transparent, sp_ceruleanblue])
const skyblue2gold  = cgrad([sp_skyblue, sp_gold])

# Purple-based gradients
const purple2gold   = cgrad([sp_irispurple, :white, sp_gold])
const white2purple  = cgrad([:white, sp_irispurple])
const trans2purple  = cgrad([:transparent, sp_darkpurple])
const lilac2gold    = cgrad([sp_lilac, sp_gold])

# Magenta-based gradients
const magenta2gold  = cgrad([sp_magenta, :white, sp_gold])
const white2magenta = cgrad([:white, sp_magenta])
const trans2magenta = cgrad([:transparent, sp_magenta])

# Neutral gradients
const white2black   = cgrad([:white, :black])
const trans2black   = cgrad([:transparent, :black])
const trans2white   = cgrad([:transparent, :white])

# Structural-specific gradients (tension/compression)
const tension_compression = cgrad([sp_ceruleanblue, :white, sp_magenta])
const stress_gradient     = cgrad([sp_skyblue, sp_gold, sp_orange])
