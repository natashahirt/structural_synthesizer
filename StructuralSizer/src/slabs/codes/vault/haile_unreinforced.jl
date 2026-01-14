# Unreinforced Masonry/Concrete Vault Sizing
# Based on Haile's method for unreinforced thin shell parabolic vaults
#
# Reference: Haile method for three-hinge parabolic arch analysis
#
# Key assumptions:
# - Parabolic intrados geometry
# - Three-hinge arch behavior (momentless under UDL if shape matches pressure line)
# - No tensile capacity (unreinforced)
# - Extrados is intrados shifted vertically by shell thickness
# - Optional ribs modeled as flat-topped extensions above extrados

const GRAVITY = 9.81  # m/s²

# =============================================================================
# Geometry Utilities
# =============================================================================

"""
Calculate arc length of a parabolic vault.

Intrados defined by: y(x) = (4h/s²) * x * (s - x)

Translation of getParabolicArcLength.m
"""
function parabolic_arc_length(span::Real, rise::Real)
    abs(rise) < 1e-9 && return Float64(span)
    
    # dy/dx = 4h/s - 8hx/s²
    dydx(x) = 4rise/span - 8rise*x/span^2
    
    # Arc length integrand: √(1 + (dy/dx)²)
    integrand(x) = sqrt(1 + dydx(x)^2)
    
    L, _ = quadgk(integrand, 0, span)
    return L
end

"""
Intrados height at position x for parabolic vault.
y(x) = (4h/s²) * x * (s - x)
"""
intrados(x, span, rise) = (4rise / span^2) * (span * x - x^2)

"""
Extrados height at position x (intrados + shell thickness).
"""
extrados(x, span, rise, thickness) = intrados(x, span, rise) + thickness

# =============================================================================
# Symmetric Load Analysis (VaultStress.m)
# =============================================================================

"""
Calculate working stress and thrust for symmetric UDL case.

Direct translation of VaultStress.m logic.

# Arguments
- `span`: Span of arch [m]
- `rise`: Rise at crown (intrados) [m]
- `trib_depth`: Tributary depth / rib spacing [m]
- `thickness`: Shell thickness [m]
- `rib_depth`: Rib width in span direction [m] (0 if no ribs)
- `rib_apex_rise`: Additional rib height above extrados at apex [m]
- `density`: Material density [kg/m³]
- `applied_load`: Applied distributed load (live) [kN/m²]
- `finishing_load`: Finishing load (screed, etc.) [kN/m²]

# Returns
Named tuple: (σ_MPa, thrust_kN, self_weight_kN_m², vertical_kN)
"""
function vault_stress_symmetric(
    span::Real,
    rise::Real,
    trib_depth::Real,
    thickness::Real,
    rib_depth::Real,
    rib_apex_rise::Real,
    density::Real,
    applied_load::Real,
    finishing_load::Real
)
    # --- Cross-sectional areas (in x-y plane per unit depth) ---
    
    # Vault shell: integral of (extrados - intrados) = thickness * span
    # Per MATLAB: "Integrand simplifies to brick_thick_m due to linear shift"
    vault_cs_area = thickness * span  # [m²]
    
    # Rib area: integral of (rib_top_line - extrados)
    # Rib top is flat at height: rise + thickness + rib_apex_rise
    rib_top_height = rise + thickness + rib_apex_rise
    
    if rib_apex_rise > 0
        # Integrate (rib_top - extrados) from 0 to span
        rib_integrand(x) = rib_top_height - extrados(x, span, rise, thickness)
        rib_cs_area, _ = quadgk(rib_integrand, 0, span)
        rib_cs_area = max(0.0, rib_cs_area)  # Ensure non-negative
    else
        rib_cs_area = 0.0
    end
    
    # --- Volume and mass ---
    vault_volume = vault_cs_area * trib_depth      # [m³]
    rib_volume = rib_cs_area * rib_depth           # [m³]
    
    vault_mass = vault_volume * density            # [kg]
    rib_mass = rib_volume * density                # [kg]
    
    # --- Self-weight ---
    total_self_weight_N = (vault_mass + rib_mass) * GRAVITY
    self_weight_kN_m = (total_self_weight_N / span) / 1000        # [kN/m along span]
    self_weight_kN_m² = (total_self_weight_N / span / trib_depth) / 1000  # [kN/m²]
    
    # --- Total load ---
    # Applied loads are per m², convert to per m of span
    applied_dist_kN_m = applied_load * trib_depth
    finishing_dist_kN_m = finishing_load * trib_depth
    
    total_UDL_kN_m = applied_dist_kN_m + finishing_dist_kN_m + self_weight_kN_m
    
    # --- Three-hinge parabolic arch analysis ---
    # Vertical reaction at each support
    vertical_reaction_kN = (total_UDL_kN_m * span) / 2
    
    # Horizontal thrust: H = wL²/(8h) for parabolic arch under UDL
    thrust_kN = (total_UDL_kN_m * span^2) / (8 * rise)
    
    # Resultant force at abutment
    resultant_kN = sqrt(vertical_reaction_kN^2 + thrust_kN^2)
    
    # --- Working stress ---
    # Resisting area at springing = trib_depth × thickness
    resisting_area = trib_depth * thickness
    resisting_area > 0 || error("Resisting area must be positive")
    
    # Working stress [Pa] then convert to [MPa]
    σ_Pa = (resultant_kN * 1000) / resisting_area
    σ_MPa = σ_Pa / 1e6
    
    return (σ_MPa=σ_MPa, thrust_kN=thrust_kN, self_weight_kN_m²=self_weight_kN_m², 
            vertical_kN=vertical_reaction_kN)
