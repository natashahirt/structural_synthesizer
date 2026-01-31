# ==============================================================================
# ACI 318-19 Slenderness Effects (Moment Magnification)
# ==============================================================================
# Reference: ACI 318-19 Chapter 6 (Structural Analysis)
# Verified against StructurePoint spColumn Design Examples:
# - "Slender Column Design in Non-Sway Frame - Moment Magnification Method"
# - "Slenderness Effects for Concrete Columns in Sway Frame"

using Unitful

# ==============================================================================
# Material Properties for Slenderness
# ==============================================================================

"""
    concrete_modulus(fc_ksi::Real) -> Float64

Calculate concrete elastic modulus Ec per ACI 318-19 (19.2.2.1.b).
For normal-weight concrete: Ec = 57000 * √f'c (psi)
Returns value in ksi.
"""
function concrete_modulus(fc_ksi::Real)
    fc_psi = fc_ksi * 1000
    Ec_psi = 57000 * sqrt(fc_psi)
    return Ec_psi / 1000  # ksi
end

# ==============================================================================
# Slenderness Check
# ==============================================================================

"""
    slenderness_ratio(section::RCColumnSection, geometry::ConcreteMemberGeometry) -> Float64

Calculate slenderness ratio kLu/r per ACI 318-19.

# Arguments
- `section`: RC column section
- `geometry`: Column geometry with Lu, k

# Returns
- Slenderness ratio (dimensionless)
"""
function slenderness_ratio(section::RCColumnSection, geometry)
    # Radius of gyration: r = 0.3h for rectangular sections (ACI 6.2.5.2)
    h_in = ustrip(u"inch", section.h)
    r_in = 0.3 * h_in
    
    # Unsupported length - ConcreteMemberGeometry stores Lu in meters
    Lu_in = geometry.Lu isa Unitful.Length ? 
            ustrip(u"inch", geometry.Lu) : 
            geometry.Lu * 39.37  # meters to inches
    
    k = geometry.k
    
    return k * Lu_in / r_in
end

"""
    should_consider_slenderness(section, geometry; M1::Real=0.0, M2::Real=1.0) -> Bool

Check if slenderness effects should be considered per ACI 318-19 6.2.5.1.

# Arguments
- `section`: RC column section
- `geometry`: Column geometry with Lu, k, braced
- `M1`: Smaller factored end moment (kip-ft)
- `M2`: Larger factored end moment (kip-ft)

# Returns
- `true` if slenderness effects must be considered

# ACI 318-19 Limits
- Non-sway (braced): kLu/r ≤ 34 - 12(M1/M2), max 40
- Sway (unbraced): kLu/r ≤ 22
"""
function should_consider_slenderness(
    section::RCColumnSection, 
    geometry;
    M1::Real = 0.0,
    M2::Real = 1.0
)
    λ = slenderness_ratio(section, geometry)
    
    if geometry.braced
        # Non-sway: ACI 6.2.5.1(b)
        # M1/M2 is positive for single curvature, negative for double
        M_ratio = M2 ≈ 0 ? 0.0 : M1 / M2
        limit = min(34 - 12 * M_ratio, 40)
        return λ > limit
    else
        # Sway: ACI 6.2.5.1(a)
        return λ > 22
    end
end

# ==============================================================================
# Effective Stiffness (EI)_eff
# ==============================================================================

"""
    effective_stiffness(section, mat; βdns::Real=0.6, method::Symbol=:accurate) -> Float64

Calculate effective flexural stiffness (EI)_eff for buckling analysis.
Per ACI 318-19 (6.6.4.4.4).

# Arguments
- `section`: RC column section
- `mat`: Material properties (fc, fy, Es)
- `βdns`: Ratio of sustained to total factored axial load (default 0.6)
- `method`: `:accurate` (includes steel) or `:simplified` (0.4EcIg)

# Returns
- (EI)_eff in kip-in²

# Methods (ACI 6.6.4.4.4)
- `:accurate` (b): (EI)_eff = (0.2*Ec*Ig + Es*Ise) / (1 + βdns)
- `:simplified` (a): (EI)_eff = 0.4*Ec*Ig / (1 + βdns)

Note: spColumn uses the `:accurate` method.
"""
function effective_stiffness(
    section::RCColumnSection, 
    mat;
    βdns::Real = 0.6,
    method::Symbol = :accurate
)
    # Material properties
    fc = _get_fc_ksi(mat)
    Es = _get_Es_ksi(mat)
    Ec = concrete_modulus(fc)
    
    # Gross moment of inertia
    b_in = ustrip(u"inch", section.b)
    h_in = ustrip(u"inch", section.h)
    Ig = b_in * h_in^3 / 12  # in⁴
    
    if method == :accurate
        # Method (b): Accounts for reinforcement
        # Ise = moment of inertia of reinforcement about centroid
        Ise = _calc_Ise(section)
        EI_eff = (0.2 * Ec * Ig + Es * Ise) / (1 + βdns)
    else
        # Method (a): Simplified
        EI_eff = 0.4 * Ec * Ig / (1 + βdns)
    end
    
    return EI_eff  # kip-in²
