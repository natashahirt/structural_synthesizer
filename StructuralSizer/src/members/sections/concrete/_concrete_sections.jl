# ==============================================================================
# Concrete Sections
# ==============================================================================
# Section types for reinforced concrete members.

# Reinforced concrete rectangular beam section
include("rc_beam_section.jl")

# Reinforced concrete T-beam section (monolithic with slab)
include("rc_tbeam_section.jl")

# Reinforced concrete column section (rectangular/square)
include("rc_rect_column_section.jl")

# Reinforced concrete circular column section
include("rc_circular_column_section.jl")

# RC column catalog (standard sizes and presets)
include("catalogs/rc_columns.jl")

# RC beam catalog (standard sizes and presets)
include("catalogs/rc_beams.jl")

# RC T-beam catalog (requires flange geometry from building context)
include("catalogs/rc_tbeams.jl")

# PixelFrame polygon geometry (must come before pixelframe_section.jl)
include("pixelframe_geometry.jl")

# PixelFrame section (FRC + external post-tensioning, Y-shaped polygon)
include("pixelframe_section.jl")

# Note: PixelFrame catalog (catalogs/pixelframe_catalog.jl) is included from
# codes/pixelframe/_pixelframe.jl because it depends on capacity functions.
