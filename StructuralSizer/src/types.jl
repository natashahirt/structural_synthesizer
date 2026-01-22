# Metal type tags for dispatch
abstract type MetalType end
struct StructuralSteelType <: MetalType end
struct RebarType <: MetalType end

struct Metal{K<:MetalType, T_P, T_D} <: AbstractMaterial
    E::T_P      # Young's modulus
    G::T_P      # Shear modulus
    Fy::T_P     # Yield strength
    Fu::T_P     # Ultimate strength
    ρ::T_D      # Density
    ν::Float64  # Poisson's ratio
    ecc::Float64  # Embodied carbon [kgCO₂e/kg]
end

# Type aliases for dispatch
const StructuralSteel{T_P, T_D} = Metal{StructuralSteelType, T_P, T_D}
const RebarSteel{T_P, T_D} = Metal{RebarType, T_P, T_D}

# Constructors
StructuralSteel(E, G, Fy, Fu, ρ, ν, ecc) = Metal{StructuralSteelType, typeof(E), typeof(ρ)}(E, G, Fy, Fu, ρ, Float64(ν), Float64(ecc))
RebarSteel(E, G, Fy, Fu, ρ, ν, ecc) = Metal{RebarType, typeof(E), typeof(ρ)}(E, G, Fy, Fu, ρ, Float64(ν), Float64(ecc))

struct Concrete{T_P, T_D} <: AbstractMaterial
    E::T_P      # Young's modulus
    fc′::T_P    # Compressive strength
    ρ::T_D      # Density
    ν::Float64  # Poisson's ratio
    ecc::Float64  # Embodied carbon [kgCO₂e/kg]
end

function Concrete(E, fc′, ρ, ν, ecc)
    Concrete{typeof(E), typeof(ρ)}(E, fc′, ρ, Float64(ν), Float64(ecc))
end