end

"""Calculate moment of inertia of reinforcement about section centroid."""
function _calc_Ise(section::RCColumnSection)
    h_in = ustrip(u"inch", section.h)
    centroid = h_in / 2
    
    Ise = 0.0
    for bar in section.bars
        y_bar = ustrip(u"inch", bar.y)
        As_bar = ustrip(u"inch^2", bar.As)
        d = y_bar - centroid  # Distance from centroid
        Ise += As_bar * d^2   # Parallel axis theorem (ignore bar's own I)
    end
    
    return Ise  # in⁴
end

# ==============================================================================
# Critical Buckling Load
# ==============================================================================

"""
    critical_buckling_load(section, mat, geometry; βdns::Real=0.6) -> Float64

Calculate Euler critical buckling load Pc per ACI 318-19 (6.6.4.4.2).

Pc = π² * (EI)_eff / (k*Lu)²

# Returns
- Critical load Pc (kip)
"""
function critical_buckling_load(
    section::RCColumnSection,
    mat,
    geometry;
    βdns::Real = 0.6
)
    EI_eff = effective_stiffness(section, mat; βdns=βdns)
    
    # Effective length
    Lu_in = geometry.Lu isa Unitful.Length ?
            ustrip(u"inch", geometry.Lu) :
            geometry.Lu * 39.37  # m to in
    k = geometry.k
    kLu = k * Lu_in
    
    # Critical load
    Pc = π^2 * EI_eff / kLu^2
    
    return Pc  # kip
end

# ==============================================================================
# Moment Magnification - Non-Sway Frame
# ==============================================================================

"""
    magnification_factor_nonsway(Pu, Pc; Cm::Real=1.0) -> Float64

Calculate moment magnification factor δns for non-sway frames.
Per ACI 318-19 (6.6.4.5.2).

δns = Cm / (1 - Pu/(0.75*Pc)) ≥ 1.0

# Arguments
- `Pu`: Factored axial load (kip)
- `Pc`: Critical buckling load (kip)
- `Cm`: Equivalent uniform moment factor (default 1.0)

# Returns
- Magnification factor δns ≥ 1.0
"""
function magnification_factor_nonsway(Pu::Real, Pc::Real; Cm::Real = 1.0)
    if Pu ≥ 0.75 * Pc
        # Section is unstable
        return Inf
    end
    
    δns = Cm / (1 - Pu / (0.75 * Pc))
    return max(δns, 1.0)
end

"""
    calc_Cm(M1::Real, M2::Real; transverse_load::Bool=false) -> Float64

Calculate equivalent uniform moment factor Cm.
Per ACI 318-19 (6.6.4.5.3).

# Arguments
- `M1`: Smaller factored end moment (kip-ft)
- `M2`: Larger factored end moment (kip-ft)
- `transverse_load`: True if transverse loads exist between supports

# Returns
- Cm factor

# Notes
- M1/M2 is positive for single curvature, negative for double curvature
- Cm = 1.0 for transverse loads
"""
function calc_Cm(M1::Real, M2::Real; transverse_load::Bool = false)
    if transverse_load
        return 1.0
    end
    
    if abs(M2) < 1e-6
        return 1.0  # Avoid division by zero
    end
    
    M_ratio = M1 / M2
    Cm = 0.6 - 0.4 * M_ratio
    return max(Cm, 0.4)  # ACI minimum
end

"""
    minimum_moment(Pu::Real, h_in::Real) -> Float64

Calculate minimum design moment per ACI 318-19 (6.6.4.5.4).

M_min = Pu * (0.6 + 0.03h)

# Arguments
- `Pu`: Factored axial load (kip)
- `h_in`: Section dimension in direction of bending (in)

# Returns
- Minimum moment (kip-ft)
"""
function minimum_moment(Pu::Real, h_in::Real)
    # M_min = Pu * (0.6 + 0.03h) [in kip-in, then convert to kip-ft]
    M_min = Pu * (0.6 + 0.03 * h_in) / 12
    return M_min  # kip-ft
