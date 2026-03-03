# =============================================================================
# ACI Concrete Torsion Capacity — Mxy Discount for Wood–Armer
# =============================================================================
#
# Computes the twisting moment that plain concrete can resist via its shear
# capacity, allowing a reduction of |Mxy| before the Wood–Armer transformation.
#
# The formulation follows Parsekian (1996), adapted from the Brazilian NB1
# code to ACI 318 shear provisions.
#
# Physics: A slab element under combined transverse shear V and twisting
# moment Mxy mobilises the same concrete shear capacity.  A circular
# interaction relates the two:
#
#   (V / V_c)² + (Mxy / Mxy_c0)² ≤ 1
#
# where V_c = d · τ_c  is the one-way shear capacity per unit width, and
# Mxy_c0 = h² · τ_c / 3  is the pure-torsion capacity of the section.
#
# Solving for the available torsion capacity at a given shear demand V:
#
#   Mxy_c = √(1 − (V / (d · τ_c))²) · h² · τ_c / 3       — Eq. (3.5)
#
# ACI shear stress capacity (per unit width, no stirrups):
#   τ_c = 2 λ √f'c                                          — ACI 318-11 §11.2.1.1
#
# where λ = lightweight concrete factor (1.0 for NWC).
#
# Application:
#   Mxy_eff = max(0, |Mxy| − Mxy_c)
#
# Reference:
#   Parsekian, G.A. (1996). "Cálculo e armação de lajes de concreto armado
#   com a consideração do momento volvente." M.Sc. dissertation, USP.
#   Adapted to ACI 318-11 §11.2.1.1.
# =============================================================================

"""
    _aci_torsion_shear_stress(fc_Pa, λ) -> Float64

ACI 318-11 §11.2.1.1 one-way concrete shear stress capacity (Pa).

    τ_c = 2 λ √f'c

# Arguments
- `fc_Pa::Float64`: Concrete compressive strength (Pa)
- `λ::Float64`: Lightweight concrete factor (1.0 for NWC)

# Returns
Shear stress capacity in Pa.
"""
@inline function _aci_torsion_shear_stress(fc_Pa::Float64, λ::Float64)::Float64
    return 2.0 * λ * sqrt(fc_Pa)
end

"""
    _aci_concrete_torsion_capacity(Qxz, Qyz, h_m, d_m, fc_Pa, λ) -> Float64

Compute the concrete torsion capacity Mxy_c for a single element.

Uses a circular V–T interaction per Parsekian (1996) Eq. (3.5), adapted
to ACI 318-11 §11.2.1.1 shear provisions.

# Arguments
- `Qxz::Float64`: Transverse shear in x-z plane (N/m, element-local)
- `Qyz::Float64`: Transverse shear in y-z plane (N/m, element-local)
- `h_m::Float64`: Slab total thickness (m)
- `d_m::Float64`: Effective depth (m)
- `fc_Pa::Float64`: f'c (Pa)
- `λ::Float64`: Lightweight concrete factor (1.0 for NWC)

# Returns
Mxy_c in N·m/m (twisting moment intensity the concrete can resist).
Returns 0.0 when the shear demand exhausts the concrete capacity.
"""
function _aci_concrete_torsion_capacity(
    Qxz::Float64, Qyz::Float64,
    h_m::Float64, d_m::Float64,
    fc_Pa::Float64, λ::Float64,
)::Float64
    τ_c = _aci_torsion_shear_stress(fc_Pa, λ)

    # Governing shear demand per unit width (N/m)
    V = max(abs(Qxz), abs(Qyz))

    # Shear utilisation ratio squared: (V / (d · τ_c))²
    Vc = d_m * τ_c
    Vc < 1e-12 && return 0.0   # degenerate section

    tv = (V / Vc)^2

    # If shear exhausts (or exceeds) concrete capacity → no torsion discount
    tv >= 1.0 && return 0.0

    # Parsekian Eq. (3.5): Mxy_c = √(1 − tv) · h² · τ_c / 3
    return sqrt(1.0 - tv) * h_m^2 * τ_c / 3.0
end

"""
    _apply_torsion_discount(Mxy, Mxy_c) -> Float64

Reduce the twisting moment by the concrete torsion capacity.

    Mxy_eff = sign(Mxy) · max(0, |Mxy| − Mxy_c)

Preserves the sign of Mxy so that the Wood–Armer transformation sees the
correct orientation.
"""
@inline function _apply_torsion_discount(Mxy::Float64, Mxy_c::Float64)::Float64
    absMxy = abs(Mxy)
    absMxy <= Mxy_c && return 0.0
    return copysign(absMxy - Mxy_c, Mxy)
end
