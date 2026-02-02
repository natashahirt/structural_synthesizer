# =============================================================================
# Material Type Definitions
# =============================================================================
#
# All material types that inherit from AbstractMaterial (defined in types.jl).
# Presets (specific material instances) are in separate files:
#   - steel.jl    → A992_Steel, S355_Steel, Rebar_*
#   - concrete.jl → NWC_4000, NWC_6000, etc.
#   - timber.jl   → (future presets)
#
# =============================================================================

# =============================================================================
# Metal (Steel)
# =============================================================================

# Type tags for dispatch (structural steel vs rebar)
abstract type MetalType end
struct StructuralSteelType <: MetalType end
struct RebarType <: MetalType end

"""
    Metal{K<:MetalType, T_P, T_D} <: AbstractMaterial

Parametric metal type supporting different steel categories via type tags.

# Type Parameters
- `K`: MetalType tag (StructuralSteelType or RebarType)
- `T_P`: Pressure unit type (e.g., typeof(1.0u"GPa"))
- `T_D`: Density unit type (e.g., typeof(1.0u"kg/m^3"))

# Fields
- `E`: Young's modulus
- `G`: Shear modulus
- `Fy`: Yield strength
- `Fu`: Ultimate strength
- `ρ`: Density
- `ν`: Poisson's ratio
- `ecc`: Embodied carbon [kgCO₂e/kg]
"""
struct Metal{K<:MetalType, T_P, T_D} <: AbstractMaterial
    E::T_P      # Young's modulus
    G::T_P      # Shear modulus
    Fy::T_P     # Yield strength
    Fu::T_P     # Ultimate strength
    ρ::T_D      # Density
    ν::Float64  # Poisson's ratio
    ecc::Float64  # Embodied carbon [kgCO₂e/kg]
end

# Type aliases for convenience
const StructuralSteel{T_P, T_D} = Metal{StructuralSteelType, T_P, T_D}
const RebarSteel{T_P, T_D} = Metal{RebarType, T_P, T_D}

# Constructors
StructuralSteel(E, G, Fy, Fu, ρ, ν, ecc) = Metal{StructuralSteelType, typeof(E), typeof(ρ)}(E, G, Fy, Fu, ρ, Float64(ν), Float64(ecc))
RebarSteel(E, G, Fy, Fu, ρ, ν, ecc) = Metal{RebarType, typeof(E), typeof(ρ)}(E, G, Fy, Fu, ρ, Float64(ν), Float64(ecc))

# =============================================================================
# Concrete
# =============================================================================

"""
    Concrete{T_P, T_D} <: AbstractMaterial

Concrete material with compressive strength.

# Fields
- `E`: Young's modulus
- `fc′`: Compressive strength (28-day)
- `ρ`: Density
- `ν`: Poisson's ratio
- `εcu`: Ultimate compressive strain (default 0.003 per ACI 318)
- `ecc`: Embodied carbon [kgCO₂e/kg]

# Notes
- `εcu = 0.003` is the standard ACI 318 value for concrete up to ~10 ksi
- High-strength concrete (>10 ksi) may use lower values (e.g., 0.0025)
"""
struct Concrete{T_P, T_D} <: AbstractMaterial
    E::T_P        # Young's modulus
    fc′::T_P      # Compressive strength
    ρ::T_D        # Density
    ν::Float64    # Poisson's ratio
    εcu::Float64  # Ultimate compressive strain
    ecc::Float64  # Embodied carbon [kgCO₂e/kg]
end

function Concrete(E, fc′, ρ, ν, ecc; εcu::Real = 0.003)
    Concrete{typeof(E), typeof(ρ)}(E, fc′, ρ, Float64(ν), Float64(εcu), Float64(ecc))
end

# =============================================================================
# Reinforced Concrete Material (Concrete + Rebar)
# =============================================================================

"""
    ReinforcedConcreteMaterial <: AbstractMaterial

Combined concrete + reinforcing steel material for RC design.
Links a `Concrete` material with longitudinal and transverse `RebarSteel`.

# Fields
- `concrete`: Concrete material (fc′, E, εcu, etc.)
- `rebar`: RebarSteel for longitudinal reinforcement (Fy, Es)
- `transverse`: RebarSteel for ties/spirals (defaults to same as rebar)

# Example
```julia
# Using presets
rc_mat = ReinforcedConcreteMaterial(NWC_4000, Rebar_60)

# With different transverse steel
rc_mat = ReinforcedConcreteMaterial(NWC_5000, Rebar_75, Rebar_60)

# Access properties
fc = rc_mat.concrete.fc′     # Concrete strength
fy = rc_mat.rebar.Fy         # Rebar yield strength
```
"""
struct ReinforcedConcreteMaterial{C<:Concrete, R<:RebarSteel} <: AbstractMaterial
    concrete::C
    rebar::R
    transverse::R
end

# Convenience constructor (same rebar for longitudinal and transverse)
function ReinforcedConcreteMaterial(concrete::Concrete, rebar::RebarSteel)
    ReinforcedConcreteMaterial(concrete, rebar, rebar)
end

# =============================================================================
# Timber
# =============================================================================

"""
    Timber <: AbstractMaterial

Timber material with NDS reference design values.

# Fields
- `species`: Species identifier (e.g., :douglas_fir, :southern_pine)
- `grade`: Lumber grade (e.g., :select_structural, :no1, :no2)
- `E`: Modulus of elasticity
- `Emin`: Minimum E for stability calculations
- `Fb`: Reference bending stress
- `Ft`: Reference tension stress
- `Fv`: Reference shear stress
- `Fc`: Reference compression parallel to grain
- `Fc_perp`: Reference compression perpendicular to grain
- `ρ`: Density
- `ecc`: Embodied carbon [kgCO₂e/kg]

Note: Reference values are multiplied by adjustment factors (CD, CM, etc.) 
per NDS to get adjusted design values.
"""
struct Timber <: AbstractMaterial
    species::Symbol      # :douglas_fir, :southern_pine, etc.
    grade::Symbol        # :select_structural, :no1, :no2, etc.
    E::Float64           # Modulus of elasticity [Pa]
    Emin::Float64        # Minimum E for stability calculations [Pa]
    Fb::Float64          # Reference bending stress [Pa]
    Ft::Float64          # Reference tension stress [Pa]
    Fv::Float64          # Reference shear stress [Pa]
    Fc::Float64          # Reference compression parallel [Pa]
    Fc_perp::Float64     # Reference compression perpendicular [Pa]
    ρ::Float64           # Density [kg/m³]
    ecc::Float64         # Embodied carbon [kgCO2e/kg]
end
