# ==============================================================================
# ACI 318-19 Column P-M Interaction
# ==============================================================================
# Strain compatibility analysis for reinforced concrete columns
# Reference: ACI 318-19 Chapter 22 (Sectional Strength)

using Unitful

# ==============================================================================
# Material Constants
# ==============================================================================

"""
    beta1(fc_ksi::Real) -> Float64

Whitney stress block factor β₁ per ACI 318-19 Table 22.2.2.4.3.
- β₁ = 0.85 for f'c ≤ 4 ksi
- β₁ = 0.85 - 0.05(f'c - 4) for 4 < f'c < 8 ksi
- β₁ = 0.65 for f'c ≥ 8 ksi
"""
function beta1(fc_ksi::Real)
    if fc_ksi ≤ 4.0
        return 0.85
    elseif fc_ksi ≥ 8.0
        return 0.65
    else
        return 0.85 - 0.05 * (fc_ksi - 4.0)
    end
end

# ==============================================================================
# Strain Compatibility Core
# ==============================================================================

"""
    calculate_steel_strain(y_bar::Real, c::Real, h::Real, εcu::Real) -> Float64

Calculate steel strain at bar location using similar triangles.

# Arguments
- `y_bar`: Distance from compression face to bar (in)
- `c`: Neutral axis depth from compression face (in)
- `h`: Total section depth (in) [unused, kept for clarity]
- `εcu`: Concrete ultimate strain (typically 0.003)

# Returns
- Steel strain (positive = tension, negative = compression)

Per ACI 318-19 strain compatibility (22.2.1.2):
- Linear strain distribution assumed
- εcu = 0.003 at extreme compression fiber
"""
function calculate_steel_strain(y_bar::Real, c::Real, h::Real, εcu::Real)
    # Strain = εcu * (distance from NA) / c
    # If y_bar < c: compression (negative strain)
    # If y_bar > c: tension (positive strain)
    return εcu * (y_bar - c) / c
end

"""
    calculate_steel_stress(εs::Real, fy_ksi::Real, Es_ksi::Real) -> Float64

Calculate steel stress from strain, limited to fy.

# Arguments
- `εs`: Steel strain (positive = tension)
- `fy_ksi`: Yield strength (ksi)
- `Es_ksi`: Elastic modulus (ksi)

# Returns
- Steel stress (ksi), positive = tension
"""
function calculate_steel_stress(εs::Real, fy_ksi::Real, Es_ksi::Real)
    fs = Es_ksi * εs
    # Limit to ± fy (elastic-perfectly-plastic)
    return clamp(fs, -fy_ksi, fy_ksi)
end