end

# =============================================================================
# Asymmetric Load Analysis (VaultStress_Asymmetric.m)
# =============================================================================

"""
Calculate working stress for asymmetric (half-span live) load case.

Direct translation of VaultStress_Asymmetric.m logic.
Assumes live load applied to one half of span only.

# Arguments
Same as `vault_stress_symmetric`

# Returns
Named tuple: (σ_MPa, thrust_kN, self_weight_kN_m², vertical_max_kN)
"""
function vault_stress_asymmetric(
    span::Real,
    rise::Real,
    trib_depth::Real,
    thickness::Real,
    rib_depth::Real,
    rib_apex_rise::Real,
    density::Real,
    applied_load::Real,
    finishing_load::Real
)
    # --- Self-weight calculation (same as symmetric) ---
    vault_cs_area = thickness * span
    
    rib_top_height = rise + thickness + rib_apex_rise
    if rib_apex_rise > 0
        rib_integrand(x) = rib_top_height - extrados(x, span, rise, thickness)
        rib_cs_area, _ = quadgk(rib_integrand, 0, span)
        rib_cs_area = max(0.0, rib_cs_area)
    else
        rib_cs_area = 0.0
    end
    
    vault_volume = vault_cs_area * trib_depth
    rib_volume = rib_cs_area * rib_depth
    
    total_self_weight_N = (vault_volume + rib_volume) * density * GRAVITY
    self_weight_kN_m = (total_self_weight_N / span) / 1000
    self_weight_kN_m² = (total_self_weight_N / span / trib_depth) / 1000
    
    # --- Load components ---
    finishing_dist_kN_m = finishing_load * trib_depth
    q_dead_kN_m = self_weight_kN_m + finishing_dist_kN_m  # Dead load per m
    q_live_kN_m = applied_load * trib_depth               # Live load per m
    
    # --- Asymmetric analysis (half-span live load) ---
    # Horizontal thrust for asymmetric loading
    thrust_kN = (span^2 / (16 * rise)) * (2 * q_dead_kN_m + q_live_kN_m)
    
    # Vertical reactions for each side
    vertical_live_side_kN = (q_dead_kN_m * span / 2) + (3 * q_live_kN_m * span / 8)
    vertical_no_live_side_kN = (q_dead_kN_m * span / 2) + (q_live_kN_m * span / 8)
    
    # Resultant forces at each support
    resultant_live_side_kN = sqrt(vertical_live_side_kN^2 + thrust_kN^2)
    resultant_no_live_side_kN = sqrt(vertical_no_live_side_kN^2 + thrust_kN^2)
    
    # Maximum resultant (governs design)
    max_resultant_kN = max(resultant_live_side_kN, resultant_no_live_side_kN)
    max_vertical_kN = max(vertical_live_side_kN, vertical_no_live_side_kN)
    
    # --- Working stress ---
    resisting_area = trib_depth * thickness
    resisting_area > 0 || error("Resisting area must be positive")
    
    σ_Pa = (max_resultant_kN * 1000) / resisting_area
    σ_MPa = σ_Pa / 1e6
    
    return (σ_MPa=σ_MPa, thrust_kN=thrust_kN, self_weight_kN_m²=self_weight_kN_m², 
            vertical_max_kN=max_vertical_kN)
