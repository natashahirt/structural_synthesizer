# ==============================================================================
# StructurePoint Circular Column Reference Data
# ==============================================================================
# Source: "Interaction Diagram - Circular Spiral Reinforced Concrete Column 
#          (ACI 318-19)" - StructurePoint Design Example
#
# This file defines the exact section used in the StructurePoint example
# for validation of circular column P-M calculations.
# ==============================================================================

using StructuralSizer
using Unitful

# ==============================================================================
# Material Properties (from SP example page 4)
# ==============================================================================
# f'c = 5000 psi = 5.0 ksi
# fy = 60000 psi = 60.0 ksi
# Es = 29000 ksi (standard)
# εcu = 0.003 (ACI 318)
# β1 = 0.85 - 0.05*(5000-4000)/1000 = 0.80

const CIRCULAR_20_MAT = (
    fc = 5.0,    # ksi
    fy = 60.0,   # ksi
    Es = 29000.0,# ksi
    εcu = 0.003
)

# ==============================================================================
# Section Geometry (from SP example Figure 1, Table 1)
# ==============================================================================
# Diameter = 20 in
# Clear cover = 1.5 in
# 8 #10 bars (As = 1.27 in² each)
# Total As = 10.16 in²
# Spiral column
#
# Bar layout from Table 1 (d = depth from compression face):
# Layer 1: d = 2.64 in, 1 bar  (top)
# Layer 2: d = 4.79 in, 2 bars
# Layer 3: d = 10.00 in, 2 bars (middle)
# Layer 4: d = 15.21 in, 2 bars
# Layer 5: d = 17.37 in, 1 bar  (bottom)
#
# Converting d to y (from bottom): y = D - d
# Layer 1: y = 20 - 2.64 = 17.36 in
# Layer 2: y = 20 - 4.79 = 15.21 in
# Layer 3: y = 20 - 10.00 = 10.00 in
# Layer 4: y = 20 - 15.21 = 4.79 in
# Layer 5: y = 20 - 17.37 = 2.63 in

"""
Create the exact circular section from the StructurePoint example.
Uses explicit bar positions matching SP Table 1.
"""
function create_sp_circular_20_section()
    D = 20.0u"inch"
    
    # Bar properties (#10 bar)
    As_bar = 1.27u"inch^2"
    
    # Create bars with explicit positions (x, y from bottom-left)
    # For a symmetric section, x-positions are distributed around center
    # But SP uses layers by depth, so we need to match that
    
    # Center of section is at (D/2, D/2) = (10, 10) from bottom-left
    # Bars are placed at radius R from center
    # The bar depths given are from compression face (top)
    
    # From SP, the bars are at depths:
    # d1=2.64, d2=4.79, d3=10.00, d4=15.21, d5=17.37
    # These correspond to y from bottom:
    # y1=17.36, y2=15.21, y3=10.00, y4=4.79, y5=2.63
    
    # For the y=10 bars (layer 3), they are at the horizontal centerline
    # The x positions can be found from the circular radius
    
    # Radius to bar centers: R = D/2 - cover - spiral - bar_dia/2
    # From SP: bars at R_bar from center
    # With d5 = 17.37 for bottom bar: R_bar = D/2 - d5 + D/2 = D - d5 = 20 - 17.37 = 2.63
    # Wait, that's y from bottom. The actual radius:
    # Layer 5 is at y=2.63 from bottom, so distance from center = |y - D/2| = |2.63 - 10| = 7.37
    # So R_bar ≈ 7.37 in
    
    R_bar = 7.37  # Approximate radius to bar centers
    
    # Now create bars:
    # Layer 5 (bottom): 1 bar at (10, 2.63)
    # Layer 4: 2 bars at y=4.79, x positions symmetric about center
    # Layer 3: 2 bars at y=10.00, x positions at edges (x = 10 ± R_bar)
    # Layer 2: 2 bars at y=15.21, symmetric
    # Layer 1 (top): 1 bar at (10, 17.36)
    
    # For circular bar arrangement, angle θ determines x position:
    # For layer at y: x = 10 ± sqrt(R_bar² - (y-10)²)
    
    bars = StructuralSizer.RebarLocation[]
    
    # Layer 5: d=17.37, y=2.63, 1 bar at center x
    y5 = 2.63
    x5 = 10.0  # Center
    push!(bars, StructuralSizer.RebarLocation(x5*u"inch", y5*u"inch", As_bar))
    
    # Layer 4: d=15.21, y=4.79, 2 bars
    y4 = 4.79
    dx4 = sqrt(R_bar^2 - (y4 - 10)^2)
    push!(bars, StructuralSizer.RebarLocation((10 - dx4)*u"inch", y4*u"inch", As_bar))
    push!(bars, StructuralSizer.RebarLocation((10 + dx4)*u"inch", y4*u"inch", As_bar))
    
    # Layer 3: d=10.00, y=10.00, 2 bars at x = 10 ± R_bar
    y3 = 10.0
    push!(bars, StructuralSizer.RebarLocation((10 - R_bar)*u"inch", y3*u"inch", As_bar))
    push!(bars, StructuralSizer.RebarLocation((10 + R_bar)*u"inch", y3*u"inch", As_bar))
    
    # Layer 2: d=4.79, y=15.21, 2 bars
    y2 = 15.21
    dx2 = sqrt(R_bar^2 - (y2 - 10)^2)
    push!(bars, StructuralSizer.RebarLocation((10 - dx2)*u"inch", y2*u"inch", As_bar))
    push!(bars, StructuralSizer.RebarLocation((10 + dx2)*u"inch", y2*u"inch", As_bar))
    
    # Layer 1: d=2.64, y=17.36, 1 bar at center
    y1 = 17.36
    x1 = 10.0
    push!(bars, StructuralSizer.RebarLocation(x1*u"inch", y1*u"inch", As_bar))
    
    # Create section with explicit bars
    return StructuralSizer.RCCircularSection(
        D, bars;
        cover = 1.5u"inch",
        tie_type = :spiral,
        name = "20DIA-8#10-SP"
    )