"""
    calculate_PM_at_c(section::RCColumnSection, mat, c_in::Real) -> NamedTuple

Calculate nominal (Pn, Mn) capacity at a given neutral axis depth c.

# Arguments
- `section`: RCColumnSection with bar positions
- `mat`: Concrete material with fc, fy, Es, εcu properties
- `c_in`: Neutral axis depth from compression face (inches)

# Returns
NamedTuple with:
- `Pn`: Nominal axial capacity (kip), positive = compression
- `Mn`: Nominal moment capacity (kip-ft)
- `εt`: Strain in extreme tension steel (for φ calculation)
- `c`: Neutral axis depth used (in)

# Notes
Uses Whitney rectangular stress block per ACI 318-19 Section 22.2.2.4.
Sign convention: compression positive for forces, tension positive for strain.

Coordinate system:
- Compression face at TOP (y = h)
- Tension face at BOTTOM (y = 0)
- Bars stored with (x, y) from bottom-left corner
- d = distance from compression face to extreme tension steel
"""
function calculate_PM_at_c(section::RCColumnSection, mat, c_in::Real)
    # Extract material properties (assume ksi units)
    fc = _get_fc_ksi(mat)
    fy = _get_fy_ksi(mat)
    Es = _get_Es_ksi(mat)
    εcu = _get_εcu(mat)
    
    # Section dimensions (stored in inches)
    b = ustrip(u"inch", section.b)
    h = ustrip(u"inch", section.h)
    
    # Whitney stress block
    β₁ = beta1(fc)
    a = β₁ * c_in  # Stress block depth
    
    # Limit stress block to section depth
    a_eff = min(a, h)
    
    # Concrete compression force over gross area (positive)
    # Cc = 0.85 * f'c * b * a
    Cc = 0.85 * fc * b * a_eff  # kip
    
    # Concrete force location from compression face (top)
    y_Cc_from_top = a_eff / 2
    
    # Steel forces - must account for displaced concrete
    # Per ACI: for bars within compression zone, net force = As * (fs - 0.85*f'c)
    Fs_total = 0.0  # Total steel force contribution (positive = compression)
    Ms_total = 0.0  # Steel moment about section centroid
    
    centroid_from_top = h / 2  # Section centroid from compression face
    
    # Concrete stress in compression zone
    fc_stress = 0.85 * fc  # ksi
    
    for bar in section.bars
        # Bar y is from bottom → distance from TOP = h - bar.y
        y_bar_from_top = h - ustrip(u"inch", bar.y)
        As_bar = ustrip(u"inch^2", bar.As)
        
        # Steel strain at this bar
        εs = calculate_steel_strain(y_bar_from_top, c_in, h, εcu)
        
        # Steel stress (positive = tension, negative = compression)
        fs = calculate_steel_stress(εs, fy, Es)
        
        # Check if bar is within compression zone (Whitney stress block)
        in_compression_zone = y_bar_from_top < a_eff
        
        # Steel force contribution (compression positive):
        # - Pure steel force: -fs * As (fs>0 tension → negative force; fs<0 compression → positive)
        # - If bar in compression zone: Cc over-counts concrete by 0.85*f'c*As
        #   Must SUBTRACT this displaced concrete from total P
        #   Net = (-fs * As) - (0.85*f'c * As) = -As * (fs + 0.85*f'c)
        
        if in_compression_zone
            # Bar in compression zone: steel force minus displaced concrete
            Fs = -As_bar * (fs + fc_stress)
        else
            # Bar outside compression zone: just steel force
            Fs = -fs * As_bar
        end
        
        Fs_total += Fs
        
        # Moment about section centroid
        arm = centroid_from_top - y_bar_from_top  # positive if bar closer to compression face
        Ms_total += Fs * arm  # kip-in
    end
    
    # Extreme tension strain: bar furthest from compression face
    # bar.y = distance from bottom, small y = near tension face (bottom)
    y_tension_bar_from_bottom = minimum(ustrip(u"inch", bar.y) for bar in section.bars)
    y_tension_from_top = h - y_tension_bar_from_bottom  # = d
    εt = calculate_steel_strain(y_tension_from_top, c_in, h, εcu)
    
    # Total axial force (positive = compression)
    Pn = Cc + Fs_total  # kip
    
    # Total moment about centroid
    Mc = Cc * (centroid_from_top - y_Cc_from_top)  # kip-in
    Mn_in = Mc + Ms_total  # kip-in
    Mn = Mn_in / 12.0  # kip-ft
    
    return (Pn = Pn, Mn = abs(Mn), εt = εt, c = c_in)
end

# ==============================================================================
# Material Property Extractors (handle different input types)
# ==============================================================================

# For NamedTuple test data
_get_fc_ksi(mat::NamedTuple) = mat.fc
_get_fy_ksi(mat::NamedTuple) = mat.fy
_get_Es_ksi(mat::NamedTuple) = mat.Es
_get_εcu(mat::NamedTuple) = hasproperty(mat, :εcu) ? mat.εcu : 0.003

# For Concrete material type (when available)
# _get_fc_ksi(mat::Concrete) = ustrip(u"ksi", mat.fc)
# etc.

# ==============================================================================
# Helper: Find c for a given εt
# ==============================================================================

