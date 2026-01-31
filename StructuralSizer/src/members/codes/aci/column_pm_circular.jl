# ==============================================================================
# ACI 318-19 Circular Column P-M Interaction
# ==============================================================================
# Strain compatibility analysis for circular reinforced concrete columns.
# Reference: StructurePoint "Interaction Diagram - Circular Spiral Reinforced
#            Concrete Column (ACI 318-19)"
# ==============================================================================

"""
    calculate_PM_at_c(section::RCCircularSection, mat, c_in::Real) -> NamedTuple

Calculate nominal (Pn, Mn) capacity for a circular column at a given neutral axis depth c.

# Arguments
- `section`: RCCircularSection with bar positions
- `mat`: Concrete material with fc, fy, Es, εcu properties
- `c_in`: Neutral axis depth from compression face (inches)

# Returns
NamedTuple with:
- `Pn`: Nominal axial capacity (kip), positive = compression
- `Mn`: Nominal moment capacity (kip-ft)
- `εt`: Strain in extreme tension steel (for φ calculation)
- `c`: Neutral axis depth used (in)

# Notes
Uses Whitney stress block with circular segment geometry per ACI 318-19.
Sign convention: compression positive for forces, tension positive for strain.

Coordinate system:
- Compression face at TOP (y = D)
- Tension face at BOTTOM (y = 0)
- Bars stored with (x, y) from bottom-left corner (y from bottom)
- d = distance from compression face to extreme tension steel

# Reference
StructurePoint formulas for circular sections:
- θ = arccos((D/2 - a) / (D/2))
- A_comp = D²/4 × (θπ/180 - sin(θ)cos(θ))  [θ in degrees for SP, radians here]
- ȳ = D³ sin³(θ) / (12 × A_comp)
"""
function calculate_PM_at_c(section::RCCircularSection, mat, c_in::Real)
    # Extract material properties (assume ksi units from mat)
    fc = _get_fc_ksi(mat)
    fy = _get_fy_ksi(mat)
    Es = _get_Es_ksi(mat)
    εcu = _get_εcu(mat)
    
    # Section dimensions (stored in inches)
    D = ustrip(u"inch", section.D)
    
    # Whitney stress block
    β₁ = beta1(fc)
    a = β₁ * c_in  # Stress block depth
    
    # Limit stress block to section diameter
    a_eff = min(a, D)
    
    # =========================================================================
    # Circular Compression Zone Geometry
    # =========================================================================
    # Using StructurePoint formulas:
    # θ = arccos((R - a) / R) where R = D/2
    # A_comp = R² × (θ - sin(θ)cos(θ))
    # ȳ = (2R sin³θ) / (3(θ - sinθcosθ))  [from center toward compression]
    
    comp_zone = circular_compression_zone(D, a_eff)
    A_comp = comp_zone.A_comp
    # y_bar is the moment arm: distance from SECTION CENTROID to compression zone centroid
    moment_arm_Cc = comp_zone.y_bar
    
    # Concrete compression force (positive)
    # Cc = 0.85 * f'c * A_comp
    Cc = 0.85 * fc * A_comp  # kip
    
    # =========================================================================
    # Steel Forces
    # =========================================================================
    Fs_total = 0.0  # Total steel force contribution (positive = compression)
    Ms_total = 0.0  # Steel moment about section centroid
    
    R = D / 2  # Section centroid is at center (radius from edge)
    
    # Concrete stress in compression zone
    fc_stress = 0.85 * fc  # ksi
    
    for bar in section.bars
        # Bar y is from bottom → distance from TOP = D - bar.y
        d_bar = D - ustrip(u"inch", bar.y)  # Depth of bar from compression face
        As_bar = ustrip(u"inch^2", bar.As)
        
        # Steel strain at this bar
        εs = calculate_steel_strain(d_bar, c_in, D, εcu)
        
        # Steel stress (positive = tension, negative = compression)
        fs = calculate_steel_stress(εs, fy, Es)
        
        # Check if bar is within compression zone (Whitney stress block)
        # For circular section, bar is in compression zone if its depth < a
        in_compression_zone = d_bar < a_eff
        
        # Steel force contribution (compression positive):
        # - Pure steel force: -fs * As (fs>0 tension → negative; fs<0 compression → positive)
        # - If bar in compression zone: subtract displaced concrete
        if in_compression_zone
            # Bar in compression zone: steel force minus displaced concrete
            Fs = -As_bar * (fs + fc_stress)
        else
            # Bar outside compression zone: just steel force
            Fs = -fs * As_bar
        end
        
        Fs_total += Fs
        
        # Moment about section centroid
        # Moment arm = R - d_bar (positive if bar is closer to compression face)
        # SP Table uses: arm = D/2 - d for each bar
        arm = R - d_bar  # positive if bar closer to compression face than centroid
        Ms_total += Fs * arm  # kip-in
    end
    
    # Extreme tension strain: bar furthest from compression face (lowest y)
    y_tension_bar_from_bottom = minimum(ustrip(u"inch", bar.y) for bar in section.bars)
    d_tension = D - y_tension_bar_from_bottom  # d = depth to extreme tension steel
    εt = calculate_steel_strain(d_tension, c_in, D, εcu)
    
    # Total axial force (positive = compression)
    Pn = Cc + Fs_total  # kip
    
    # Total moment about centroid
    # Cc acts at the compression zone centroid, moment arm = y_bar (from circular_compression_zone)
    Mc = Cc * moment_arm_Cc  # kip-in
    Mn_in = Mc + Ms_total  # kip-in
    Mn = Mn_in / 12.0  # kip-ft
    
    return (Pn = Pn, Mn = abs(Mn), εt = εt, c = c_in)