end

"""
    magnify_moment_nonsway(section, mat, geometry, Pu, M1, M2; 
                           βdns=0.6, transverse_load=false) -> NamedTuple

Calculate magnified design moment for non-sway frame column.
Per ACI 318-19 Section 6.6.4.5.

# Arguments
- `section`: RC column section
- `mat`: Material properties
- `geometry`: Column geometry (Lu, k, braced=true)
- `Pu`: Factored axial load (kip)
- `M1`: Smaller factored end moment (kip-ft)
- `M2`: Larger factored end moment (kip-ft)
- `βdns`: Sustained load ratio (default 0.6)
- `transverse_load`: Whether transverse loads exist

# Returns
NamedTuple with:
- `Mc`: Magnified design moment (kip-ft)
- `δns`: Magnification factor
- `Cm`: Equivalent uniform moment factor
- `Pc`: Critical buckling load (kip)
- `slender`: Whether slenderness was considered

# Reference
StructurePoint: "Slender Column Design in Non-Sway Frame"
"""
function magnify_moment_nonsway(
    section::RCColumnSection,
    mat,
    geometry,
    Pu::Real,
    M1::Real,
    M2::Real;
    βdns::Real = 0.6,
    transverse_load::Bool = false
)
    # Check if slenderness should be considered
    slender = should_consider_slenderness(section, geometry; M1=M1, M2=M2)
    
    if !slender
        # No magnification needed
        h_in = ustrip(u"inch", section.h)
        M_min = minimum_moment(Pu, h_in)
        Mc = max(abs(M2), M_min)
        return (Mc=Mc, δns=1.0, Cm=1.0, Pc=Inf, slender=false)
    end
    
    # Calculate critical load
    Pc = critical_buckling_load(section, mat, geometry; βdns=βdns)
    
    # Calculate Cm
    Cm = calc_Cm(M1, M2; transverse_load=transverse_load)
    
    # Calculate magnification factor
    δns = magnification_factor_nonsway(Pu, Pc; Cm=Cm)
    
    # Magnified moment
    h_in = ustrip(u"inch", section.h)
    M_min = minimum_moment(Pu, h_in)
    Mc = max(δns * abs(M2), M_min)
    
    return (Mc=Mc, δns=δns, Cm=Cm, Pc=Pc, slender=true)
end

# ==============================================================================
# Moment Magnification - Sway Frame
# ==============================================================================

"""
    magnification_factor_sway(ΣPu, ΣPc) -> Float64

Calculate sway magnification factor δs for sway frames.
Per ACI 318-19 (6.6.4.6.2).

δs = 1 / (1 - ΣPu/(0.75*ΣPc)) ≥ 1.0

# Arguments
- `ΣPu`: Sum of factored axial loads in story (kip)
- `ΣPc`: Sum of critical loads for all columns in story (kip)

# Returns
- Sway magnification factor δs
"""
function magnification_factor_sway(ΣPu::Real, ΣPc::Real)
    if ΣPu ≥ 0.75 * ΣPc
        return Inf  # Story is unstable
    end
    
    δs = 1 / (1 - ΣPu / (0.75 * ΣPc))
    return max(δs, 1.0)
end

"""
    magnify_moment_sway(M1ns, M2ns, M1s, M2s, δs) -> NamedTuple

Calculate magnified design moments for sway frame column.
Per ACI 318-19 (6.6.4.6.1).

# Arguments
- `M1ns, M2ns`: Non-sway moments at ends (kip-ft)
- `M1s, M2s`: Sway moments at ends (kip-ft)
- `δs`: Sway magnification factor

# Returns
NamedTuple with:
- `M1`: Magnified moment at end 1 (kip-ft)
- `M2`: Magnified moment at end 2 (kip-ft)
"""
function magnify_moment_sway(
    M1ns::Real, M2ns::Real,
    M1s::Real, M2s::Real,
    δs::Real
)
    M1 = M1ns + δs * M1s
    M2 = M2ns + δs * M2s
    return (M1=M1, M2=M2)
end

# ==============================================================================
# Circular Column Support
# ==============================================================================