"""
    c_from_εt(εt::Real, d::Real, εcu::Real=0.003) -> Float64

Calculate neutral axis depth c for a given extreme tension steel strain.

# Arguments
- `εt`: Target strain in extreme tension steel
- `d`: Depth to extreme tension steel from compression face (in)
- `εcu`: Concrete ultimate strain

# Returns
- Neutral axis depth c (in)

From similar triangles: εcu/c = (εcu + εt)/(d)
→ c = εcu * d / (εcu + εt)
"""
function c_from_εt(εt::Real, d::Real, εcu::Real=0.003)
    return εcu * d / (εcu + εt)
end

# ==============================================================================
# Pure Compression Capacity (P0)
# ==============================================================================

"""
    pure_compression_capacity(section::RCColumnSection, mat) -> Float64

Calculate pure axial compression capacity P0 per ACI 318-19.

P0 = 0.85 * f'c * (Ag - As) + fy * As

Note: This is the theoretical maximum. ACI 22.4.2 requires using:
- Pn,max = 0.80 * P0 for tied columns
- Pn,max = 0.85 * P0 for spiral columns
"""
function pure_compression_capacity(section::RCColumnSection, mat)
    fc = _get_fc_ksi(mat)
    fy = _get_fy_ksi(mat)
    
    Ag = ustrip(u"inch^2", section.Ag)
    As = ustrip(u"inch^2", section.As_total)
    
    P0 = 0.85 * fc * (Ag - As) + fy * As
    return P0  # kip
end

"""
    max_compression_capacity(section::RCColumnSection, mat) -> Float64

Calculate maximum permitted compression per ACI 318-19 Section 22.4.2.

Pn,max = α * P0, where:
- α = 0.80 for tied columns
- α = 0.85 for spiral columns
"""
function max_compression_capacity(section::RCColumnSection, mat)
    P0 = pure_compression_capacity(section, mat)
    α = section.tie_type == :spiral ? 0.85 : 0.80
    return α * P0
end

# ==============================================================================
# Strength Reduction Factor (φ)
# ==============================================================================

"""
    phi_factor(εt::Real, tie_type::Symbol=:tied; fy_ksi::Real=60.0) -> Float64

Calculate strength reduction factor φ per ACI 318-19 Table 21.2.2.

# Arguments
- `εt`: Net tensile strain in extreme tension steel
- `tie_type`: :tied or :spiral
- `fy_ksi`: Yield strength (for calculating εy)

# Returns
- φ factor for moment/axial design

# ACI 318-19 Table 21.2.2:
For Grade 60 steel (εy = 0.00207):
- εt ≤ εy: Compression controlled
  - Tied: φ = 0.65
  - Spiral: φ = 0.75
- εy < εt < (εy + 0.003): Transition zone
  - Tied: φ = 0.65 + 0.25(εt - εy)/0.003
  - Spiral: φ = 0.75 + 0.15(εt - εy)/0.003
- εt ≥ (εy + 0.003): Tension controlled
  - φ = 0.90
"""
function phi_factor(εt::Real, tie_type::Symbol=:tied; fy_ksi::Real=60.0)
    # Yield strain (ACI 318-19 uses modular ratio)
    Es = 29000.0  # ksi
    εy = fy_ksi / Es
    
    # Tension-controlled limit
    εt_limit = εy + 0.003
    
    if εt ≤ εy
        # Compression controlled
        return tie_type == :spiral ? 0.75 : 0.65
    elseif εt ≥ εt_limit
        # Tension controlled
        return 0.90
    else
        # Transition zone
        if tie_type == :spiral
            return 0.75 + 0.15 * (εt - εy) / 0.003
        else
            return 0.65 + 0.25 * (εt - εy) / 0.003
        end
    end
end

