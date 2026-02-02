# ==============================================================================
# Section Interface
# ==============================================================================
# Generic functions for each AbstractSection subtype.

"""Cross-sectional area."""
function area end

"""Total section depth."""
function depth end

"""Section width."""
function width end

"""Weight per unit length. Default: section_area(s) * mat.ρ"""
weight_per_length(s::AbstractSection, mat::AbstractMaterial) = section_area(s) * mat.ρ

# ==============================================================================
# Material-Organized Sections
# ==============================================================================

# Steel sections (I-shapes, HSS, angles, etc.)
include("steel/_steel_sections.jl")

# Rebar (used across steel and concrete)
include("steel/rebar.jl")

# Timber sections (glulam, LVL, sawn lumber, etc.)
include("timber/_timber_sections.jl")

# Concrete sections (RC beams, columns, etc.)
include("concrete/_concrete_sections.jl")

# Asap.Section conversion (requires all section types to be defined)
include("to_asap_section.jl")