end

# ==============================================================================
# Pure Compression Capacity (P0) for Circular Sections
# ==============================================================================

"""
    pure_compression_capacity(section::RCCircularSection, mat) -> Float64

Calculate pure axial compression capacity P0 per ACI 318-19.

P0 = 0.85 * f'c * (Ag - As) + fy * As
"""
function pure_compression_capacity(section::RCCircularSection, mat)
    fc = _get_fc_ksi(mat)
    fy = _get_fy_ksi(mat)
    
    Ag = ustrip(u"inch^2", section.Ag)
    As = ustrip(u"inch^2", section.As_total)
    
    P0 = 0.85 * fc * (Ag - As) + fy * As
    return P0  # kip
end

"""
    max_compression_capacity(section::RCCircularSection, mat) -> Float64

Calculate maximum permitted compression per ACI 318-19 Section 22.4.2.

Pn,max = α * P0, where:
- α = 0.80 for tied columns
- α = 0.85 for spiral columns
"""
function max_compression_capacity(section::RCCircularSection, mat)
    P0 = pure_compression_capacity(section, mat)
    α = section.tie_type == :spiral ? 0.85 : 0.80
    return α * P0
end

# ==============================================================================
# Factored P-M Calculation
# ==============================================================================

"""
    calculate_phi_PM_at_c(section::RCCircularSection, mat, c_in::Real) -> NamedTuple

Calculate factored (φPn, φMn) capacity for a circular column at given c.

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
function calculate_phi_PM_at_c(section::RCCircularSection, mat, c_in::Real)
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
# P-M Interaction Diagram for Circular Sections
# ==============================================================================

"""
    PMInteractionDiagramCircular

Complete P-M interaction diagram for a circular column section.
"""
struct PMInteractionDiagramCircular
    section::RCCircularSection
    mat::NamedTuple
    points::Vector{PMDiagramPoint}
    control_points::Dict{Symbol, Int}
end

"""
    generate_PM_diagram(section::RCCircularSection, mat; n_intermediate::Int=20)

Generate a complete P-M interaction diagram for a circular section per ACI 318-19.

# Arguments
- `section`: RC circular column section
- `mat`: Material properties (fc, fy, Es, εcu)
- `n_intermediate`: Number of intermediate points between control points

# Returns
PMInteractionDiagramCircular with:
- 7 standard ACI control points (StructurePoint methodology)
- Optional intermediate points for smooth curves

