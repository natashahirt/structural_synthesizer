# ==============================================================================
# ACI 318-19 Slenderness Effects (Moment Magnification)
# ==============================================================================
# Reference: ACI 318-19 Chapter 6 (Structural Analysis)
# Verified against StructurePoint spColumn Design Examples:
# - "Slender Column Design in Non-Sway Frame - Moment Magnification Method"
# - "Slenderness Effects for Concrete Columns in Sway Frame"
#
# Uses unified material utilities from aci_material_utils.jl

using Unitful
using Asap: to_inches, to_sqinches, ksi

# ==============================================================================
# Material Properties for Slenderness
# ==============================================================================
# Note: Prefer Ec() or Ec_ksi() from aci_material_utils.jl for new code.
# This function is kept for backward compatibility with tests.
#
# ACI 318-19 (19.2.2.1.b): Ec = 57000 × √(f'c in psi)
#
# The CORRECT way is to use Unitful: Ec(4.0u"ksi") handles all conversions.
# This wrapper accepts dimensionless fc assumed to be in ksi.
"""
    concrete_modulus(fc_ksi::Real) -> Float64

Concrete elastic modulus from f'c (DEPRECATED - use Ec() with Unitful instead).

Assumes fc_ksi is f'c in ksi (dimensionless). Returns Ec in ksi (dimensionless).
"""
function concrete_modulus(fc_ksi::Real)
    # Use the proper Unitful path to avoid conversion bugs
    fc = fc_ksi * ksi
    Ec_result = 57000 * sqrt(ustrip(u"psi", fc)) * u"psi"
    return ustrip(ksi, Ec_result)
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
    h_in = to_inches(section.h)
    r_in = 0.3 * h_in
    
    # Unsupported length - ConcreteMemberGeometry stores Lu in meters or inches
    Lu_in = geometry.Lu isa Unitful.Length ? 
            to_inches(geometry.Lu) : 
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
    # Material properties (using unified extractors)
    fc = fc_ksi(mat)
    Es = Es_ksi(mat)
    Ec = Ec_ksi(mat)
    
    # Gross moment of inertia
    b_in = to_inches(section.b)
    h_in = to_inches(section.h)
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
    h_in = to_inches(section.h)
    centroid = h_in / 2
    
    Ise = 0.0
    for bar in section.bars
        y_bar = to_inches(bar.y)
        As_bar = to_sqinches(bar.As)
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
            to_inches(geometry.Lu) :
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
    h_in = to_inches(section.h)
    
    if !slender
        # No magnification needed
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
# Complete Sway Frame Magnification (Per StructurePoint Examples)
# ==============================================================================
# Reference: StructurePoint "Slender Concrete Column Design in Sway Frames -
# Moment Magnification Method (ACI 318-19)" and "Slenderness Effects for
# Concrete Columns in Sway Frame - Moment Magnification Method (ACI 318-19)"
#
# For sway frames, the complete procedure involves:
# 1. Story stability check (Q index)
# 2. Sway magnification δs at column ends
# 3. Additional slenderness check along column length (δns on magnified moments)
# ==============================================================================

"""
    StoryProperties

Properties of a story for sway frame analysis per ACI 318-19 Section 6.6.4.

# Fields
- `ΣPu`: Total factored vertical load in story (kip)
- `ΣPc`: Sum of critical buckling loads for all sway columns (kip)
- `Vus`: Factored horizontal story shear (kip)
- `Δo`: First-order relative story drift (in)
- `lc`: Story height from center-to-center of joints (in)
"""
struct StoryProperties
    ΣPu::Float64
    ΣPc::Float64
    Vus::Float64
    Δo::Float64
    lc::Float64
end

"""
    stability_index(story::StoryProperties) -> Float64

Calculate story stability index Q per ACI 318-19 (6.6.4.4.1).

Q = (ΣPu × Δo) / (Vus × lc)

# Returns
- Q: Stability index (Q > 0.05 indicates sway frame)

# Reference
ACI 318-19 6.6.4.3: Story is sway if Q > 0.05
"""
function stability_index(story::StoryProperties)
    if story.Vus ≈ 0 || story.lc ≈ 0
        return Inf  # Undefined without lateral load
    end
    return (story.ΣPu * story.Δo) / (story.Vus * story.lc)
end

"""
    is_sway_frame(story::StoryProperties) -> Bool

Determine if story is a sway frame per ACI 318-19 6.6.4.3.

A story is sway if Q > 0.05.
"""
function is_sway_frame(story::StoryProperties)
    Q = stability_index(story)
    return Q > 0.05
end

