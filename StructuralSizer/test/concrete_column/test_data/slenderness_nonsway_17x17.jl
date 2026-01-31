# ============================================================================
# StructurePoint Design Example:
# "Slender Column Design in Non-Sway Frame - Moment Magnification Method (ACI 318-19)"
# Source: https://structurepoint.org/publication/design-examples.asp
# Version: July-18-2022
#
# This example evaluates slenderness effects for an exterior first floor column
# in a non-sway multistory reinforced concrete frame.
# ============================================================================

"""
Verified reference data from StructurePoint spColumn design example.
17"×17" tied column with 10 #9 bars, non-sway frame slenderness check.
"""
const SLENDER_NONSWAY_17X17 = (
    # ===== GEOMETRY =====
    column = (
        b = 17.0,           # in - column width
        h = 17.0,           # in - column depth
        H = 12.0,           # ft - story height
        Lu = 120.0,         # in - unsupported length (H - beam depth = 144 - 24)
    ),
    
    # ===== REINFORCEMENT =====
    reinforcement = (
        bar_size = 9,
        n_bars = 10,
        As_total = 10.0,    # in² (10 × 1.00)
        Ise = 360.0,        # in⁴ - moment of inertia of reinforcement about centroid
    ),
    
    # ===== MATERIALS =====
    materials = (
        fc = 3.0,           # ksi
        fy = 60.0,          # ksi
        Es = 29000.0,       # ksi
        εcu = 0.003,
        Ec = 3122.0,        # ksi - from 57000√f'c (psi)
    ),
    
    # ===== FRAME PROPERTIES =====
    frame = (
        # Beam properties
        beam_b = 14.0,      # in
        beam_h = 24.0,      # in
        beam_l = 30.0,      # ft
        # Frame stiffness
        EI_col_l = 8.8e3,   # kip-ft (EcIcol/lc)
        EI_beam_l = 4.08e3, # kip-ft (EcIbeam/lb)
        ψ_A = 4.32,         # Stiffness ratio at top (2 columns / 1 beam)
        ψ_B = Inf,          # Hinged at base
        k_calc = 0.959,     # Calculated effective length factor
        k_conservative = 1.0, # Conservative value per ACI 6.6.4.4.3
        braced = true,      # Non-sway (braced) frame
    ),
    
    # ===== LOADING =====
    loading = (
        Pu = 525.0,         # kip - factored axial load
        M1 = 0.0,           # kip-ft - smaller end moment
        M2 = 105.0,         # kip-ft - larger end moment
        βdns = 0.40,        # 40% sustained load
    ),
    
    # ===== SLENDERNESS CALCULATIONS (from PDF) =====
    slenderness = (
        # Section properties
        Ig = 6960.0,        # in⁴ - gross moment of inertia (17⁴/12)
        r = 4.91,           # in - radius of gyration (√(Ig/Ag))
        
        # With k = 0.959
        kLu_r = 23.45,      # Slenderness ratio (0.959×120/4.91)
        limit_nonsway = 34.0, # Limit: 34 - 12(M1/M2) = 34 - 0 = 34
        slender = false,    # kLu/r < 34, slenderness can be neglected
        
        # Effective stiffness (EI)_eff per ACI 6.6.4.4.4(b)
        EI_eff = 10.56e6,   # kip-in² - (0.2×Ec×Ig + Es×Ise)/(1+βdns)
        
        # Critical load
        Pc = 7871.0,        # kip - π²(EI)_eff/(kLu)²
        
        # Moment magnification (shown for illustration even though not required)
        Cm = 0.60,          # 0.6 - 0.4(M1/M2) = 0.6 - 0 = 0.6
        δns_calc = 0.66,    # Cm/(1 - Pu/(0.75Pc)) = 0.6/(1 - 525/(0.75×7871))
        δns = 1.0,          # Must be ≥ 1.0
        
        # Minimum moment
        M_min = 48.56,      # kip-ft - Pu(0.6 + 0.03h)/12
        
        # Magnified moment
        Mc = 105.0,         # kip-ft - max(δns×M2, M_min) = max(1.0×105, 48.56)
    ),
    
    # ===== COMPARISON TABLE (Table 2 from PDF) =====
    comparison = (
        # Reference values
        reference = (k = 1.000, EI_eff = 10.50e6, Pc = 7200.0, δns = 0.66, Mc = 105.0),
        # Hand calculation
        hand = (k = 0.959, EI_eff = 10.56e6, Pc = 7871.0, δns = 0.66, Mc = 105.0),
        # spColumn
        spColumn = (k = 0.960, EI_eff = 10.57e6, Pc = 7850.0, Mc = 105.0),
    ),
)
