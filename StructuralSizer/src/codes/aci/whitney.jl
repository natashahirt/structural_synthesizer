# ==============================================================================
# Whitney Stress Block — Required Reinforcement
# ==============================================================================
#
# Element-agnostic flexural reinforcement calculation per ACI 318.
# Works for any rectangular concrete section: beams, slab strips, walls.
# ==============================================================================

"""
    required_reinforcement(Mu, b, d, fc, fy) -> Area

Required tension steel area from Whitney stress block equilibrium.

Uses the quadratic solution for As from moment equilibrium:
    As = (β₁·f'c·b·d / fy) × (1 - √(1 - 2Rn/(β₁·f'c)))

where Rn = Mu / (φ·b·d²)

# Arguments
- `Mu`: Factored moment demand
- `b`: Section width (or strip width for slabs)
- `d`: Effective depth (h - cover - db/2)
- `fc`: Concrete compressive strength
- `fy`: Steel yield strength

# Returns
Required steel area As (with units)

# Reference
- ACI 318-19 §22.2 (Whitney rectangular stress block)
- Supplementary Document Section 1.7 (Setareh & Darvas derivation)
"""
function required_reinforcement(Mu::Moment, b::Length, d::Length, fc::Pressure, fy::Pressure)
    φ = 0.9  # Tension-controlled section (ACI 21.2.2)

    # Resistance coefficient Rn = Mu/(φ·b·d²) — has units of pressure
    Rn = Mu / (φ * b * d^2)

    # Stress block factor
    β = beta1(fc)

    # Check if section is adequate (ACI limits)
    Rn_max = 0.319 * β * fc  # Approximate limit for tension-controlled
    if Rn > Rn_max
        @warn "Section may not be tension-controlled, Rn=$(ustrip(u"psi", Rn)) psi > Rn_max=$(ustrip(u"psi", Rn_max)) psi"
    end

    # Required steel ratio (from quadratic solution)
    term = 2 * Rn / (β * fc)  # dimensionless
    if term > 1.0
        error("Section inadequate: required Rn exceeds capacity. Increase h or f'c.")
    end

    ρ = (β * fc / fy) * (1 - sqrt(1 - term))  # dimensionless

    # Required area: As = ρ·b·d
    return ρ * b * d
end
