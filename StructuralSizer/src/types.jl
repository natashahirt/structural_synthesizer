struct Metal{T_P, T_D} <: AbstractMaterial
    E::T_P      # Young's modulus
    G::T_P      # Shear modulus
    Fy::T_P     # Yield strength
    Fu::T_P     # Ultimate strength
    ρ::T_D      # Density
    ν::Float64  # Poisson's ratio
    ecc::Float64  # Embodied carbon [kgCO₂e/kg]
end

function Metal(E, G, Fy, Fu, ρ, ν, ecc)
    Metal{typeof(E), typeof(ρ)}(E, G, Fy, Fu, ρ, Float64(ν), Float64(ecc))
end

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