"""
    calculate_phi_PM_at_c(section::RCColumnSection, mat, c_in::Real) -> NamedTuple

Calculate factored (φPn, φMn) capacity at a given neutral axis depth.

# Returns
NamedTuple with:
- `Pn`: Nominal axial capacity (kip)
- `Mn`: Nominal moment capacity (kip-ft)
- `φPn`: Factored axial capacity (kip)
- `φMn`: Factored moment capacity (kip-ft)
- `φ`: Strength reduction factor
- `εt`: Strain in extreme tension steel
- `c`: Neutral axis depth (in)
"""
function calculate_phi_PM_at_c(section::RCColumnSection, mat, c_in::Real)
    # Get nominal values
    result = calculate_PM_at_c(section, mat, c_in)
    
    # Calculate φ based on tension strain
    fy = _get_fy_ksi(mat)
    φ = phi_factor(result.εt, section.tie_type; fy_ksi=fy)
    
    # Factored capacities
    φPn = φ * result.Pn
    φMn = φ * result.Mn
    
    return (
        Pn = result.Pn,
        Mn = result.Mn,
        φPn = φPn,
        φMn = φMn,
        φ = φ,
        εt = result.εt,
        c = result.c
    )
end

# ==============================================================================
# P-M Interaction Diagram Generation
# ==============================================================================

"""
    PMDiagramPoint

A single point on the P-M interaction diagram.
"""
struct PMDiagramPoint
    c::Float64       # Neutral axis depth (in)
    εt::Float64      # Extreme tension steel strain
    Pn::Float64      # Nominal axial capacity (kip)
    Mn::Float64      # Nominal moment capacity (kip-ft)
    φ::Float64       # Strength reduction factor
    φPn::Float64     # Factored axial capacity (kip)
    φMn::Float64     # Factored moment capacity (kip-ft)
    label::String    # Control point label (if any)
end

"""
    PMInteractionDiagram

Complete P-M interaction diagram for a column section.

# Fields
- `section`: RCColumnSection used to generate the diagram
- `mat`: Material properties
- `points`: Vector of PMDiagramPoint (ordered from compression to tension)
- `control_points`: Dict mapping control point names to indices
"""
struct PMInteractionDiagram
    section::RCColumnSection
    mat::NamedTuple
    points::Vector{PMDiagramPoint}
    control_points::Dict{Symbol, Int}
end