end

# =============================================================================
# Elastic Shortening Solver (solveFullyCoupledRise.m)
# =============================================================================

"""
Solve for equilibrium rise considering elastic shortening.

Direct translation of solveFullyCoupledRise.m logic.
Uses iterative solver to find final rise where geometric arc length
equals original arc length minus elastic shortening.

# Arguments
- `span`: Span of arch [m]
- `initial_rise`: Rise before loading [m]
- `total_load_Pa`: Total load (self + live) [Pa = N/m²]
- `thickness`: Shell thickness [m]
- `trib_depth`: Tributary depth [m]
- `E_MPa`: Modulus of elasticity [MPa]
- `deflection_limit`: Max allowable change in rise [m] (default: Inf)

# Returns
Named tuple: (final_rise, converged, deflection_ok)
"""
function solve_equilibrium_rise(
    span::Real,
    initial_rise::Real,
    total_load_Pa::Real,
    thickness::Real,
    trib_depth::Real,
    E_MPa::Real;
    deflection_limit::Real=Inf
)
    E_Pa = E_MPa * 1e6
    area = thickness * trib_depth
    w_N_m = total_load_Pa * trib_depth  # Line load [N/m]
    
    # Original arc length
    L_original = parabolic_arc_length(span, initial_rise)
    isnan(L_original) && error("Could not calculate initial arc length")
    
    # Objective: find rise where geometric length = elastic length
    function objective(test_rise)
        if abs(test_rise) < 1e-9
            return L_original  # No shortening if flat
        end
        
        # dy/dx for test rise
        dydx(x) = (4 * test_rise) / span - (8 * x * test_rise) / span^2
        
        # dL/dx = √(1 + (dy/dx)²)
        dLdx(x) = sqrt(1 + dydx(x)^2)
        
        # Force at point x: resultant of thrust and vertical reaction
        # Thrust: H = wL²/(8h), Vertical at x: V(x) = wL/2 - wx
        thrust_sq = ((w_N_m * span^2) / (8 * test_rise))^2
        force(x) = sqrt(thrust_sq + ((w_N_m * span / 2) - w_N_m * x)^2)
        
        # Integral of force along arc: ∫ F(x) * dL/dx dx
        combined_integrand(x) = force(x) * dLdx(x)
        integral_force_dL, _ = quadgk(combined_integrand, 0, span)
        
        # Elastic shortening
        shortening = integral_force_dL / (area * E_Pa)
        
        # Target length and actual geometric length
        L_target = L_original - shortening
        L_actual = parabolic_arc_length(span, test_rise)
        
        return L_actual - L_target
    end
    
    # Solve using derivative-free method with initial guess
    # MATLAB uses fzero(f, x0) which searches for a bracket automatically
    # We use Order0() which is similar - a robust derivative-free method
    initial_guess = initial_rise * 0.98
    
    try
        # Use Order0 (secant-like) starting from initial guess
        # This matches MATLAB's fzero(f, x0) behavior
        final_rise = find_zero(objective, initial_guess, Order0())
        
        # Validate result is physically reasonable
        if final_rise <= 0 || final_rise > initial_rise * 1.1
            return (final_rise=NaN, converged=false, deflection_ok=false)
        end
        
        # Check deflection
        deflection = abs(initial_rise - final_rise)
        deflection_ok = deflection <= deflection_limit
        
        return (final_rise=final_rise, converged=true, deflection_ok=deflection_ok)
    catch e
        # Silently fail for expected non-convergence cases
        return (final_rise=NaN, converged=false, deflection_ok=false)
    end