# Control Points (per StructurePoint Circular Column Example)
1. Pure compression (P₀)
2. Maximum allowable compression (Pn,max = 0.85*P₀ for spiral)
3. fs = 0 (c = d, zero tension strain)
4. fs = 0.5fy
5. Balanced (fs = fy)
6. Tension controlled (εt = εy + 0.003)
7. Pure bending (Pn ≈ 0)
8. Pure tension
"""
function generate_PM_diagram(section::RCCircularSection, mat; n_intermediate::Int=20)
    # Material properties
    fc = _get_fc_ksi(mat)
    fy = _get_fy_ksi(mat)
    Es = _get_Es_ksi(mat)
    εcu = _get_εcu(mat)
    εy = fy / Es
    
    # Section properties
    D = ustrip(u"inch", section.D)
    d = extreme_tension_depth(section)  # Depth to extreme tension steel
    
    points = PMDiagramPoint[]
    control_indices = Dict{Symbol, Int}()
    
    # =========================================================================
    # Control Point 1: Pure Compression (P₀)
    # =========================================================================
    P0 = pure_compression_capacity(section, mat)
    φ_comp = section.tie_type == :spiral ? 0.75 : 0.65
    push!(points, PMDiagramPoint(
        Inf, -εy,
        P0, 0.0,
        φ_comp, φ_comp * P0, 0.0,
        "P₀ (Pure Compression)"
    ))
    control_indices[:pure_compression] = length(points)
    
    # =========================================================================
    # Control Point 2: Maximum Allowable Compression
    # =========================================================================
    α = section.tie_type == :spiral ? 0.85 : 0.80
    Pn_max = α * P0
    c_large = 5.0 * D
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
    # Control Point 4: Half Yield (fs = 0.5fy)
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
    # Control Point 5: Balanced (fs = fy)
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
    # =========================================================================
    c_pure_m = _find_pure_bending_c_circular(section, mat)
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
    # =========================================================================
    As_total = ustrip(u"inch^2", section.As_total)
    Pnt = -fy * As_total  # Tension negative
    push!(points, PMDiagramPoint(
        -Inf, Inf,
        Pnt, 0.0,
        0.90, 0.90 * Pnt, 0.0,
        "Pure Tension"
    ))
    control_indices[:pure_tension] = length(points)
    
    # =========================================================================
    # Add intermediate points (inserted between control points, indices update)
    # =========================================================================
    if n_intermediate > 0
        # Add intermediate points but preserve control point indices
        # by looking up control points by label after insertion
        all_points = _add_intermediate_points_circular(section, mat, points, n_intermediate)
        
        # Rebuild control_indices based on labels in new points list
        new_indices = Dict{Symbol, Int}()
        label_to_symbol = Dict(
            "P₀ (Pure Compression)" => :pure_compression,
            "Pn,max (Allowable Compression)" => :max_compression,
            "fs = 0" => :fs_zero,
            "fs = 0.5fy" => :fs_half_fy,
            "Balanced (fs = fy)" => :balanced,
            "Tension Controlled (εt = εy + 0.003)" => :tension_controlled,
            "Pure Bending" => :pure_bending,
            "Pure Tension" => :pure_tension
        )
        for (i, pt) in enumerate(all_points)
            if !isempty(pt.label) && haskey(label_to_symbol, pt.label)
                new_indices[label_to_symbol[pt.label]] = i
            end
        end
        
        return PMInteractionDiagramCircular(section, mat, all_points, new_indices)
    end
    
    return PMInteractionDiagramCircular(section, mat, points, control_indices)
end

"""Find c value for pure bending (Pn ≈ 0) for circular sections."""
function _find_pure_bending_c_circular(section::RCCircularSection, mat; tol::Float64=0.1)
    D = ustrip(u"inch", section.D)
    d = extreme_tension_depth(section)
    
    # Bracket: c between small value and balanced point
    c_low = 0.5
    c_high = d
    
    # Check that we have a valid bracket
    result_low = calculate_PM_at_c(section, mat, c_low)
    result_high = calculate_PM_at_c(section, mat, c_high)
    
    if result_low.Pn > 0 && result_high.Pn > 0
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
    
    return (c_low + c_high) / 2
end

"""Add intermediate points for circular sections while preserving all control points."""
function _add_intermediate_points_circular(
    section::RCCircularSection,
    mat,
    control_points::Vector{PMDiagramPoint},
    n_per_segment::Int
)
    all_points = PMDiagramPoint[]
    
    # Keep first two control points (P0 and Pn,max at Inf/large c)
    push!(all_points, control_points[1])  # P₀
    push!(all_points, control_points[2])  # Pn,max
    
    # Extract c values from finite control points (indices 3 to end-1)
    # Sort by c descending (large c = high compression, small c = tension)
    finite_control_pts = filter(pt -> isfinite(pt.c) && pt.c > 0, control_points[3:end-1])
    sort!(finite_control_pts, by = pt -> -pt.c)  # Descending by c
    
    # Add intermediate points between consecutive finite control points
    for i in 1:length(finite_control_pts)
        pt = finite_control_pts[i]
        push!(all_points, pt)  # Add the control point itself
        
        # Add intermediate points between this and next control point
        if i < length(finite_control_pts)
            c_start = pt.c
            c_end = finite_control_pts[i+1].c
            n_between = max(1, n_per_segment ÷ (length(finite_control_pts) - 1))
            
            for j in 1:n_between
                t = j / (n_between + 1)
                c_interp = c_start + t * (c_end - c_start)
                result = calculate_phi_PM_at_c(section, mat, c_interp)
                push!(all_points, PMDiagramPoint(
                    c_interp, result.εt,
                    result.Pn, result.Mn,
                    result.φ, result.φPn, result.φMn,
                    ""  # No label for intermediate points
                ))
            end
        end
    end
    
    # Add final control points (pure bending, pure tension)
    push!(all_points, control_points[end-1])  # Pure bending
    push!(all_points, control_points[end])    # Pure tension
    
    return all_points
end

# ==============================================================================
# Diagram Access Functions (dispatch on circular type)
# ==============================================================================

"""Get nominal P-M points as (Pn, Mn) arrays."""
function get_nominal_curve(diagram::PMInteractionDiagramCircular)
    Pn = [pt.Pn for pt in diagram.points]
    Mn = [pt.Mn for pt in diagram.points]
    return (Pn=Pn, Mn=Mn)
end

"""Get factored P-M points as (φPn, φMn) arrays."""
function get_factored_curve(diagram::PMInteractionDiagramCircular)
    φPn = [pt.φPn for pt in diagram.points]
    φMn = [pt.φMn for pt in diagram.points]
    return (φPn=φPn, φMn=φMn)
end

"""Get control points only (labeled points)."""
function get_control_points(diagram::PMInteractionDiagramCircular)
    return filter(pt -> !isempty(pt.label), diagram.points)
end

"""Get a specific control point by name."""
function get_control_point(diagram::PMInteractionDiagramCircular, name::Symbol)
    idx = get(diagram.control_points, name, nothing)
    if isnothing(idx)
        error("Control point :$name not found. Available: $(keys(diagram.control_points))")
    end
    return diagram.points[idx]
end

# ==============================================================================
# Capacity Check Functions
# ==============================================================================

"""Check if demand (Pu, Mu) is within circular column P-M capacity."""
function check_PM_capacity(diagram::PMInteractionDiagramCircular, Pu::Real, Mu::Real)
    Mu = abs(Mu)
    
    curve = get_factored_curve(diagram)
    φPn = curve.φPn
    φMn = curve.φMn
    
    φMn_at_Pu = _interpolate_moment_at_P(φPn, φMn, Pu)
    φPn_at_Mu = _interpolate_axial_at_M(φPn, φMn, Mu)
    
    if φMn_at_Pu > 0 && abs(φPn_at_Mu) > 0
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
        utilization = 1.5
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

"""Get factored moment capacity at a given factored axial load."""
function capacity_at_axial(diagram::PMInteractionDiagramCircular, Pu::Real)
    curve = get_factored_curve(diagram)
    return _interpolate_moment_at_P(curve.φPn, curve.φMn, Pu)
end

"""Get factored axial capacity at a given factored moment."""
function capacity_at_moment(diagram::PMInteractionDiagramCircular, Mu::Real)
    curve = get_factored_curve(diagram)
    return _interpolate_axial_at_M(curve.φPn, curve.φMn, abs(Mu))
end

"""Calculate utilization ratio for circular columns."""
function utilization_ratio(diagram::PMInteractionDiagramCircular, Pu::Real, Mu::Real)
    result = check_PM_capacity(diagram, Pu, Mu)
    return result.utilization
end
