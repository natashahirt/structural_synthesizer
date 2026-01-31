# ============================================================================
# StructurePoint Design Example:
# "Interaction Diagram - Tied Reinforced Concrete Column Design Strength (ACI 318-19)"
# Source: https://structurepoint.org/publication/design-examples.asp
# Version: May-24-2022
#
# This example generates a P-M interaction diagram for a square tied column
# using ACI 318-19 provisions.
# ============================================================================

"""
Verified reference data from StructurePoint spColumn design example.
16"×16" tied column with 8 #9 bars (4 top + 4 bottom in 2 layers).
"""
const TIED_16X16_SPCOLUMN = (
    # ===== GEOMETRY =====
    geometry = (
        b = 16.0,           # in - column width
        h = 16.0,           # in - column depth
        d = 13.5,           # in - depth to tension steel (from compression face)
        d_prime = 2.5,      # in - depth to compression steel (from compression face)
    ),

    # ===== REINFORCEMENT =====
    # 8 #9 bars total: 4 in tension layer, 4 in compression layer
    # Note: This is a 2-LAYER arrangement (not perimeter)
    reinforcement = (
        bar_size = 9,
        n_bars = 8,
        As_bar = 1.00,          # in² - area per #9 bar
        As_total = 8.00,        # in² - total steel area
        # Bar positions (y measured from BOTTOM of section):
        # Bottom layer (tension when moment causes compression at top):
        #   4 bars at y = 2.5" from bottom
        # Top layer (compression when moment causes compression at top):
        #   4 bars at y = 13.5" from bottom
        bar_layers = [
            (y = 2.5, n_bars = 4, As = 4.00),   # bottom/tension layer
            (y = 13.5, n_bars = 4, As = 4.00),  # top/compression layer
        ],
    ),

    # ===== MATERIALS =====
    materials = (
        fc = 5.0,           # ksi - concrete compressive strength
        fy = 60.0,          # ksi - steel yield strength
        Es = 29000.0,       # ksi - steel modulus
        εcu = 0.003,        # in/in - ultimate concrete strain
        β1 = 0.80,          # stress block factor for f'c = 5 ksi
    ),

    # ===== NOMINAL STRENGTH CONTROL POINTS (Pn, Mn) =====
    # These are NOMINAL (unfactored) values from the PDF hand calculations
    control_points = (
        # Point 1: Pure compression (P₀)
        # P₀ = 0.85·f'c·(Ag - Ast) + fy·Ast
        # P₀ = 0.85×5×(256 - 8) + 60×8 = 1054.0 + 480.0 = 1534.0 kip
        pure_compression = (
            name = "Pure Compression (P₀)",
            c = Inf,            # neutral axis at infinity
            Pn = 1534.0,        # kip (nominal)
            Mn = 0.0,           # kip-ft
            φ = 0.65,           # compression controlled
            φPn = 997.1,        # kip (factored)
            φMn = 0.0,          # kip-ft (factored)
        ),

        # Point 2: Zero tension steel strain (εs = 0, fs = 0)
        # c = d = 13.5 in
        fs_zero = (
            name = "fs = 0 (εt = 0)",
            c = 13.5,           # in
            Pn = 957.4,         # kip
            Mn = 261.33,        # kip-ft
            φ = 0.65,
            φPn = 622.3,        # kip
            φMn = 169.86,       # kip-ft
        ),

        # Point 3: Half yield stress (fs = 0.5·fy)
        # εs = 0.00103, c = 10.04 in
        fs_half_fy = (
            name = "fs = 0.5fy",
            c = 10.04,          # in
            Pn = 649.1,         # kip
            Mn = 338.54,        # kip-ft
            φ = 0.65,
            φPn = 421.9,        # kip
            φMn = 220.05,       # kip-ft
        ),

        # Point 4: Balanced point (fs = fy, tension steel just yielding)
        # εs = εy = 0.00207, c = 7.99 in
        balanced = (
            name = "Balanced (fs = fy)",
            c = 7.99,           # in
            Pn = 416.8,         # kip
            Mn = 385.81,        # kip-ft
            φ = 0.65,
            φPn = 270.9,        # kip
            φMn = 250.77,       # kip-ft
        ),

        # Point 5: Tension controlled (εs = εy + 0.003 = 0.00507)
        # c = 5.02 in
        tension_controlled = (
            name = "Tension Controlled (εt = εy + 0.003)",
            c = 5.02,           # in
            Pn = 190.7,         # kip
            Mn = 318.61,        # kip-ft
            φ = 0.90,
            φPn = 171.6,        # kip
            φMn = 286.75,       # kip-ft
        ),

        # Point 6: Pure bending (Pn ≈ 0)
        # c = 3.25 in (iteratively solved)
        pure_bending = (
            name = "Pure Bending",
            c = 3.25,           # in
            Pn = 0.0,           # kip (approximately)
            Mn = 237.73,        # kip-ft
            φ = 0.90,
            φPn = 0.0,          # kip
            φMn = 213.96,       # kip-ft
        ),

        # Point 7: Pure tension
        # Pnt = fy × Ast = 60 × 8 = 480 kip (tension is negative by convention)
        pure_tension = (
            name = "Pure Tension",
            c = -Inf,           # all tension
            Pn = -480.0,        # kip (tension negative)
            Mn = 0.0,           # kip-ft
            φ = 0.90,
            φPn = -432.0,       # kip
            φMn = 0.0,          # kip-ft
        ),
    ),

    # ===== INTERMEDIATE CALCULATION VALUES (for verification) =====
    # These are key intermediate values from the PDF for debugging
    intermediate = (
        # At balanced point (c = 7.99 in):
        balanced = (
            a = 6.39,               # in - stress block depth
            Cc = 434.6,             # kip - concrete compression force
            εs_compression = 0.00206,  # compression steel strain (< εy, not yielded)
            fs_compression = 59778.0,  # psi - compression steel stress
            Cs = 222.1,             # kip - compression steel force (fs - 0.85f'c)×As
            Ts = 240.0,             # kip - tension steel force
        ),
        
        # At tension controlled (c = 5.02 in):
        tension_controlled = (
            a = 4.02,               # in
            Cc = 273.1,             # kip
            εs_compression = 0.00151,  # < εy
            fs_compression = 43667.0,  # psi
            Cs = 157.7,             # kip
            Ts = 240.0,             # kip
        ),
        
        # At pure bending (c = 3.25 in):
        pure_bending = (
            a = 2.60,               # in
            Cc = 176.8,             # kip
            εs_compression = 0.00069,  # < εy
            fs_compression = 20077.0,  # psi
            Cs = 63.3,              # kip
            Ts = 240.0,             # kip
        ),
    ),
)