"""
    magnification_factor_sway_Q(Q::Real) -> Float64

Calculate sway magnification factor δs using stability index Q method.
Per ACI 318-19 (6.6.4.6.2a).

δs = 1 / (1 - Q) ≥ 1.0

This method requires stability index Q from drift analysis.
Valid when δs ≤ 1.5; if δs > 1.5, use second-order analysis.

# Arguments
- `Q`: Story stability index

# Returns
- δs: Sway magnification factor
"""
function magnification_factor_sway_Q(Q::Real)
    if Q ≥ 1.0
        return Inf  # Story is unstable
    end
    
    δs = 1 / (1 - Q)
    
    if δs > 1.5
        @warn "δs = $δs > 1.5; ACI 318-19 recommends second-order analysis"
    end
    
    return max(δs, 1.0)
end

"""
    effective_stiffness_sway(section, mat; βds::Real=0.0, method::Symbol=:accurate) -> Float64

Calculate effective flexural stiffness (EI)eff for sway frames.
Per ACI 318-19 (6.6.4.4.4).

# Arguments
- `section`: RC column section
- `mat`: Material properties
- `βds`: Ratio of max sustained shear to max shear in story (typically 0 for wind)
- `method`: `:accurate` (includes steel) or `:simplified`

# Returns
- (EI)eff in kip-in²

# Notes
- For sway frames, βds (not βdns) is used in the denominator
- βds = 0 for pure lateral loads (wind, seismic)
- βds = ratio of sustained lateral load to total lateral load

# Reference
StructurePoint: "Slender Concrete Column Design in Sway Frames"
"""
function effective_stiffness_sway(
    section::RCColumnSection, 
    mat;
    βds::Real = 0.0,
    method::Symbol = :accurate
)
    fc = fc_ksi(mat)
    Es = Es_ksi(mat)
    Ec = Ec_ksi(mat)
    
    b_in = to_inches(section.b)
    h_in = to_inches(section.h)
    Ig = b_in * h_in^3 / 12
    
    if method == :accurate
        Ise = _calc_Ise(section)
        EI_eff = (0.2 * Ec * Ig + Es * Ise) / (1 + βds)
    else
        EI_eff = 0.4 * Ec * Ig / (1 + βds)
    end
    
    return EI_eff
end

"""
    critical_buckling_load_sway(section, mat, geometry; βds::Real=0.0) -> Float64

Calculate critical buckling load Pc for sway frame columns.
Per ACI 318-19 (6.6.4.4.2).

# Arguments
- `section`: RC column section
- `mat`: Material properties  
- `geometry`: Column geometry with Lu, k (k should be sway k ≥ 1.0)
- `βds`: Sustained shear ratio (default 0.0 for wind/seismic)

# Returns
- Pc: Critical buckling load (kip)

# Notes
- For sway frames, use k ≥ 1.0 from alignment charts
- The effective length factor k for sway frames is typically 1.2 to 2.0
"""
function critical_buckling_load_sway(
    section::RCColumnSection,
    mat,
    geometry;
    βds::Real = 0.0
)
    EI_eff = effective_stiffness_sway(section, mat; βds=βds)
    
    Lu_in = geometry.Lu isa Unitful.Length ?
            to_inches(geometry.Lu) :
            geometry.Lu * 39.37
    k = geometry.k
    kLu = k * Lu_in
    
    Pc = π^2 * EI_eff / kLu^2
    return Pc
end

