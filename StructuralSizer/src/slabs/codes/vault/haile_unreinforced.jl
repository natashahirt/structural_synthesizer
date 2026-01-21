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

const GRAVITY = ustrip(u"m/s^2", StructuralUnits.GRAVITY)  # m/s²

# =============================================================================
# Geometry Utilities
# =============================================================================

"""
Calculate arc length of a parabolic vault.

Intrados defined by: y(x) = (4h/s²) * x * (s - x)

Translation of getParabolicArcLength.m
"""
function parabolic_arc_length(span::Real, rise::Real)
    # y = (4h/s²) * (sx - x²)
    # dy/dx = (4h/s²) * (s - 2x)
    # L = integral of sqrt(1 + (dy/dx)²) dx from 0 to s
    k = 4 * rise / span^2
    integrand(x) = sqrt(1 + (k * (span - 2x))^2)
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

"""
Calculate geometric properties (volumes, areas) for a vault.
"""
function get_vault_properties(
    span::Real,
    rise::Real,
    thickness::Real,
    trib_depth::Real,
    rib_depth::Real,
    rib_apex_rise::Real
)
    # Shell volume: arc_length × thickness × trib_depth
    arc_len = parabolic_arc_length(span, rise)
    
    # Cross-sectional area of the shell (per unit depth)
    # Integral of (extrados - intrados) = thickness * span (linear shift approximation)
    shell_cs_area = thickness * span
    shell_vol = shell_cs_area * trib_depth
    
    # Rib calculations
    rib_cs_area = 0.0
    if rib_apex_rise > 0 && rib_depth > 0
        rib_top_height = rise + thickness + rib_apex_rise
        rib_integrand(x) = max(0.0, rib_top_height - extrados(x, span, rise, thickness))
        val, _ = quadgk(rib_integrand, 0, span)
        rib_cs_area = val
    end
    rib_vol = rib_cs_area * rib_depth
    
    return (
        arc_length = arc_len,
        shell_cs_area = shell_cs_area,
        shell_vol = shell_vol,
        rib_cs_area = rib_cs_area,
        rib_vol = rib_vol,
        total_vol = shell_vol + rib_vol
    )
end

"""
Calculate material volume per unit plan area for a vault.

Accounts for curved shell geometry (arc length > span) and ribs.

# Returns
Volume per plan area [m³/m²]
"""
function vault_volume_per_area(
    span::Real,
    rise::Real,
    thickness::Real,
    trib_depth::Real,
    rib_depth::Real,
    rib_apex_rise::Real
)
    props = get_vault_properties(span, rise, thickness, trib_depth, rib_depth, rib_apex_rise)
    
    # Normalized to plan area (span × trib_depth)
    plan_area = span * trib_depth
    return props.total_vol / plan_area
end

# =============================================================================
# Symmetric Load Analysis (VaultStress.m)
# =============================================================================

"""
Calculate working stress and thrust for symmetric UDL case.

# Arguments
- `applied_load`: [kN/m²]
- `finishing_load`: [kN/m²]
- `thickness`: Shell thickness [m]
- `density`: Material density [kg/m³]
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
    # --- Geometric Properties ---
    props = get_vault_properties(span, rise, thickness, trib_depth, rib_depth, rib_apex_rise)
    
    # --- Mass ---
    # Convert volume to mass
    total_mass = props.total_vol * density
    
    # --- Self-weight ---
    total_self_weight_N = total_mass * GRAVITY
    # Convert N -> kN
    total_self_weight_kN = ustrip(u"kN", total_self_weight_N * u"N")
    
    self_weight_kN_m = total_self_weight_kN / span        # [kN/m along span]
    self_weight_kN_m² = total_self_weight_kN / (span * trib_depth)  # [kN/m²]
    
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
    # resultant_kN -> N = * 1000
    σ_Pa = (resultant_kN * 1000) / resisting_area
    σ_MPa = ustrip(u"MPa", σ_Pa * u"Pa")
    
    return (σ_MPa=σ_MPa, thrust_kN=thrust_kN, self_weight_kN_m²=self_weight_kN_m², 
            vertical_kN=vertical_reaction_kN)
end

# =============================================================================
# Asymmetric Load Analysis (VaultStress_Asymmetric.m)
# =============================================================================

"""
Calculate working stress and thrust for asymmetric case (live load on half-span).