end

# ==============================================================================
# StructurePoint Reference Results (from Table 8, page 31)
# ==============================================================================
# These are the exact values from the StructurePoint design example
# for validating our implementation.

const SP_CIRCULAR_20_RESULTS = (
    # Control point values (φPn in kip, φMn in kip-ft)
    max_compression = (φPn = 1426.2, φMn = 0.00),
    allowable_compression = (φPn = 1212.3, φMn = 0.00),  # Note: SP shows "---" for φMn
    fs_zero = (φPn = 984.5, φMn = 208.16),
    fs_half_fy = (φPn = 642.2, φMn = 281.43),
    balanced = (φPn = 389.2, φMn = 305.80),
    tension_controlled = (φPn = 26.6, φMn = 295.31),
    pure_bending = (φPn = 0.0, φMn = 288.09),  # SP shows 288.10
    max_tension = (φPn = -548.6, φMn = 0.00),
)

# Intermediate values from Table 4 (balanced point detailed calculation)
const SP_CIRCULAR_20_BALANCED_DETAILS = (
    c = 10.28,           # in (neutral axis depth)
    d5 = 17.36,          # in (depth to extreme tension steel)
    εs5 = 0.00207,       # in/in (strain at balanced = εy)
    Pn = 519.0,          # kip (nominal, before φ)
    Mn = 408.0,          # kip-ft (nominal, before φ)
    φ = 0.75,            # Compression controlled for spiral
)

# Section properties
const SP_CIRCULAR_20_PROPERTIES = (
    D = 20.0,            # in
    Ag = π * 20^2 / 4,   # in² = 314.16
    As_total = 10.16,    # in² (8 × 1.27)
    ρg = 10.16 / (π * 20^2 / 4),  # = 0.0323 = 3.23%
    β1 = 0.80,           # For f'c = 5 ksi
    εy = 60.0 / 29000,   # = 0.00207
)

# Intermediate values at fs=0 point (Table 2)
const SP_CIRCULAR_20_FS_ZERO = (
    c = 17.37,           # in (= d5, neutral axis at extreme tension steel)
    a = 0.80 * 17.37,    # = 13.89 in
    θ_deg = 112.9,       # degrees
    A_comp = 232.9,      # in²
    y_bar = 2.24,        # in (centroid from extreme compression)
    Cc = 989.86,         # kip
    Pn = 1312.64,        # kip
    Mn = 277.54,         # kip-ft
    φ = 0.75,
)