"""
    magnify_moment_sway_complete(
        section, mat, geometry,
        Pu, M1ns, M2ns, M1s, M2s;
        story::Union{Nothing, StoryProperties}=nothing,
        βds::Real=0.0, βdns::Real=0.6,
        transverse_load::Bool=false
    ) -> NamedTuple

Complete sway frame moment magnification per ACI 318-19 Sections 6.6.4.5 and 6.6.4.6.

This implements the full procedure from StructurePoint design examples:
1. Calculate δs (sway magnification at column ends)
2. Magnify sway moments: M = Mns + δs × Ms
3. Check slenderness along column length (additional δns magnification)

# Arguments
- `section`: RC column section
- `mat`: Material properties
- `geometry`: Column geometry (Lu, k for sway frame, braced=false)
- `Pu`: Factored axial load (kip)
- `M1ns, M2ns`: Non-sway moments at ends 1 and 2 (kip-ft)
- `M1s, M2s`: Sway moments at ends 1 and 2 (kip-ft)
- `story`: Story properties for δs calculation (optional, uses ΣPu/ΣPc if provided)
- `βds`: Sustained shear ratio for sway stiffness (default 0.0 for wind)
- `βdns`: Sustained load ratio for non-sway stiffness (default 0.6)
- `transverse_load`: Whether transverse loads exist between supports

# Returns
NamedTuple with:
- `M1`: Final magnified moment at end 1 (kip-ft)
- `M2`: Final magnified moment at end 2 (kip-ft)
- `Mc`: Design moment (max of M1, M2, and slenderness check) (kip-ft)
- `δs`: Sway magnification factor
- `δns`: Non-sway magnification factor (for along-length check)
- `Q`: Stability index (if story provided)
- `sway_magnified`: Whether sway magnification was applied
- `length_magnified`: Whether along-length magnification was applied

# Reference
StructurePoint: "Slender Concrete Column Design in Sway Frames - Moment 
Magnification Method (ACI 318-19)"
"""
function magnify_moment_sway_complete(
    section::RCColumnSection,
    mat,
    geometry,
    Pu::Real,
    M1ns::Real, M2ns::Real,
    M1s::Real, M2s::Real;
    story::Union{Nothing, StoryProperties} = nothing,
    βds::Real = 0.0,
    βdns::Real = 0.6,
    transverse_load::Bool = false
)
    h_in = to_inches(section.h)
    
    # =========================================================================
    # Step 1: Calculate δs (sway magnification at ends)
    # Per ACI 318-19 (6.6.4.6.2)
    # =========================================================================
    Q = NaN
    
    if !isnothing(story)
        # Method (a): Use Q index
        Q = stability_index(story)
        δs = magnification_factor_sway_Q(Q)
        
        # Alternative: Method (b) using ΣPu/ΣPc
        # This provides a check
        δs_check = magnification_factor_sway(story.ΣPu, story.ΣPc)
    else
        # Simplified: assume story data not available, use conservative δs = 1.0
        # In practice, story properties should be provided
        δs = 1.0
        @warn "No story properties provided; using δs = 1.0 (conservative)"
    end
    
    # Check δs limit
    if δs > 1.5 && isfinite(δs)
        @warn "δs = $(round(δs, digits=3)) > 1.5; ACI recommends second-order analysis"
    end
    
    # =========================================================================
    # Step 2: Magnify moments at column ends
    # Per ACI 318-19 (6.6.4.6.1): M = Mns + δs × Ms
    # =========================================================================
    M1 = M1ns + δs * M1s
    M2 = M2ns + δs * M2s
    
    sway_magnified = δs > 1.0
    
    # =========================================================================
    # Step 3: Check slenderness along column length
    # Per ACI 318-19 (6.6.4.6.4): Use non-sway procedure on magnified moments
    # =========================================================================
    # Determine if slenderness check is needed
    # Use braced frame limits with M1, M2 from step 2
    
    # For along-length check, use non-sway k (typically 1.0 for braced ends)
    # Create a modified geometry with k = 1.0 for the along-length check
    k_nonsway = 1.0  # For members braced against sidesway (after sway magnification)
    
    # Calculate slenderness ratio for non-sway check
    h_in = to_inches(section.h)
    r_in = 0.3 * h_in
    Lu_in = geometry.Lu isa Unitful.Length ?
            to_inches(geometry.Lu) :
            geometry.Lu * 39.37
    
    λ = k_nonsway * Lu_in / r_in
    
    # Check if along-length magnification is needed
    M_ratio = M2 ≈ 0 ? 0.0 : M1 / M2
    limit = min(34 - 12 * M_ratio, 40)
    
    length_magnified = false
    δns = 1.0
    Mc = max(abs(M1), abs(M2))
    
    if λ > limit
        # Need to magnify for P-δ effects along length
        # Use non-sway procedure per ACI 6.6.4.5
        
        # Create temporary geometry for non-sway check
        geometry_nonsway = (Lu = geometry.Lu, k = k_nonsway, braced = true)
        
        # Calculate Pc for non-sway
        Pc = critical_buckling_load(section, mat, geometry_nonsway; βdns=βdns)
        
        # Calculate Cm using magnified moments
        Cm = calc_Cm(M1, M2; transverse_load=transverse_load)
        
        # Calculate δns
        δns = magnification_factor_nonsway(Pu, Pc; Cm=Cm)
        
        # Final design moment (ACI 6.6.4.6.4)
        M_min = minimum_moment(Pu, h_in)
        Mc = max(δns * max(abs(M1), abs(M2)), M_min)
        
        length_magnified = δns > 1.0
    end
    
    return (
        M1 = M1,
        M2 = M2,
        Mc = Mc,
        δs = δs,
        δns = δns,
        Q = Q,
        sway_magnified = sway_magnified,
        length_magnified = length_magnified
    )
end

# ==============================================================================
# Circular Column Sway Support
# ==============================================================================

