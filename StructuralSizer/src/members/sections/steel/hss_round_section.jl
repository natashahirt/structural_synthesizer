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

"""
    HSSRoundSection(OD, t; name=nothing, material=nothing, is_preferred=false) -> HSSRoundSection

Construct a round HSS section from outside diameter and wall thickness.
All section properties (A, I, S, Z, J, r) are computed analytically.

# Arguments
- `OD::Length` — outside diameter (in)
- `t::Length`  — design wall thickness (in)
"""
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

"""
    HSSRoundSection(name, OD, ID, t, A, I, S, Z, J, r, is_preferred; material=nothing) -> HSSRoundSection

Construct a round HSS section from AISC database (catalog) values.
Derived geometry (Dm, rm, D_t) is computed; section properties are taken as given.
"""
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

"""Return a shallow copy of the round HSS section."""
function Base.copy(s::HSSRoundSection)
    HSSRoundSection(
        s.name, s.OD, s.t,
        s.ID, s.Dm, s.rm, s.D_t,
        s.material,
        s.A, s.I, s.S, s.Z, s.J, s.r,
        s.is_preferred
    )
end

"""Gross cross-sectional area (in²)."""
section_area(s::HSSRoundSection) = s.A
"""Outside diameter `OD` (in)."""
section_depth(s::HSSRoundSection) = s.OD
"""Outside diameter `OD` (in) — symmetric section, same as depth."""
section_width(s::HSSRoundSection) = s.OD

"""Strong-axis moment of inertia (= `I`, symmetric) (in⁴)."""
Ix(s::HSSRoundSection) = s.I
"""Weak-axis moment of inertia (= `I`, symmetric) (in⁴)."""
Iy(s::HSSRoundSection) = s.I
"""Strong-axis elastic section modulus (= `S`, symmetric) (in³)."""
Sx(s::HSSRoundSection) = s.S
"""Weak-axis elastic section modulus (= `S`, symmetric) (in³)."""
Sy(s::HSSRoundSection) = s.S
"""Strong-axis plastic section modulus (= `Z`, symmetric) (in³)."""
Zx(s::HSSRoundSection) = s.Z
"""Weak-axis plastic section modulus (= `Z`, symmetric) (in³)."""
Zy(s::HSSRoundSection) = s.Z
"""Strong-axis radius of gyration (= `r`, symmetric) (in)."""
rx(s::HSSRoundSection) = s.r
"""Weak-axis radius of gyration (= `r`, symmetric) (in)."""
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

"""Type alias: `PipeSection = HSSRoundSection` for backward compatibility."""
const PipeSection = HSSRoundSection