"""
    generate_PM_diagram(section::RCColumnSection, mat; n_intermediate::Int=20)

Generate a complete P-M interaction diagram per ACI 318-19.

# Arguments
- `section`: RC column section
- `mat`: Material properties (fc, fy, Es, εcu)
- `n_intermediate`: Number of intermediate points between control points (default 20)

# Returns
PMInteractionDiagram with:
- 7 standard ACI control points (StructurePoint methodology)
- Optional intermediate points for smooth curves

# Control Points (per StructurePoint Design Example)
1. Pure compression (P₀)
2. fs = 0 (c = d, zero tension strain)
3. fs = 0.5fy
4. Balanced (fs = fy)
5. Tension controlled (εt = εy + 0.003)
6. Pure bending (Pn ≈ 0)
7. Pure tension

# Reference
StructurePoint: "Interaction Diagram - Tied Reinforced Concrete Column 
Design Strength (ACI 318-19)"
"""
function generate_PM_diagram(section::RCColumnSection, mat; n_intermediate::Int=20)
    # Material properties
    fc = _get_fc_ksi(mat)
    fy = _get_fy_ksi(mat)
    Es = _get_Es_ksi(mat)
    εcu = _get_εcu(mat)
    εy = fy / Es
    
    # Section properties
    h = ustrip(u"inch", section.h)
    d = ustrip(u"inch", effective_depth(section))
    
    points = PMDiagramPoint[]
    control_indices = Dict{Symbol, Int}()
    
    # =========================================================================
    # Control Point 1: Pure Compression (P₀)
    # Very large c → entire section in compression
    # =========================================================================
    P0 = pure_compression_capacity(section, mat)
    φ_comp = section.tie_type == :spiral ? 0.75 : 0.65
    push!(points, PMDiagramPoint(
        Inf, -εy,  # Compression throughout
        P0, 0.0,
        φ_comp, φ_comp * P0, 0.0,
        "P₀ (Pure Compression)"
    ))
    control_indices[:pure_compression] = length(points)
    
    # =========================================================================
    # Control Point 2: Maximum Allowable Compression
    # Pn,max = α × P₀ (α = 0.80 for tied, 0.85 for spiral)
    # This is a horizontal cutoff, not a computed point
    # We add it at the same moment as the very large c case
    # =========================================================================
    α = section.tie_type == :spiral ? 0.85 : 0.80
    Pn_max = α * P0
    # Find c that gives this Pn (approximately)
    c_large = 5.0 * h  # Large c for essentially pure compression
    result_large = calculate_phi_PM_at_c(section, mat, c_large)
    push!(points, PMDiagramPoint(
        c_large, result_large.εt,
        Pn_max, result_large.Mn,
        φ_comp, φ_comp * Pn_max, φ_comp * result_large.Mn,
        "Pn,max (Allowable Compression)"
    ))
    control_indices[:max_compression] = length(points)
    
    # =========================================================================
    # Control Point 3: Zero Tension Strain (fs = 0, c = d)
    # Marks transition for lap splice requirements
    # =========================================================================
    c_fs0 = d
    result_fs0 = calculate_phi_PM_at_c(section, mat, c_fs0)
    push!(points, PMDiagramPoint(
        c_fs0, result_fs0.εt,
        result_fs0.Pn, result_fs0.Mn,
        result_fs0.φ, result_fs0.φPn, result_fs0.φMn,
        "fs = 0"
    ))
    control_indices[:fs_zero] = length(points)
    
    # =========================================================================
    # Control Point 4: Half Yield (fs = 0.5fy, εt = 0.5εy)
    # =========================================================================
    εt_half = 0.5 * εy
    c_half = c_from_εt(εt_half, d, εcu)
    result_half = calculate_phi_PM_at_c(section, mat, c_half)
    push!(points, PMDiagramPoint(
        c_half, result_half.εt,
        result_half.Pn, result_half.Mn,
        result_half.φ, result_half.φPn, result_half.φMn,
        "fs = 0.5fy"
    ))
    control_indices[:fs_half_fy] = length(points)
    
    # =========================================================================
    # Control Point 5: Balanced (fs = fy, εt = εy)
    # Marks compression-controlled limit
    # =========================================================================
    c_balanced = c_from_εt(εy, d, εcu)
    result_balanced = calculate_phi_PM_at_c(section, mat, c_balanced)
    push!(points, PMDiagramPoint(
        c_balanced, result_balanced.εt,
        result_balanced.Pn, result_balanced.Mn,
        result_balanced.φ, result_balanced.φPn, result_balanced.φMn,
        "Balanced (fs = fy)"
    ))
    control_indices[:balanced] = length(points)
    
    # =========================================================================
    # Control Point 6: Tension Controlled (εt = εy + 0.003)
    # Marks tension-controlled limit (φ = 0.90)
    # =========================================================================
    εt_tension = εy + 0.003
    c_tension = c_from_εt(εt_tension, d, εcu)
    result_tension = calculate_phi_PM_at_c(section, mat, c_tension)
    push!(points, PMDiagramPoint(
        c_tension, result_tension.εt,
        result_tension.Pn, result_tension.Mn,
        result_tension.φ, result_tension.φPn, result_tension.φMn,
        "Tension Controlled (εt = εy + 0.003)"
    ))
    control_indices[:tension_controlled] = length(points)
    
    # =========================================================================
    # Control Point 7: Pure Bending (Pn ≈ 0)
    # Requires iteration to find c where Pn = 0
    # =========================================================================
    c_pure_m = _find_pure_bending_c(section, mat)
    result_pure_m = calculate_phi_PM_at_c(section, mat, c_pure_m)
    push!(points, PMDiagramPoint(
        c_pure_m, result_pure_m.εt,
        result_pure_m.Pn, result_pure_m.Mn,
        result_pure_m.φ, result_pure_m.φPn, result_pure_m.φMn,
        "Pure Bending"
    ))
    control_indices[:pure_bending] = length(points)
    
    # =========================================================================
    # Control Point 8: Pure Tension
    # All steel in tension at yield
    # =========================================================================
    As_total = ustrip(u"inch^2", section.As_total)
    Pnt = -fy * As_total  # Tension negative
    push!(points, PMDiagramPoint(
        -Inf, Inf,  # All tension
        Pnt, 0.0,
        0.90, 0.90 * Pnt, 0.0,
        "Pure Tension"
    ))
    control_indices[:pure_tension] = length(points)
    
    # =========================================================================
    # Add intermediate points for smooth curve (optional)
    # =========================================================================
    if n_intermediate > 0
        points = _add_intermediate_points(section, mat, points, n_intermediate)
    end
    
    return PMInteractionDiagram(section, mat, points, control_indices)
