# Section Interface
# Generic functions for each AbstractSection subtype.

"""Cross-sectional area."""
function area end

"""Total section depth."""
function depth end

"""Section width."""
function width end

"""Weight per unit length. Default: area(s) * mat.ρ"""
weight_per_length(s::AbstractSection, mat::AbstractMaterial) = area(s) * mat.ρ

# Section Types
include("i_symm_section.jl")
include("rebar.jl")

# Catalogs
include("catalogs/aisc_w.jl")