"""
    slenderness_ratio(section::RCCircularSection, geometry) -> Float64

Calculate slenderness ratio kLu/r for circular sections.
Per ACI 318-19 6.2.5.2: r = 0.25D for circular sections.
"""
function slenderness_ratio(section::RCCircularSection, geometry)
    # Radius of gyration: r = 0.25D for circular sections (ACI 6.2.5.2)
    D_in = ustrip(u"inch", section.D)
    r_in = 0.25 * D_in
    
    # Unsupported length - ConcreteMemberGeometry stores Lu in meters
    Lu_in = geometry.Lu isa Unitful.Length ? 
            ustrip(u"inch", geometry.Lu) : 
            geometry.Lu * 39.37  # meters to inches
    
    k = geometry.k
    
    return k * Lu_in / r_in
end

"""
    should_consider_slenderness(section::RCCircularSection, geometry; M1, M2) -> Bool

Check slenderness for circular columns.
"""
function should_consider_slenderness(
    section::RCCircularSection, 
    geometry;
    M1::Real = 0.0,
    M2::Real = 1.0
)
    λ = slenderness_ratio(section, geometry)
    
    if geometry.braced
        M_ratio = M2 ≈ 0 ? 0.0 : M1 / M2
        limit = min(34 - 12 * M_ratio, 40)
        return λ > limit
    else
        return λ > 22
    end
end

"""
    effective_stiffness(section::RCCircularSection, mat; βdns=0.6, method=:accurate) -> Float64

Calculate effective flexural stiffness for circular columns.
Ig = πD⁴/64 for circular sections.
"""
function effective_stiffness(
    section::RCCircularSection, 
    mat;
    βdns::Real = 0.6,
    method::Symbol = :accurate
)
    fc = _get_fc_ksi(mat)
    Es = _get_Es_ksi(mat)
    Ec = concrete_modulus(fc)
    
    # Gross moment of inertia for circular: Ig = πD⁴/64
    D_in = ustrip(u"inch", section.D)
    Ig = π * D_in^4 / 64  # in⁴
    
    if method == :accurate
        Ise = _calc_Ise(section)
        EI_eff = (0.2 * Ec * Ig + Es * Ise) / (1 + βdns)
    else
        EI_eff = 0.4 * Ec * Ig / (1 + βdns)
    end
    
    return EI_eff  # kip-in²
end

"""Calculate moment of inertia of reinforcement for circular section."""
function _calc_Ise(section::RCCircularSection)
    D_in = ustrip(u"inch", section.D)
    centroid = D_in / 2  # Center of circle
    
    Ise = 0.0
    for bar in section.bars
        y_bar = ustrip(u"inch", bar.y)
        As_bar = ustrip(u"inch^2", bar.As)
        d = y_bar - centroid
        Ise += As_bar * d^2
    end
    
    return Ise  # in⁴
end

"""
    critical_buckling_load(section::RCCircularSection, mat, geometry; βdns=0.6) -> Float64

Calculate critical buckling load for circular columns.
"""
function critical_buckling_load(
    section::RCCircularSection,
    mat,
    geometry;
    βdns::Real = 0.6
)
    EI_eff = effective_stiffness(section, mat; βdns=βdns)
    
    Lu_in = geometry.Lu isa Unitful.Length ?
            ustrip(u"inch", geometry.Lu) :
            geometry.Lu * 39.37
    k = geometry.k
    kLu = k * Lu_in
    
    Pc = π^2 * EI_eff / kLu^2
    return Pc  # kip
end

"""
    magnify_moment_nonsway(section::RCCircularSection, mat, geometry, Pu, M1, M2; 
                           βdns=0.6, transverse_load=false) -> NamedTuple

Calculate magnified design moment for circular column in non-sway frame.
"""
function magnify_moment_nonsway(
    section::RCCircularSection,
    mat,
    geometry,
    Pu::Real,
    M1::Real,
    M2::Real;
    βdns::Real = 0.6,
    transverse_load::Bool = false
)
    slender = should_consider_slenderness(section, geometry; M1=M1, M2=M2)
    
    # Use diameter for minimum moment calculation
    D_in = ustrip(u"inch", section.D)
    
    if !slender
        M_min = minimum_moment(Pu, D_in)
        Mc = max(abs(M2), M_min)
        return (Mc=Mc, δns=1.0, Cm=1.0, Pc=Inf, slender=false)
    end
    
    Pc = critical_buckling_load(section, mat, geometry; βdns=βdns)
    Cm = calc_Cm(M1, M2; transverse_load=transverse_load)
    δns = magnification_factor_nonsway(Pu, Pc; Cm=Cm)
    
    M_min = minimum_moment(Pu, D_in)
    Mc = max(δns * abs(M2), M_min)
    
    return (Mc=Mc, δns=δns, Cm=Cm, Pc=Pc, slender=true)
end
