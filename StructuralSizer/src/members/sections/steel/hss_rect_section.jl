# ==============================================================================
# Rectangular/Square HSS Sections
# ==============================================================================

using StructuralBase.StructuralUnits: Length, Area, Volume, Inertia

const LengthQ_HSS = Length
const AreaQ_HSS   = Area
const ModQ_HSS    = Volume   # Section modulus has L³ dimension
const InertQ_HSS  = Inertia  # Moment of inertia L⁴

"""
    HSSRectSection <: AbstractRectHollowSection

Rectangular or square HSS section with computed geometric properties.

# Geometric Properties (AISC 360-16)
- `H`: Outside height (depth)
- `B`: Outside width
- `t`: Design wall thickness
- `h`: Clear web height = H - 3t (AISC convention)
- `b`: Clear flange width = B - 3t (AISC convention)
- `λ_f`: Flange slenderness = b/t
- `λ_w`: Web slenderness = h/t

# Section Properties
- `A`: Cross-sectional area
- `Ix, Iy`: Moments of inertia
- `Sx, Sy`: Elastic section moduli
- `Zx, Zy`: Plastic section moduli
- `J`: Torsional constant
- `rx, ry`: Radii of gyration
"""
mutable struct HSSRectSection <: AbstractRectHollowSection
    name::Union{String, Nothing}
    
    # Input geometry
    H::LengthQ_HSS      # Outside height
    B::LengthQ_HSS      # Outside width
    t::LengthQ_HSS      # Design wall thickness
    
    # Derived geometry (AISC convention: clear dimensions use 3t)
    h::LengthQ_HSS      # Clear web height = H - 3t
    b::LengthQ_HSS      # Clear flange width = B - 3t
    λ_f::Float64        # Flange slenderness b/t
    λ_w::Float64        # Web slenderness h/t
    H_t::Float64        # H/t ratio (for compact checks)
    B_t::Float64        # B/t ratio (for compact checks)
    
    # Material
    material::Union{Metal, Nothing}
    
    # Section properties
    A::AreaQ_HSS
    Ix::InertQ_HSS
    Iy::InertQ_HSS
    Sx::ModQ_HSS
    Sy::ModQ_HSS
    Zx::ModQ_HSS
    Zy::ModQ_HSS
    J::InertQ_HSS
    rx::LengthQ_HSS
    ry::LengthQ_HSS
    
    # AISC preferred (bolded) section flag
    is_preferred::Bool
end

# Constructor from basic dimensions (computes all properties)
function HSSRectSection(H, B, t; name=nothing, material=nothing, is_preferred=false)
    props = compute_hss_rect_properties(H, B, t)
    HSSRectSection(
        name, H, B, t,
        props.h, props.b, props.λ_f, props.λ_w, props.H_t, props.B_t,
        material,
        props.A, props.Ix, props.Iy, props.Sx, props.Sy, props.Zx, props.Zy, props.J, props.rx, props.ry,
        is_preferred
    )
end

# Constructor from catalog (with database values)
function HSSRectSection(name, H, B, t, A, Ix, Iy, Sx, Sy, Zx, Zy, J, rx, ry, is_preferred; material=nothing)
    # Compute derived geometry
    h = H - 3t
    b = B - 3t
    λ_f = ustrip(b / t)
    λ_w = ustrip(h / t)
    H_t = ustrip(H / t)
    B_t = ustrip(B / t)
    
    HSSRectSection(
        name, H, B, t,
        h, b, λ_f, λ_w, H_t, B_t,
        material,
        A, Ix, Iy, Sx, Sy, Zx, Zy, J, rx, ry,
        is_preferred
    )
end

function Base.copy(s::HSSRectSection)
    HSSRectSection(
        s.name, s.H, s.B, s.t,
        s.h, s.b, s.λ_f, s.λ_w, s.H_t, s.B_t,
        s.material,
        s.A, s.Ix, s.Iy, s.Sx, s.Sy, s.Zx, s.Zy, s.J, s.rx, s.ry,
        s.is_preferred
    )
end

# --- Section interface ---
area(s::HSSRectSection) = s.A
depth(s::HSSRectSection) = s.H
width(s::HSSRectSection) = s.B

# --- Geometry computation ---

"""Compute all geometric and section properties for rectangular HSS."""
function compute_hss_rect_properties(H, B, t)
    # Derived geometry (AISC uses 3t for clear dimensions)
    h = H - 3t
    b = B - 3t
    λ_f = ustrip(b / t)
    λ_w = ustrip(h / t)
    H_t = ustrip(H / t)
    B_t = ustrip(B / t)
    
    # Cross-sectional area (exact for rectangular tube)
    A = 2 * (H * t + B * t) - 4 * t^2  # = 2*H*t + 2*B*t - 4*t² (corners counted twice)
    
    # Simplified: A ≈ 2*t*(H + B - 2t) for thin walls
    # Using more accurate formula:
    A = 2 * t * (H + B - 2t)
    
    # Moments of inertia (approximate for thin-walled tube)
    # Ix about strong axis (horizontal), Iy about weak axis (vertical)
    # For rectangular tube with uniform thickness:
    Ix = (B * H^3 - (B - 2t) * (H - 2t)^3) / 12
    Iy = (H * B^3 - (H - 2t) * (B - 2t)^3) / 12
    
    # Section moduli
    Sx = Ix / (H / 2)
    Sy = Iy / (B / 2)
    
    # Plastic section moduli (approximate)
    # For thin-walled rectangular tube:
    Zx = t * (H - t) * (B - t) + t * (H - 2t)^2 / 2
    Zy = t * (B - t) * (H - t) + t * (B - 2t)^2 / 2
    
    # Simplified plastic moduli (commonly used approximation):
    Zx = (B * H^2 - (B - 2t) * (H - 2t)^2) / 4
    Zy = (H * B^2 - (H - 2t) * (B - 2t)^2) / 4
    
    # Torsional constant (thin-walled approximation)
    # J = 2 * t * (H - t)² * (B - t)² / (H + B - 2t)
    Am = (H - t) * (B - t)  # Mean enclosed area
    pm = 2 * ((H - t) + (B - t))  # Mean perimeter
    J = 4 * Am^2 * t / pm
    
    # Radii of gyration
    rx = sqrt(Ix / A)
    ry = sqrt(Iy / A)
    
    return (; h, b, λ_f, λ_w, H_t, B_t, A, Ix, Iy, Sx, Sy, Zx, Zy, J, rx, ry)
end

"""Check if HSS is square (H ≈ B)."""
is_square(s::HSSRectSection) = isapprox(ustrip(s.H), ustrip(s.B); rtol=0.01)

"""Get the governing (larger) slenderness for local buckling."""
governing_slenderness(s::HSSRectSection) = max(s.λ_f, s.λ_w)
