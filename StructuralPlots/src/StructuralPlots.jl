module StructuralPlots

using Reexport
@reexport using GLMakie
using Colors

# ============================================================================
# Colors
# ============================================================================
include("colors.jl")

# Primary colors
export sp_powderblue, sp_skyblue, sp_gold, sp_magenta, sp_orange
export sp_ceruleanblue, sp_charcoalgrey, sp_irispurple, sp_darkpurple, sp_lilac

# Neutral tones
export sp_lightgray, sp_mediumgray, sp_darkgray, sp_offwhite, sp_nearblack

# Color dictionary and palettes
export 色
export harmonic

# Gradients
export blue2gold, white2blue, trans2blue, skyblue2gold
export purple2gold, white2purple, trans2purple, lilac2gold
export magenta2gold, white2magenta, trans2magenta
export white2black, trans2black, trans2white
export tension_compression, stress_gradient

# ============================================================================
# Themes
# ============================================================================
include("themes.jl")
export sp_light
export sp_dark

include("themes_mono.jl")
export sp_light_mono
export sp_dark_mono

# ============================================================================
# Utility Functions
# ============================================================================
include("functions.jl")
export discretize
export labelize!
export labelscale!
export resetlabelscale!
export changefont!
export gridtoggle!
export simplifyspines!
export linkaxes!
export linkproperties!
export mirrorticks!
export alignticks!
export tickstoggle!
export fixlimits!
export getfigsize

# ============================================================================
# Axis Styles
# ============================================================================
include("axis_styles.jl")
export graystyle!
export structurestyle!
export cleanstyle!
export asapstyle!
export blueprintstyle!

# ============================================================================
# Figure Sizes
# ============================================================================
include("figure_sizes.jl")
export fullwidth
export halfwidth
export customwidth
export thirdwidth
export quarterwidth

end # module StructuralPlots