end

# =============================================================================
# Main API: size_floor
# =============================================================================

"""
Size an unreinforced vault using Haile's method.

# Arguments
- `span`: Clear span (chord length) [m]
- `load`: Superimposed live load [kN/m²]
- `material`: Concrete material (provides E, ρ)
- `rise`: Rise at crown [m] (provide either `rise` or `lambda`, not both)
- `lambda`: Span/rise ratio (provide either `rise` or `lambda`, not both)
- `thickness`: Shell thickness [m] (optional - if omitted, iterates to find minimum)
- `trib_depth`: Tributary depth / rib spacing [m] (default: 1.0)
- `rib_depth`: Rib width in span direction [m] (default: 0.0, no ribs)
- `rib_apex_rise`: Additional rib height above vault extrados at apex [m] (default: 0.0)
- `finishing_load`: Topping/screed load [kN/m²] (default: 0.0)
- `allowable_stress`: Max allowable compressive stress [MPa] (optional - no check if omitted)
- `deflection_limit`: Max allowable rise deflection [m] (default: span/240)
- `check_asymmetric`: Also check half-span live load case (default: true)

# Returns
`VaultResult` with thickness, rise, thrust, self_weight

# Example
```julia
# Using rise directly
result = size_floor(Vault(), 6.0, 2.5; rise=1.0, material=NWC_4000)

# Using lambda (span/rise ratio) - equivalent to rise=1.0 for 6m span
result = size_floor(Vault(), 6.0, 2.5; lambda=6.0, material=NWC_4000)
```
"""
function size_floor(::Vault, span::Real, load::Real;
                    material::Concrete=NWC_4000,
                    rise::Union{Real,Nothing}=nothing,
                    lambda::Union{Real,Nothing}=nothing,
                    thickness::Union{Real,Nothing}=nothing,
                    trib_depth::Real=1.0,
                    rib_depth::Real=0.0,
                    rib_apex_rise::Real=0.0,
                    finishing_load::Real=0.0,
                    allowable_stress::Union{Real,Nothing}=nothing,
                    deflection_limit::Union{Real,Nothing}=nothing,
                    check_asymmetric::Bool=true)
    
    # Validate rise/lambda: exactly one must be provided
    if !isnothing(rise) && !isnothing(lambda)
        throw(ArgumentError("Provide either `rise` or `lambda`, not both"))
    elseif isnothing(rise) && isnothing(lambda)
        throw(ArgumentError("Vault requires `rise` or `lambda` kwarg"))
    end
    
    # Compute rise from lambda if needed
    rise = isnothing(rise) ? span / lambda : rise
    rise > 0 || throw(ArgumentError("Rise must be positive (check lambda > 0)"))
    
    # Material properties (explicit unit conversion for safety)
    density = ustrip(u"kg/m^3", material.ρ)
    E_MPa = ustrip(u"MPa", material.E)
    
    # Default deflection limit: span/240
    defl_lim = isnothing(deflection_limit) ? span / 240 : deflection_limit
    
    # --- Determine thickness ---
    if isnothing(thickness)
        # SIZE MODE: iterate to find minimum thickness
        t = _find_min_thickness(span, rise, trib_depth, rib_depth, rib_apex_rise,
                                density, E_MPa, load, finishing_load,
                                allowable_stress, defl_lim, check_asymmetric)
    else
        # CHECK MODE: use provided thickness
        t = thickness
    end
    
    # --- Final analysis with chosen thickness ---
    sym = vault_stress_symmetric(span, rise, trib_depth, t, rib_depth, rib_apex_rise,
                                 density, load, finishing_load)
    
    σ_max = sym.σ_MPa
    thrust = sym.thrust_kN
    sw = sym.self_weight_kN_m²
    
    if check_asymmetric
        asym = vault_stress_asymmetric(span, rise, trib_depth, t, rib_depth, rib_apex_rise,
                                       density, load, finishing_load)
        σ_max = max(σ_max, asym.σ_MPa)
        thrust = max(thrust, asym.thrust_kN)  # Return governing thrust
    end
    
    # --- Elastic shortening check ---
    total_load_Pa = (load + sw + finishing_load) * 1000  # kN/m² to Pa
    eq = solve_equilibrium_rise(span, rise, total_load_Pa, t, trib_depth, E_MPa;
                                deflection_limit=defl_lim)
    
    final_rise = eq.converged ? eq.final_rise : rise
    
    # --- Warnings ---
    !eq.converged && @warn "Elastic shortening solver did not converge"
    eq.converged && !eq.deflection_ok && @warn "Deflection exceeds limit: Δrise > $defl_lim m"
    
    if !isnothing(allowable_stress) && σ_max > allowable_stress
        @warn "Working stress exceeds allowable: $(round(σ_max, digits=3)) > $allowable_stress MPa"
    end
    
    return VaultResult(t, final_rise, thrust, sw)
