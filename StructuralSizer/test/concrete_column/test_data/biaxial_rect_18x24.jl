# ============================================================================
# Test Data: Rectangular Column Biaxial Bending
# Based on StructurePoint: "Biaxial Bending Interaction Diagrams for 
# Rectangular Reinforced Concrete Column Design (ACI 318-19)"
# Version: July-25-2022
#
# This tests the y-axis P-M diagram generation and rectangular biaxial check.
# For rectangular columns (b ≠ h), the capacity differs about each axis.
# ============================================================================

"""
Reference data for 18"×24" rectangular column.
Y-axis (about b=18") should have lower capacity than X-axis (about h=24").
"""
const BIAXIAL_RECT_18X24 = (
    # ===== GEOMETRY =====
    geometry = (
        b = 18.0,           # in - column width (y-axis bending depth)
        h = 24.0,           # in - column depth (x-axis bending depth)
        cover = 1.5,        # in - clear cover
        Ag = 432.0,         # in² - gross area (18×24)
    ),
    
    # ===== REINFORCEMENT =====
    # 8 #9 bars distributed on perimeter
    reinforcement = (
        bar_size = 9,
        n_bars = 8,
        As_bar = 1.00,      # in² - #9 bar area
        As_total = 8.00,    # in² - total steel
        # Effective depths
        d_x = 21.44,        # in - depth to tension steel for x-axis (h - cover - tie - d_bar/2)
        d_y = 15.44,        # in - depth to tension steel for y-axis (b - cover - tie - d_bar/2)
    ),
    
    # ===== MATERIALS =====
    materials = (
        fc = 4.0,           # ksi
        fy = 60.0,          # ksi
        Es = 29000.0,       # ksi
        εcu = 0.003,
        β1 = 0.85,          # for f'c = 4 ksi
    ),
    
    # ===== EXPECTED CAPACITIES =====
    # X-axis bending (about h=24"): stronger direction
    # Y-axis bending (about b=18"): weaker direction
    capacities = (
        # Pure compression (same for both axes)
        P0 = 1923.0,        # kip (approx: 0.85×4×(432-8) + 60×8)
        Pn_max = 1538.4,    # kip (0.80 × P0 for tied)
        
        # Maximum moment capacities (at around 0.2-0.4 P0)
        # X-axis has higher capacity since h > b
        φMnx_max = 440.0,   # kip-ft (approximate)
        φMny_max = 302.0,   # kip-ft (approximate)
        
        # Capacity ratio should reflect aspect ratio
        # φMny_max / φMnx_max ≈ (b/h) × some factor
        # For 18/24 = 0.75, expect ratio around 0.65-0.75
        capacity_ratio = 0.69,  # Approximate
    ),
    
    # ===== BIAXIAL DEMANDS AND CHECKS =====
    demands = (
        Pu = 400.0,         # kip
        Mux = 150.0,        # kip-ft - x-axis moment
        Muy = 100.0,        # kip-ft - y-axis moment
    ),
    
    # Expected utilization with Bresler Load Contour (α = 1.5)
    # At Pu = 400 kip:
    # φMnx ≈ 440 kip-ft, φMny ≈ 302 kip-ft
    # util = (150/440)^1.5 + (100/302)^1.5 ≈ 0.20 + 0.19 ≈ 0.39
    bresler_contour = (
        α = 1.5,
        φMnx_at_Pu = 440.0, # kip-ft (approximate)
        φMny_at_Pu = 302.0, # kip-ft (approximate)
        util = 0.39,        # Approximate
        adequate = true,
    ),
    
    # ===== KEY ASSERTIONS =====
    assertions = (
        # Y-axis capacity must be less than X-axis
        y_less_than_x = true,
        # Pure compression same for both (uniform squash)
        p0_equal = true,
        # Rectangular check should detect non-square
        is_square = false,
    ),
)