end

"""Find c value for pure bending (Pn ≈ 0) using bisection."""
function _find_pure_bending_c(section::RCColumnSection, mat; tol::Float64=0.1)
    h = ustrip(u"inch", section.h)
    d = ustrip(u"inch", effective_depth(section))
    
    # Bracket: c between small value and balanced point
    c_low = 0.5  # Small c → tension dominates
    c_high = d   # At d, compression still dominates
    
    # Check that we have a valid bracket
    result_low = calculate_PM_at_c(section, mat, c_low)
    result_high = calculate_PM_at_c(section, mat, c_high)
    
    if result_low.Pn > 0 && result_high.Pn > 0
        # Both positive, try smaller c_low
        c_low = 0.1
        result_low = calculate_PM_at_c(section, mat, c_low)
    end
    
    # Bisection
    for _ in 1:50
        c_mid = (c_low + c_high) / 2
        result_mid = calculate_PM_at_c(section, mat, c_mid)
        
        if abs(result_mid.Pn) < tol
            return c_mid
        elseif result_mid.Pn > 0
            c_high = c_mid
        else
            c_low = c_mid
        end
    end
    
    # Return best guess
    return (c_low + c_high) / 2
end

"""Add intermediate points between control points for smooth curve."""
function _add_intermediate_points(
    section::RCColumnSection, 
    mat, 
    control_points::Vector{PMDiagramPoint},
    n_per_segment::Int
)
    # Extract c values from control points (skip Inf values)
    c_values = Float64[]
    for pt in control_points
        if isfinite(pt.c) && pt.c > 0
            push!(c_values, pt.c)
        end
    end
    sort!(c_values, rev=true)  # Largest c first (compression end)
    
    # Generate intermediate c values
    all_points = PMDiagramPoint[]
    
    # Add pure compression point
    push!(all_points, control_points[1])
    push!(all_points, control_points[2])
    
    # Sweep c from large to small
    c_max = maximum(c_values)
    c_min = minimum(c_values)
    
    c_sweep = range(c_max, c_min, length=n_per_segment + 2)[2:end-1]
    
    for c in c_sweep
        result = calculate_phi_PM_at_c(section, mat, c)
        push!(all_points, PMDiagramPoint(
            c, result.εt,
            result.Pn, result.Mn,
            result.φ, result.φPn, result.φMn,
            ""  # No label for intermediate points
        ))
    end
    
    # Add remaining control points (pure bending, pure tension)
    push!(all_points, control_points[end-1])  # Pure bending
    push!(all_points, control_points[end])    # Pure tension
    
    return all_points
end

# ==============================================================================
# Diagram Access Functions
# ==============================================================================

"""Get nominal P-M points as (Pn, Mn) arrays."""
function get_nominal_curve(diagram::PMInteractionDiagram)
    Pn = [pt.Pn for pt in diagram.points]
    Mn = [pt.Mn for pt in diagram.points]
    return (Pn=Pn, Mn=Mn)
