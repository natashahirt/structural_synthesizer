# ============================================================================
# StructurePoint Design Example:
# "Slender Concrete Column Design in Sway Frames - Moment Magnification 
# Method (ACI 318-19)"
# Source: https://structurepoint.org/publication/design-examples.asp
# Version: August-12-2022
#
# This example evaluates slenderness effects for an exterior first floor column
# in a sway multistory reinforced concrete building with wind loads.
# ============================================================================

"""
Reference data from StructurePoint spColumn design example.
18"×18" tied column with 8 #6 bars, sway frame slenderness check.
"""
const SLENDER_SWAY_18X18 = (
    # ===== COLUMN GEOMETRY =====
    column = (
        b = 18.0,           # in - column width
        h = 18.0,           # in - column depth
        cover = 2.5,        # in - clear cover
        Lu = 186.0,         # in - unsupported length (15.5 ft = 186 in)
        H = 15.5,           # ft - first story height (clear)
    ),
    
    # ===== REINFORCEMENT =====
    reinforcement = (
        bar_size = 6,
        n_bars = 8,
        As_total = 3.52,    # in² (8 × 0.44)
        Ise = 111.5,        # in⁴ - moment of inertia of reinforcement
    ),
    
    # ===== MATERIALS =====
    materials = (
        fc = 4.0,           # ksi
        fy = 60.0,          # ksi
        Es = 29000.0,       # ksi
        εcu = 0.003,
        Ec = 3605.0,        # ksi - from 57000√f'c (psi)
    ),
    
    # ===== FRAME PROPERTIES =====
    frame = (
        # Frame is unbraced (sway)
        braced = false,
        
        # Effective length factors for sway
        ψ_A = 2.027,        # Stiffness ratio at top (from PDF)
        ψ_B = 0.0,          # Fixed at base
        k_sway = 1.282,     # Sway effective length factor (from alignment chart)
        
        # For non-sway check along length (after sway magnification)
        k_nonsway = 1.0,    # Used for along-length check
    ),
    
    # ===== STORY PROPERTIES =====
    # Total building loads in first story (from Table 1 in PDF)
    story = (
        ΣPu = 2031.0,       # kip - total vertical load (load combo 6)
        ΣPc = 49976.83,     # kip - sum of critical loads for all columns
        Vus = 20.0,         # kip - factored horizontal story shear
        Δo = 0.16,          # in - first-order story drift
        lc = 186.0,         # in - story height (center to center)
    ),
    
    # ===== LOADING (Load Combination 6) =====
    # 1.2D + 0.5L + 0.5Lr + 1.0W
    loading = (
        Pu = 381.8,         # kip - factored axial load
        # Non-sway moments (gravity only)
        M1ns = 50.2,        # kip-ft - smaller end non-sway moment
        M2ns = 47.6,        # kip-ft - larger end non-sway moment
        # Sway moments (lateral load only)
        M1s = 53.8,         # kip-ft - smaller end sway moment
        M2s = 46.3,         # kip-ft - larger end sway moment
        # Sustained load ratios
        βds = 0.0,          # No sustained lateral load (wind is transient)
        βdns = 0.805,       # Sustained gravity load ratio
    ),
    
    # ===== SWAY MAGNIFICATION (ACI 6.6.4.6) =====
    sway = (
        # Story stability index Q = ΣPu×Δo / (Vus×lc)
        # Q = 2031 × 0.16 / (20 × 186) = 0.087
        Q = 0.087,
        is_sway = true,     # Q > 0.05
        
        # Sway magnification factor δs
        # Method (a) using Q: δs = 1/(1-Q) = 1/(1-0.087) = 1.095
        δs_Q_method = 1.095,
        
        # Method (b) using ΣPu/ΣPc: δs = 1/(1 - ΣPu/(0.75×ΣPc))
        # δs = 1/(1 - 2031/(0.75×49976.83)) = 1.057
        δs_Pc_method = 1.057,
        
        # PDF uses method (b): δs = 1.057
        δs = 1.057,
        
        # Magnified moments at ends
        # M1 = M1ns + δs × M1s = 50.2 + 1.057 × 53.8 = 107.1 kip-ft
        # M2 = M2ns + δs × M2s = 47.6 + 1.057 × 46.3 = 96.6 kip-ft
        M1_magnified = 107.1,   # kip-ft
        M2_magnified = 96.6,    # kip-ft
    ),
    
    # ===== ALONG-LENGTH CHECK (ACI 6.6.4.6.4) =====
    # After sway magnification, check slenderness along length using nonsway procedure
    length_check = (
        # Slenderness ratio for along-length check (k = 1.0)
        r = 5.4,            # in - radius of gyration (0.3h for rectangular)
        λ_along = 34.4,     # 1.0 × 186 / 5.4
        
        # Limit: 34 - 12(M1/M2) ≈ 34 for near-equal moments
        limit = 34.0,
        
        # λ_along > limit → need to check along length
        check_required = true,
        
        # But for this example, the along-length magnification is small
        # because Pc is large relative to Pu
        δns = 1.0,          # Approximately 1.0
    ),
    
    # ===== FINAL DESIGN MOMENT =====
    final = (
        Mc = 107.1,         # kip-ft - design moment (max of magnified ends)
    ),
    
    # ===== COMPARISON TABLE (from PDF Table 4) =====
    # Lateral load combination #6 results
    comparison = (
        # Using ACI 6.6.4.6.2(a) (Q method)
        Q_method = (δs = 1.08, M1 = 97.7, M2 = 108.4),
        # Using ACI 6.6.4.6.2(b) (ΣPc method)
        Pc_method = (δs = 1.06, M1 = 96.6, M2 = 107.1),
    ),
)
