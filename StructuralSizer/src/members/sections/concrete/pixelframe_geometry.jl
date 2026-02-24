# ==============================================================================
# PixelFrame Polygon Geometry
# ==============================================================================
# Constructs the Y, X2, and X4 cross-section geometries for PixelFrame
# elements using Asap's CompoundSection / SolidSection types.
#
# Ported from external/Pixelframe.jl/src/Geometry/pixelGeo.jl (Keith JL).
#
# Layup types (thesis Fig. 2.1):
#   Y  — 3 arms at 120° intervals (primary & secondary beams)
#   X2 — 2 arms at 180° (two-piece columns, slabs, thin members)
#   X4 — 4 arms at 90°  (four-piece columns, biaxial members)
#
# All inputs in mm (bare Float64) — CompoundSection is unitless.
# ==============================================================================

using LinearAlgebra
using Asap: SolidSection, CompoundSection

# ==============================================================================
# Single arm polygon
# ==============================================================================

"""
    _pixel_arm_points(L, t, Lc; n=10) -> Vector{Vector{Float64}}

Generate the 2D polygon vertices for a single PixelFrame arm.

# Arguments
- `L`: Arm length [mm]
- `t`: Wall thickness [mm]
- `Lc`: Straight region before arc [mm]
- `n`: Arc discretization points (default 10)

# Reference
Ported from `get_pixel_points` in Pixelframe.jl (Keith JL).
"""
function _pixel_arm_points(L::Real, t::Real, Lc::Real; n::Int=10)
    θ = π / 6
    ϕ = π / 3
    psirange = range(0, ϕ, n)

    p1 = [0.0, 0.0]

    # First set: outer edges of the arm
    p2  = p1 .+ [0.0, -L]
    p2′ = p1 .+ L .* [cos(θ), sin(θ)]

    # Second set: inner edges (offset by thickness)
    p3 = p2 .+ [t, 0.0]
    p3′ = p2′ + t .* [cos(ϕ), -sin(ϕ)]

    # Third set: start of arc region
    p4 = p3 .+ [0.0, Lc]
    p4′ = p3′ .+ Lc .* [-cos(θ), -sin(θ)]

    # Arc connecting p4 to p4′
    v4 = p4′ .- p4
    r = norm(v4) / cos(ϕ) / 2
    p5 = p4 .+ [r, 0.0]
    arcs = [p5 .+ r .* [-cos(ang), sin(ang)] for ang in psirange]

    return [p1, p2, p3, arcs..., p3′, p2′]
end

# ==============================================================================
# Rotation helper
# ==============================================================================

"""Rotate a 2D point about the origin by `angle` radians."""
function _rotate_2d(point::AbstractVector{<:Real}, angle::Float64)
    c, s = cos(angle), sin(angle)
    [c * point[1] - s * point[2], s * point[1] + c * point[2]]
end

# ==============================================================================
# Y-section assembly (3 arms at 120°)
# ==============================================================================

"""
    make_pixelframe_Y_section(L, t, Lc; n=10) -> CompoundSection

Build the Y-shaped (3-arm) PixelFrame cross-section as a `CompoundSection`.

Three identical arms are placed at 0°, 120°, and 240° about the origin.

# Arguments
- `L`: Arm length [mm]
- `t`: Wall thickness [mm]
- `Lc`: Straight region before arc [mm]
- `n`: Arc discretization points (default 10)

# Returns
`Asap.CompoundSection` with polygon-computed area, centroid, Ix, Iy, etc.
"""
function make_pixelframe_Y_section(L::Real, t::Real, Lc::Real; n::Int=10)
    arm_pts = _pixel_arm_points(Float64(L), Float64(t), Float64(Lc); n=n)

    right_pixel = arm_pts
    top_pixel   = [_rotate_2d(p, 2π / 3) for p in right_pixel]
    left_pixel  = [_rotate_2d(p, 2π / 3) for p in top_pixel]

    solids = SolidSection.([right_pixel, top_pixel, left_pixel])
    return CompoundSection(solids)
end

# ==============================================================================
# X2-section assembly (2 arms at 180°)
# ==============================================================================