end

"""
Find minimum thickness satisfying stress and deflection constraints.
"""
function _find_min_thickness(
    span::Real,
    rise::Real,
    trib_depth::Real,
    rib_depth::Real,
    rib_apex_rise::Real,
    density::Real,
    E_MPa::Real,
    applied_load::Real,
    finishing_load::Real,
    allowable_stress::Union{Real,Nothing},
    deflection_limit::Real,
    check_asymmetric::Bool;
    t_min::Real=0.03,    # Minimum 3 cm
    t_max::Real=0.50,    # Maximum 50 cm
    t_step::Real=0.005   # 5 mm increments
)
    # If no allowable stress, only check deflection
    has_stress_check = !isnothing(allowable_stress)
    
    for t in t_min:t_step:t_max
        # Check stress
        if has_stress_check
            sym = vault_stress_symmetric(span, rise, trib_depth, t, rib_depth, rib_apex_rise,
                                         density, applied_load, finishing_load)
            σ_max = sym.σ_MPa
            sw = sym.self_weight_kN_m²
            
            if check_asymmetric
                asym = vault_stress_asymmetric(span, rise, trib_depth, t, rib_depth, rib_apex_rise,
                                               density, applied_load, finishing_load)
                σ_max = max(σ_max, asym.σ_MPa)
            end
            
            σ_max > allowable_stress && continue  # Too thin
        else
            sym = vault_stress_symmetric(span, rise, trib_depth, t, rib_depth, rib_apex_rise,
                                         density, applied_load, finishing_load)
            sw = sym.self_weight_kN_m²
        end
        
        # Check deflection via elastic shortening
        total_load_Pa = (applied_load + sw + finishing_load) * 1000
        eq = solve_equilibrium_rise(span, rise, total_load_Pa, t, trib_depth, E_MPa;
                                    deflection_limit=deflection_limit)
        
        if eq.converged && eq.deflection_ok
            return t  # Found valid thickness
        end
    end
    
    @warn "Could not find valid thickness in range [$t_min, $t_max] m"
    return t_max
end

# =============================================================================
# Structural Effects
# =============================================================================

"""
Apply vault thrust to structural model.

Adds horizontal thrust to support nodes and edge beams.
Thrust is per unit length of vault edge (kN/m).

# Effects
- Horizontal point loads at corner nodes
- Axial compression in edge beams
- Potential uplift at supports (check stability)
"""
function apply_effects!(::Vault, struc, slab, section::VaultResult)
    # TODO: Implement thrust application to structural model
    # This requires knowledge of the structural model API
    #
    # Conceptually:
    # 1. Identify edge beams/nodes at vault supports
    # 2. Apply horizontal thrust = section.thrust * edge_length
    # 3. Add axial load to edge beams
    #
    # For now, warn that this needs model-specific implementation
    @warn "Vault thrust application not yet implemented - manual thrust check required"
    @info "Vault thrust: $(round(section.thrust, digits=2)) kN/m at supports"
    return nothing
end