Reference: Haile's VaultStress_Asymmetric.m
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
    # For asymmetric analysis, only live load is asymmetric
    # Total UDL on half 1 (left): SW + finish + Live
    # Total UDL on half 2 (right): SW + finish
    
    # 1. Base symmetric self-weight and finishing
    # We can use vault_stress_symmetric with zero live load
    base = vault_stress_symmetric(span, rise, trib_depth, thickness, rib_depth, rib_apex_rise,
                                  density, 0.0, finishing_load)
    
    q_d = (base.vertical_kN * 2) / span  # Total dead load kN/m
    
    # 2. Live load intensity kN/m
    q_l = applied_load * trib_depth
    
    # 3. Asymmetric Thrust (H_asym)
    # H = (L²/16h) * (2q_d + q_l)
    thrust_kN = (span^2 / (16 * rise)) * (2q_d + q_l)
    
    # 4. Vertical reactions
    # V1 (loaded side) = (L/8) * (4q_d + 3q_l)
    # V2 (unloaded side) = (L/8) * (4q_d + q_l)
    V1 = (span / 8) * (4q_d + 3q_l)
    # V2 = (span / 8) * (4q_d + q_l)
    
    # 5. Working stress at abutments (governed by V1)
    resisting_area = trib_depth * thickness
    resultant_kN = sqrt(V1^2 + thrust_kN^2)
    σ_MPa = ustrip(u"MPa", ((resultant_kN * 1000) / resisting_area) * u"Pa")
    
    return (σ_MPa=σ_MPa, thrust_kN=thrust_kN, self_weight_kN_m²=base.self_weight_kN_m²,
            vertical_kN=V1)
end

# =============================================================================
# Elastic Shortening Solver (solveFullyCoupledRise.m)
# =============================================================================

"""
Determine equilibrium rise accounting for elastic shortening.

Iteratively solves for rise h such that shortening matches geometry change.
Ref: Haile's solveFullyCoupledRise.m
"""
function solve_equilibrium_rise(
    span::Real,
    initial_rise::Real,
    total_load_Pa::Real,
    thickness::Real,
    trib_depth::Real,
    E_MPa::Real;
    deflection_limit::Real = 0.05
)
    E_Pa = ustrip(u"Pa", E_MPa * u"MPa")
    A_springing = thickness * trib_depth
    
    # Residual function for root finding: f(h) = ΔL_geometry(h) - ΔL_elastic(h)
    function residual(h)
        # 1. Arc length at this rise
        L = parabolic_arc_length(span, h)
        L0 = parabolic_arc_length(span, initial_rise)
        ΔL_geom = L0 - L
        
        # 2. Elastic shortening
        # H = wL² / 8h
        # V = wL / 2
        # Resultant R = sqrt(H² + V²)
        w = total_load_Pa * trib_depth
        H = (w * span^2) / (8h)
        V = (w * span) / 2
        R = sqrt(H^2 + V^2)
        
        # Approximate average axial force as resultant at support
        # ΔL = R * L / (A * E)
        ΔL_elastic = (R * L) / (A_springing * E_Pa)
        
        return ΔL_geom - ΔL_elastic
    end
    
    # Solve for final_rise
    # Initial guess is slightly lower than initial_rise (shortening)
    try
        # Use Order0() which mimics MATLAB's fzero (derivative-free, search-based)
        final_rise = find_zero(residual, initial_rise, Order0())
        
        # Sanity checks
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
- `span`: Clear span (chord length) - any length unit
- `sdl`: Superimposed dead load - any force/area unit
- `live`: Live load - any force/area unit
- `rise`: Rise at crown (provide either `rise` or `lambda`, not both)
- `lambda`: Span/rise ratio (dimensionless)
- `thickness`: Shell thickness (optional - iterates to find minimum if omitted)
- `trib_depth`: Tributary depth / rib spacing (default: 1.0m)
- `rib_depth`: Rib width in span direction (default: 0.0m, no ribs)
- `rib_apex_rise`: Additional rib height above extrados at apex (default: 0.0m)
- `finishing_load`: Topping/screed load (default: 0.0)
- `allowable_stress`: Max allowable compressive stress [MPa] (optional)
- `deflection_limit`: Max allowable rise deflection (default: span/240)
- `check_asymmetric`: Also check half-span live load case (default: true)

