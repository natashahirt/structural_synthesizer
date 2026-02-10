# ==============================================================================
# Round HSS (Pipe) Sections
# ==============================================================================

using Asap: Length, Area, Volume, SecondMomentOfArea

"""
    HSSRoundSection <: AbstractRoundHollowSection

Round HSS (pipe) section with computed geometric properties.

# Geometric Properties
- `OD`: Outside diameter
- `ID`: Inside diameter = OD - 2t
- `t`: Design wall thickness
- `Dm`: Mean diameter = OD - t
- `rm`: Mean radius = Dm / 2
- `D_t`: D/t ratio (slenderness, AISC uses OD/t)

# Section Properties (symmetric about all axes)
- `A`: Cross-sectional area
- `I`: Moment of inertia (Ix = Iy = I)
- `S`: Elastic section modulus (Sx = Sy = S)
- `Z`: Plastic section modulus (Zx = Zy = Z)
- `J`: Torsional constant (= 2I for round sections)
- `r`: Radius of gyration (rx = ry = r)
"""
mutable struct HSSRoundSection <: AbstractRoundHollowSection
    name::Union{String, Nothing}
    
    # Input geometry
    OD::Length    # Outside diameter
    t::Length     # Design wall thickness
    
    # Derived geometry
    ID::Length    # Inside diameter = OD - 2t
    Dm::Length    # Mean diameter = OD - t
    rm::Length    # Mean radius = Dm / 2
    D_t::Float64         # OD/t ratio (slenderness)
    
    # Material
    material::Union{Metal, Nothing}
    
    # Section properties (symmetric: Ix=Iy, Sx=Sy, Zx=Zy, rx=ry)
    A::Area
    I::SecondMomentOfArea      # = Ix = Iy
    S::Volume        # = Sx = Sy
    Z::Volume        # = Zx = Zy
    J::SecondMomentOfArea      # = 2I for round section
    r::Length     # = rx = ry
    
    # AISC preferred (bolded) section flag
    is_preferred::Bool
end

# Constructor from basic dimensions (computes all properties)
function HSSRoundSection(OD, t; name=nothing, material=nothing, is_preferred=false)
    props = compute_hss_round_properties(OD, t)
    HSSRoundSection(
        name, OD, t,
        props.ID, props.Dm, props.rm, props.D_t,
        material,
        props.A, props.I, props.S, props.Z, props.J, props.r,
        is_preferred
    )
end

# Constructor from catalog (with database values for I, S, Z, J, r)
function HSSRoundSection(name, OD, ID, t, A, I, S, Z, J, r, is_preferred; material=nothing)
    # Compute derived geometry
    Dm = OD - t
    rm = Dm / 2
    D_t = ustrip(OD / t)
    
    HSSRoundSection(
        name, OD, t,
        ID, Dm, rm, D_t,
        material,
        A, I, S, Z, J, r,
        is_preferred
    )
end

function Base.copy(s::HSSRoundSection)
    HSSRoundSection(
        s.name, s.OD, s.t,
        s.ID, s.Dm, s.rm, s.D_t,
        s.material,
        s.A, s.I, s.S, s.Z, s.J, s.r,
        s.is_preferred
    )
end

# --- Section interface ---
section_area(s::HSSRoundSection) = s.A
section_depth(s::HSSRoundSection) = s.OD
section_width(s::HSSRoundSection) = s.OD

# Symmetric properties aliases
Ix(s::HSSRoundSection) = s.I
Iy(s::HSSRoundSection) = s.I
Sx(s::HSSRoundSection) = s.S
Sy(s::HSSRoundSection) = s.S
Zx(s::HSSRoundSection) = s.Z
Zy(s::HSSRoundSection) = s.Z
rx(s::HSSRoundSection) = s.r
ry(s::HSSRoundSection) = s.r

# --- Geometry computation ---

"""Compute all geometric and section properties for round HSS."""
function compute_hss_round_properties(OD, t)
    # Derived geometry
    ID = OD - 2t
    Dm = OD - t      # Mean diameter
    rm = Dm / 2      # Mean radius
    D_t = ustrip(OD / t)
    
    # Cross-sectional area (exact for circular annulus)
    # A = π/4 * (OD² - ID²) = π * Dm * t
    A = π * Dm * t
    
    # Moment of inertia (exact)
    # I = π/64 * (OD⁴ - ID⁴)
    I = π / 64 * (OD^4 - ID^4)
    
    # Elastic section modulus
    S = I / (OD / 2)
    
    # Plastic section modulus (exact for hollow circle)
    # Z = (OD³ - ID³) / 6
    Z = (OD^3 - ID^3) / 6
    
    # Torsional constant (polar moment = 2I for circular section)
    J = 2 * I
    
    # Radius of gyration
    r = sqrt(I / A)
    
    return (; ID, Dm, rm, D_t, A, I, S, Z, J, r)
end

"""Get the D/t slenderness ratio."""
slenderness(s::HSSRoundSection) = s.D_t

# Type alias for backward compatibility (PIPE → HSSRound)
const PipeSection = HSSRoundSection