"""
    make_pixelframe_X2_section(L, t, Lc; n=10) -> CompoundSection

Build the X2-shaped (2-arm) PixelFrame cross-section as a `CompoundSection`.

Two identical arms rotated 30° from the base, placed at top and bottom (180° apart).

# Arguments
- `L`: Arm length [mm]
- `t`: Wall thickness [mm]
- `Lc`: Straight region before arc [mm]
- `n`: Arc discretization points (default 10)

# Returns
`Asap.CompoundSection` with polygon-computed area, centroid, Ix, Iy, etc.

# Reference
Ported from `make_X2_layup_section` in Pixelframe.jl (Keith JL).
"""
function make_pixelframe_X2_section(L::Real, t::Real, Lc::Real; n::Int=10)
    arm_pts = _pixel_arm_points(Float64(L), Float64(t), Float64(Lc); n=n)

    # Rotate base arm by π/6 (30°) to align with X-axis
    right_pixel = [_rotate_2d(p, π / 6) for p in arm_pts]

    # Top arm = right rotated 90°
    top_pixel = [_rotate_2d(p, π / 2) for p in right_pixel]

    # Left arm = top rotated 90°
    left_pixel = [_rotate_2d(p, π / 2) for p in top_pixel]

    # Bottom arm = left rotated 90°
    bottom_pixel = [_rotate_2d(p, π / 2) for p in left_pixel]

    # X2 uses only top and bottom (2 of 4 arms)
    solids = SolidSection.([top_pixel, bottom_pixel])
    return CompoundSection(solids)
end

# ==============================================================================
# X4-section assembly (4 arms at 90°)
# ==============================================================================

"""
    make_pixelframe_X4_section(L, t, Lc; n=10) -> CompoundSection

Build the X4-shaped (4-arm) PixelFrame cross-section as a `CompoundSection`.

Four identical arms rotated 30° from the base, placed at 90° intervals,
with a gap offset to prevent overlap.

# Arguments
- `L`: Arm length [mm]
- `t`: Wall thickness [mm]
- `Lc`: Straight region before arc [mm]
- `n`: Arc discretization points (default 10)

# Returns
`Asap.CompoundSection` with polygon-computed area, centroid, Ix, Iy, etc.

# Reference
Ported from `make_X4_layup_section` in Pixelframe.jl (Keith JL).
"""
function make_pixelframe_X4_section(L::Real, t::Real, Lc::Real; n::Int=10)
    arm_pts = _pixel_arm_points(Float64(L), Float64(t), Float64(Lc); n=n)

    # Rotate base arm by π/6 (30°) to align with X-axis
    right_pixel = [_rotate_2d(p, π / 6) for p in arm_pts]

    # Rotate by 90° increments
    top_pixel    = [_rotate_2d(p, π / 2) for p in right_pixel]
    left_pixel   = [_rotate_2d(p, π / 2) for p in top_pixel]
    bottom_pixel = [_rotate_2d(p, π / 2) for p in left_pixel]

    # Compute gap offset: distance between adjacent arm tips
    distance = top_pixel[2][1] - right_pixel[end][1]

    # Apply offsets to separate arms
    right_pixel  = [[p[1] + distance, p[2]] for p in right_pixel]
    top_pixel    = [[p[1], p[2] + distance] for p in top_pixel]
    left_pixel   = [[p[1] - distance, p[2]] for p in left_pixel]
    bottom_pixel = [[p[1], p[2] - distance] for p in bottom_pixel]

    solids = SolidSection.([right_pixel, top_pixel, left_pixel, bottom_pixel])
    return CompoundSection(solids)
end

# ==============================================================================
# Dispatch by layup symbol
# ==============================================================================

"""
    make_pixelframe_section(λ::Symbol, L, t, Lc; n=10) -> CompoundSection

Build a PixelFrame cross-section for the given layup type `λ`.

# Layup types (thesis Fig. 2.1)
- `:Y`  — 3-arm Y-section (primary & secondary beams)
- `:X2` — 2-arm X-section (two-piece columns, slabs)
- `:X4` — 4-arm X-section (four-piece columns, biaxial members)
"""
function make_pixelframe_section(λ::Symbol, L::Real, t::Real, Lc::Real; n::Int=10)
    λ === :Y  && return make_pixelframe_Y_section(L, t, Lc; n)
    λ === :X2 && return make_pixelframe_X2_section(L, t, Lc; n)
    λ === :X4 && return make_pixelframe_X4_section(L, t, Lc; n)
    error("Unknown PixelFrame layup type: $λ. Must be :Y, :X2, or :X4.")
end