end

"""Get factored P-M points as (φPn, φMn) arrays."""
function get_factored_curve(diagram::PMInteractionDiagram)
    φPn = [pt.φPn for pt in diagram.points]
    φMn = [pt.φMn for pt in diagram.points]
    return (φPn=φPn, φMn=φMn)
end

"""Get control points only (labeled points)."""
function get_control_points(diagram::PMInteractionDiagram)
    return filter(pt -> !isempty(pt.label), diagram.points)
end

"""Get a specific control point by name."""
function get_control_point(diagram::PMInteractionDiagram, name::Symbol)
    idx = get(diagram.control_points, name, nothing)
    if isnothing(idx)
        error("Control point :$name not found. Available: $(keys(diagram.control_points))")
    end
    return diagram.points[idx]
end

# ==============================================================================
# Capacity Check Functions
# ==============================================================================

"""
    check_PM_capacity(diagram::PMInteractionDiagram, Pu::Real, Mu::Real) -> NamedTuple

Check if demand (Pu, Mu) is within the factored P-M capacity envelope.

# Arguments
- `diagram`: PMInteractionDiagram for the section
- `Pu`: Factored axial demand (kip), positive = compression
- `Mu`: Factored moment demand (kip-ft), absolute value

# Returns
NamedTuple with:
- `adequate`: Bool - true if demand is within capacity
- `utilization`: Float64 - demand/capacity ratio (1.0 = at limit)
- `φPn_at_Mu`: Float64 - factored axial capacity at the given moment
- `φMn_at_Pu`: Float64 - factored moment capacity at the given axial load
- `governing`: Symbol - which limit governs (:axial, :moment, :combined)

# Notes
Uses linear interpolation between diagram points.
"""
function check_PM_capacity(diagram::PMInteractionDiagram, Pu::Real, Mu::Real)
    Mu = abs(Mu)  # Ensure positive moment
    
    # Get factored curve
    curve = get_factored_curve(diagram)
    φPn = curve.φPn
    φMn = curve.φMn
    
    # Find φMn capacity at the given Pu by interpolation
    φMn_at_Pu = _interpolate_moment_at_P(φPn, φMn, Pu)
    
    # Find φPn capacity at the given Mu by interpolation
    φPn_at_Mu = _interpolate_axial_at_M(φPn, φMn, Mu)
    
    # Calculate utilization
    # For P-M interaction, the radial distance ratio is a good measure
    if φMn_at_Pu > 0 && abs(φPn_at_Mu) > 0
        # Combined check: ratio of demand to capacity at constant P/M ratio
        utilization_M = Mu / max(φMn_at_Pu, 1e-6)
        utilization_P = abs(Pu) / max(abs(φPn_at_Mu), 1e-6)
        utilization = max(utilization_M, utilization_P)
        
        if utilization_M > utilization_P
            governing = :moment
        elseif utilization_P > utilization_M
            governing = :axial
        else
            governing = :combined
        end
    elseif φMn_at_Pu > 0
        utilization = Mu / φMn_at_Pu
        governing = :moment
    else
        utilization = 1.5  # Over capacity
        governing = :combined
    end
    
    adequate = utilization ≤ 1.0
    
    return (
        adequate = adequate,
        utilization = utilization,
        φMn_at_Pu = φMn_at_Pu,
        φPn_at_Mu = φPn_at_Mu,
        governing = governing
    )
end

"""
    capacity_at_axial(diagram::PMInteractionDiagram, Pu::Real) -> Float64

Get factored moment capacity φMn at a given factored axial load Pu.

# Arguments
- `diagram`: PMInteractionDiagram
- `Pu`: Factored axial demand (kip), positive = compression

# Returns
- φMn: Factored moment capacity (kip-ft) at the given Pu
"""
function capacity_at_axial(diagram::PMInteractionDiagram, Pu::Real)
    curve = get_factored_curve(diagram)
    return _interpolate_moment_at_P(curve.φPn, curve.φMn, Pu)