# Returns
`VaultResult{L,P,F}` preserving input unit types

# Example
```julia
result = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 2.0u"kN/m^2"; rise=1.0u"m")
```
"""
function size_floor(::Vault, span::L, sdl::F, live::F;
                    material::Concrete=NWC_4000,
                    options::FloorOptions=FloorOptions(),
                    rise::Union{L,Nothing}=nothing,
                    lambda::Union{Real,Nothing}=nothing,
                    thickness::Union{L,Nothing}=nothing,
                    trib_depth::L=uconvert(unit(span), 1.0u"m"),
                    rib_depth::L=zero(span),
                    rib_apex_rise::L=zero(span),
                    finishing_load::F=zero(sdl),
                    allowable_stress::Union{Real,Nothing}=nothing,
                    deflection_limit::Union{L,Nothing}=nothing,
                    check_asymmetric::Bool=true) where {L, F}
    
    vopt = options.vault
    rise = isnothing(rise) ? vopt.rise : rise
    lambda = isnothing(lambda) ? vopt.lambda : lambda
    thickness = isnothing(thickness) ? vopt.thickness : thickness
    if vopt.trib_depth !== nothing
        trib_depth = vopt.trib_depth
    end
    if vopt.rib_depth !== nothing
        rib_depth = vopt.rib_depth
    end
    if vopt.rib_apex_rise !== nothing
        rib_apex_rise = vopt.rib_apex_rise
    end
    if vopt.finishing_load !== nothing
        finishing_load = vopt.finishing_load
    end
    allowable_stress = isnothing(allowable_stress) ? vopt.allowable_stress : allowable_stress
    deflection_limit = isnothing(deflection_limit) ? vopt.deflection_limit : deflection_limit
    if vopt.check_asymmetric !== nothing
        check_asymmetric = vopt.check_asymmetric
    end

    if !isnothing(rise) && !isnothing(lambda)
        throw(ArgumentError("Provide either `rise` or `lambda`, not both"))
    elseif isnothing(rise) && isnothing(lambda)
        throw(ArgumentError("Vault requires `rise` or `lambda` kwarg"))
    end
    
    # Strip units for internal calculations (MATLAB-style arithmetic)
    span_m = ustrip(u"m", span)
    sdl_kN = ustrip(u"kN/m^2", sdl)
    live_kN = ustrip(u"kN/m^2", live)
    trib_m = ustrip(u"m", trib_depth)
    rib_d_m = ustrip(u"m", rib_depth)
    rib_h_m = ustrip(u"m", rib_apex_rise)
    finish_kN = ustrip(u"kN/m^2", finishing_load)
    density = ustrip(u"kg/m^3", material.ρ)
    E_MPa = ustrip(u"MPa", material.E)
    
    # Total applied load for stress check
    total_app_load_kN = sdl_kN + live_kN
    
    # Compute rise from lambda if needed
    rise_m = isnothing(rise) ? span_m / lambda : ustrip(u"m", rise)
    rise_m > 0 || throw(ArgumentError("Rise must be positive (check lambda > 0)"))
    
    # Default deflection limit: span/240
    defl_lim = isnothing(deflection_limit) ? span_m / 240 : ustrip(u"m", deflection_limit)
    
    # Strip thickness if provided
    t_m = isnothing(thickness) ? nothing : ustrip(u"m", thickness)
    
    # --- Determine thickness ---
    if isnothing(t_m)
        t_m = _find_min_thickness(span_m, rise_m, trib_m, rib_d_m, rib_h_m,
                                  density, E_MPa, total_app_load_kN, finish_kN,
                                  allowable_stress, defl_lim, check_asymmetric)
    end
    
    # --- Final analysis with chosen thickness ---
    # Dead component: SW + finishing + SDL
    sym_dead = vault_stress_symmetric(span_m, rise_m, trib_m, t_m, rib_d_m, rib_h_m,
                                      density, sdl_kN, finish_kN)
    
    # Live component: Live load only
    sym_live = vault_stress_symmetric(span_m, rise_m, trib_m, t_m, rib_d_m, rib_h_m,
                                      0.0, live_kN, 0.0)
    
    σ_max = sym_dead.σ_MPa + sym_live.σ_MPa
    thrust_dead = sym_dead.thrust_kN
    thrust_live = sym_live.thrust_kN
    sw = sym_dead.self_weight_kN_m²
    
    if check_asymmetric
        asym_total = vault_stress_asymmetric(span_m, rise_m, trib_m, t_m, rib_d_m, rib_h_m,
                                             density, sdl_kN + live_kN, finish_kN)
        σ_max = max(σ_max, asym_total.σ_MPa)
    end
    
    # --- Elastic shortening check ---
    # total_load_Pa = kN/m2 -> Pa = * 1000
    total_load_Pa = (sdl_kN + live_kN + sw + finish_kN) * 1000
    eq = solve_equilibrium_rise(span_m, rise_m, total_load_Pa, t_m, trib_m, E_MPa;
                                deflection_limit=defl_lim)
    
    final_rise = eq.converged ? eq.final_rise : rise_m
    
    # --- Warnings ---
    !eq.converged && @warn "Elastic shortening solver did not converge"
    eq.converged && !eq.deflection_ok && @warn "Deflection exceeds limit"
    
    if !isnothing(allowable_stress) && σ_max > allowable_stress
        @warn "Working stress exceeds allowable: $(round(σ_max, digits=3)) > $allowable_stress MPa"
    end
    
    # --- Material volume (for carbon calculations) ---
    vol_per_area = vault_volume_per_area(span_m, final_rise, t_m, trib_m, rib_d_m, rib_h_m)
    
    # Convert outputs to match input unit system (where meaningful).
    len_unit = unit(span)
    force_area_unit = unit(sdl)
    
    t_out = uconvert(len_unit, t_m * u"m")
    rise_out = uconvert(len_unit, final_rise * u"m")
    
    # `thrust_*` from the Haile arch formulas is a *resultant force* [kN] for the analyzed strip
    # of width `trib_depth`. Convert to a line load along the support edge by dividing by strip width.
    thrust_dead_line_kN_m = thrust_dead / trib_m
    thrust_live_line_kN_m = thrust_live / trib_m
    thrust_dead_out = uconvert(u"kN/m", thrust_dead_line_kN_m * u"kN/m")
    thrust_live_out = uconvert(u"kN/m", thrust_live_line_kN_m * u"kN/m")
    
    # Volume is length (m^3/m^2 = m), convert to length unit
    vol_out = uconvert(len_unit, vol_per_area * u"m")
    
    sw_out = uconvert(force_area_unit, sw * u"kN/m^2")
    
    return VaultResult(t_out, rise_out, thrust_dead_out, thrust_live_out, vol_out, sw_out)
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
    t_min::Real=0.03,
    t_max::Real=0.50,
    t_step::Real=0.005
)
    has_stress_check = !isnothing(allowable_stress)
    
    for t in t_min:t_step:t_max
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
            
            σ_max > allowable_stress && continue
        else
            sym = vault_stress_symmetric(span, rise, trib_depth, t, rib_depth, rib_apex_rise,
                                         density, applied_load, finishing_load)
            sw = sym.self_weight_kN_m²
        end
        
        total_load_Pa = (applied_load + sw + finishing_load) * 1000
        eq = solve_equilibrium_rise(span, rise, total_load_Pa, t, trib_depth, E_MPa;
                                    deflection_limit=deflection_limit)
        
        if eq.converged && eq.deflection_ok
            return t
        end
    end
    
    @warn "Could not find valid thickness in range [$t_min, $t_max] m"
    return t_max
end