"""
    effective_stiffness_sway(section::RCCircularSection, mat; βds=0.0, method=:accurate)

Calculate effective flexural stiffness for circular columns in sway frames.
"""
function effective_stiffness_sway(
    section::RCCircularSection, 
    mat;
    βds::Real = 0.0,
    method::Symbol = :accurate
)
    fc = fc_ksi(mat)
    Es = Es_ksi(mat)
    Ec = Ec_ksi(mat)
    
    D_in = to_inches(section.D)
    Ig = π * D_in^4 / 64
    
    if method == :accurate
        Ise = _calc_Ise(section)
        EI_eff = (0.2 * Ec * Ig + Es * Ise) / (1 + βds)
    else
        EI_eff = 0.4 * Ec * Ig / (1 + βds)
    end
    
    return EI_eff
end

"""
    critical_buckling_load_sway(section::RCCircularSection, mat, geometry; βds=0.0)

Calculate critical buckling load for circular columns in sway frames.
"""
function critical_buckling_load_sway(
    section::RCCircularSection,
    mat,
    geometry;
    βds::Real = 0.0
)
    EI_eff = effective_stiffness_sway(section, mat; βds=βds)
    
    Lu_in = geometry.Lu isa Unitful.Length ?
            to_inches(geometry.Lu) :
            geometry.Lu * 39.37
    k = geometry.k
    kLu = k * Lu_in
    
    Pc = π^2 * EI_eff / kLu^2
    return Pc
end

"""
    magnify_moment_sway_complete(section::RCCircularSection, ...)

Complete sway frame moment magnification for circular columns.
"""
function magnify_moment_sway_complete(
    section::RCCircularSection,
    mat,
    geometry,
    Pu::Real,
    M1ns::Real, M2ns::Real,
    M1s::Real, M2s::Real;
    story::Union{Nothing, StoryProperties} = nothing,
    βds::Real = 0.0,
    βdns::Real = 0.6,
    transverse_load::Bool = false
)
    D_in = to_inches(section.D)
    r_in = 0.25 * D_in
    
    # Step 1: Calculate δs
    Q = NaN
    if !isnothing(story)
        Q = stability_index(story)
        δs = magnification_factor_sway_Q(Q)
    else
        δs = 1.0
    end
    
    # Step 2: Magnify moments at ends
    M1 = M1ns + δs * M1s
    M2 = M2ns + δs * M2s
    sway_magnified = δs > 1.0
    
    # Step 3: Check along-length slenderness
    k_nonsway = 1.0
    Lu_in = geometry.Lu isa Unitful.Length ?
            to_inches(geometry.Lu) :
            geometry.Lu * 39.37
    
    λ = k_nonsway * Lu_in / r_in
    M_ratio = M2 ≈ 0 ? 0.0 : M1 / M2
    limit = min(34 - 12 * M_ratio, 40)
    
    length_magnified = false
    δns = 1.0
    Mc = max(abs(M1), abs(M2))
    
    if λ > limit
        geometry_nonsway = (Lu = geometry.Lu, k = k_nonsway, braced = true)
        Pc = critical_buckling_load(section, mat, geometry_nonsway; βdns=βdns)
        Cm = calc_Cm(M1, M2; transverse_load=transverse_load)
        δns = magnification_factor_nonsway(Pu, Pc; Cm=Cm)
        
        M_min = minimum_moment(Pu, D_in)
        Mc = max(δns * max(abs(M1), abs(M2)), M_min)
        length_magnified = δns > 1.0
    end
    
    return (
        M1 = M1,
        M2 = M2,
        Mc = Mc,
        δs = δs,
        δns = δns,
        Q = Q,
        sway_magnified = sway_magnified,
        length_magnified = length_magnified
    )
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
    D_in = to_inches(section.D)
    r_in = 0.25 * D_in
    
    # Unsupported length - ConcreteMemberGeometry stores Lu in meters or inches
    Lu_in = geometry.Lu isa Unitful.Length ? 
            to_inches(geometry.Lu) : 
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
    # Material properties (using unified extractors)
    fc = fc_ksi(mat)
    Es = Es_ksi(mat)
    Ec = Ec_ksi(mat)
    
    # Gross moment of inertia for circular: Ig = πD⁴/64
    D_in = to_inches(section.D)
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
    D_in = to_inches(section.D)
    centroid = D_in / 2  # Center of circle
    
    Ise = 0.0
    for bar in section.bars
        y_bar = to_inches(bar.y)
        As_bar = to_sqinches(bar.As)
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
            to_inches(geometry.Lu) :
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
    D_in = to_inches(section.D)
    
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