end

"""
    capacity_at_moment(diagram::PMInteractionDiagram, Mu::Real) -> Float64

Get factored axial capacity φPn at a given factored moment Mu.

# Arguments
- `diagram`: PMInteractionDiagram  
- `Mu`: Factored moment demand (kip-ft)

# Returns
- φPn: Factored axial capacity (kip) at the given Mu
"""
function capacity_at_moment(diagram::PMInteractionDiagram, Mu::Real)
    curve = get_factored_curve(diagram)
    return _interpolate_axial_at_M(curve.φPn, curve.φMn, abs(Mu))
end

"""
    utilization_ratio(diagram::PMInteractionDiagram, Pu::Real, Mu::Real) -> Float64

Calculate the utilization ratio for a demand point (Pu, Mu).

# Returns
- Ratio ≤ 1.0 means adequate capacity
- Ratio > 1.0 means demand exceeds capacity
"""
function utilization_ratio(diagram::PMInteractionDiagram, Pu::Real, Mu::Real)
    result = check_PM_capacity(diagram, Pu, Mu)
    return result.utilization
end

# ==============================================================================
# Interpolation Helpers
# ==============================================================================

"""Interpolate moment capacity at a given axial load."""
function _interpolate_moment_at_P(φPn::Vector, φMn::Vector, Pu::Real)
    n = length(φPn)
    
    # Handle edge cases
    if Pu ≥ maximum(φPn)
        # At or above max compression - find the φMn at max φPn
        idx = argmax(φPn)
        return φMn[idx]
    elseif Pu ≤ minimum(φPn)
        # At or below max tension
        idx = argmin(φPn)
        return φMn[idx]
    end
    
    # Find bracketing points
    # The curve goes from high P (compression) to low P (tension)
    for i in 1:(n-1)
        P1, P2 = φPn[i], φPn[i+1]
        M1, M2 = φMn[i], φMn[i+1]
        
        # Check if Pu is between these points
        if (P1 ≥ Pu ≥ P2) || (P2 ≥ Pu ≥ P1)
            # Linear interpolation
            if abs(P1 - P2) < 1e-10
                return (M1 + M2) / 2
            end
            t = (Pu - P1) / (P2 - P1)
            return M1 + t * (M2 - M1)
        end
    end
    
    # Fallback: return closest point
    idx = argmin(abs.(φPn .- Pu))
    return φMn[idx]
end

"""Interpolate axial capacity at a given moment."""
function _interpolate_axial_at_M(φPn::Vector, φMn::Vector, Mu::Real)
    n = length(φMn)
    
    # Handle edge cases
    if Mu ≤ minimum(φMn)
        # At or below minimum moment (pure axial cases)
        # Return max compression capacity
        return maximum(φPn)
    end
    
    max_M = maximum(φMn)
    if Mu ≥ max_M
        # Beyond the envelope - interpolate along the tension side
        # Find the point with maximum moment and return its P
        idx = argmax(φMn)
        return φPn[idx]
    end
    
    # The P-M curve is not single-valued in M (moment increases then decreases)
    # Find all points where M ≈ Mu and return the max P (conservative for compression)
    matching_P = Float64[]
    for i in 1:(n-1)
        M1, M2 = φMn[i], φMn[i+1]
        P1, P2 = φPn[i], φPn[i+1]
        
        # Check if Mu is between these points
        if (M1 ≤ Mu ≤ M2) || (M2 ≤ Mu ≤ M1)
            if abs(M1 - M2) < 1e-10
                push!(matching_P, (P1 + P2) / 2)
            else
                t = (Mu - M1) / (M2 - M1)
                push!(matching_P, P1 + t * (P2 - P1))
            end
        end
    end
    
    if isempty(matching_P)
        # Fallback: return closest point
        idx = argmin(abs.(φMn .- Mu))
        return φPn[idx]
    end
    
    # Return max P (most conservative for compression check)
    return maximum(matching_P)
end
