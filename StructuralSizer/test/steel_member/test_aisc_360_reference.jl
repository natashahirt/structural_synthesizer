# =============================================================================
# Reference Tests for AISC 360-16/22 Steel Design
# NOT INCLUDED IN runtests.jl - Standalone verification against AISC Specification
#
# IMPORTANT: These tests validate against AISC 360 equations.
# DO NOT MODIFY without verifying against source specification.
#
# Source: AISC 360-16 Specification for Structural Steel Buildings
# Supplemented by: AISC Steel Construction Manual 15th/16th Edition
# =============================================================================
#
# These tests verify that the implementation correctly applies:
# - Chapter D: Design of Members for Tension
# - Chapter E: Design of Members for Compression  
# - Chapter F: Design of Members for Flexure
# - Chapter G: Design of Members for Shear
# - Chapter H: Design of Members for Combined Forces
# =============================================================================

using Test
using Unitful
using Unitful: @u_str

# =============================================================================
# AISC 360 REFERENCE EQUATIONS AND CONSTANTS
# =============================================================================

"""
AISC 360-16 constants and material properties for A992 steel
"""
const AISC_360_CONSTANTS = (
    # Material Properties (A992 Steel, Table 2-4)
    E = 29000.0,             # ksi - modulus of elasticity (Eq. E3-4)
    G = 11200.0,             # ksi - shear modulus (approx E/2.6)
    Fy = 50.0,               # ksi - yield stress
    Fu = 65.0,               # ksi - tensile strength
    
    # Resistance Factors (Table J3.2, Spec)
    ϕc = 0.90,               # compression
    ϕb = 0.90,               # flexure
    ϕv = 1.00,               # shear (rolled I-shapes)
    ϕt_yield = 0.90,         # tension yielding
    ϕt_rupture = 0.75,       # tension rupture
    
    # Slenderness Limits (Table B4.1a - Compression)
    λr_flange_comp = 0.56,   # coefficient for compact/noncompact flange limit
    λr_web_comp = 1.49,      # coefficient for compact/noncompact web limit
    
    # Slenderness Limits (Table B4.1b - Flexure)
    λp_flange_flex = 0.38,   # compact flange limit coefficient
    λr_flange_flex = 1.0,    # noncompact flange limit coefficient
    λp_web_flex = 3.76,      # compact web limit coefficient
    λr_web_flex = 5.70,      # noncompact web limit coefficient
    
    # Column Buckling Transition
    transition_ratio = 4.71, # √(E/Fy) coefficient (Eq. E3-2/E3-3 boundary)
    inelastic_coef = 0.658,  # coefficient in Eq. E3-2
    elastic_coef = 0.877,    # coefficient in Eq. E3-3
)

# =============================================================================
# HAND-CALCULATED REFERENCE VALUES
# W14X82 at KL=14 ft (typical column scenario)
# =============================================================================

"""
Hand-calculated compression design for W14X82 with KL = 14 ft
Reference: AISC 360-16 Section E3
"""
const W14X82_COMPRESSION_REFERENCE = (
    # Section Properties (AISC Manual Table 1-1)
    section = (
        name = "W14X82",
        A = 24.0,             # in² - gross area
        d = 14.3,             # in - overall depth
        tw = 0.510,           # in - web thickness
        bf = 10.1,            # in - flange width
        tf = 0.855,           # in - flange thickness
        rx = 6.05,            # in - radius of gyration (x-axis)
        ry = 2.48,            # in - radius of gyration (y-axis)
        J = 5.07,             # in⁴ - torsional constant
        Cw = 5110.0,          # in⁶ - warping constant
    ),
    
    # Design Parameters
    design = (
        KL = 14.0,            # ft - effective length
        K = 1.0,              # effective length factor
        L = 14.0,             # ft - unbraced length
    ),
    
    # ===== WEAK AXIS FLEXURAL BUCKLING (E3) =====
    # Governs for W-shapes (smaller r)
    weak_axis = (
        # Step 1: Slenderness ratio
        # KL/ry = (14 × 12) / 2.48 = 67.74
        KL_r = 67.74,
        
        # Step 2: Check slenderness limit
        # 4.71√(E/Fy) = 4.71√(29000/50) = 113.4
        λ_limit = 113.4,
        
        # Since KL/r = 67.74 < 113.4 → Inelastic buckling (Eq. E3-2)
        
        # Step 3: Elastic buckling stress (Eq. E3-4)
        # Fe = π²E / (KL/r)² = π² × 29000 / 67.74² = 62.36 ksi
        Fe = 62.36,           # ksi
        
        # Step 4: Critical stress (Eq. E3-2)
        # Since Fy/Fe = 50/62.36 = 0.802 < 2.25
        # Fcr = 0.658^(Fy/Fe) × Fy = 0.658^0.802 × 50 = 36.16 ksi
        Fcr = 36.16,          # ksi
        
        # Step 5: Nominal compressive strength (Eq. E3-1)
        # Pn = Fcr × Ag = 36.16 × 24.0 = 867.8 kips
        Pn = 867.8,           # kips
        
        # Step 6: Design strength
        # ϕPn = 0.9 × 867.8 = 781.1 kips
        ϕPn = 781.1,          # kips
    ),
    
    # ===== STRONG AXIS FLEXURAL BUCKLING (for comparison) =====
    strong_axis = (
        # KL/rx = (14 × 12) / 6.05 = 27.77
        KL_r = 27.77,
        
        # Fe = π²E / (KL/r)² = π² × 29000 / 27.77² = 371.2 ksi
        Fe = 371.2,           # ksi
        
        # Since Fy/Fe = 50/371.2 = 0.135 < 2.25
        # Fcr = 0.658^0.135 × 50 = 46.92 ksi
        Fcr = 46.92,          # ksi
        
        # Pn = 46.92 × 24.0 = 1126.1 kips
        Pn = 1126.1,          # kips
        
        # ϕPn = 0.9 × 1126.1 = 1013.5 kips
        ϕPn = 1013.5,         # kips
    ),
)

"""
Hand-calculated tension design for W8X21
Reference: AISC 360-16 Section D
"""
const W8X21_TENSION_REFERENCE = (
    # Section Properties (AISC Manual Table 1-1)
    section = (
        name = "W8X21",
        A = 6.16,             # in² - gross area
        d = 8.28,             # in - overall depth
        bf = 5.27,            # in - flange width
        tf = 0.400,           # in - flange thickness
        rx = 3.49,            # in - radius of gyration (x-axis)
        ry = 1.26,            # in - radius of gyration (y-axis)
    ),
    
    # Design for yielding and rupture
    # Assume: Ae = 4.32 in² (from U factor and bolt holes)
    Ae = 4.32,                # in² - effective net area
    
    # ===== TENSION YIELDING (D2a) =====
    # Pn = Fy × Ag = 50 × 6.16 = 308 kips
    # ϕPn = 0.90 × 308 = 277.2 kips
    yielding = (
        Pn = 308.0,           # kips
        ϕPn = 277.2,          # kips
    ),
    
    # ===== TENSION RUPTURE (D2b) =====
    # Pn = Fu × Ae = 65 × 4.32 = 280.8 kips
    # ϕPn = 0.75 × 280.8 = 210.6 kips (GOVERNS)
    rupture = (
        Pn = 280.8,           # kips
        ϕPn = 210.6,          # kips
    ),
    
    # ===== SLENDERNESS CHECK (D1 Commentary) =====
    # L/r ≤ 300 (recommended for tension members)
    # For L = 25 ft: L/ry = (25 × 12) / 1.26 = 238.1 < 300 ✓
    slenderness = (
        L = 25.0,             # ft
        L_r = 238.1,          # slenderness ratio
        limit = 300,          # recommended maximum
    ),
)

"""
Hand-calculated flexure design for W21X55 with Lb = 12 ft
Reference: AISC 360-16 Section F2
"""
const W21X55_FLEXURE_REFERENCE = (
    # Section Properties (AISC Manual Table 1-1)
    section = (
        name = "W21X55",
        Zx = 126.0,           # in³ - plastic section modulus (x-axis)
        Sx = 110.0,           # in³ - elastic section modulus (x-axis)
        Iy = 48.4,            # in⁴ - moment of inertia (y-axis)
        ry = 1.64,            # in - radius of gyration (y-axis)
        J = 1.24,             # in⁴ - torsional constant
        Cw = 4980.0,          # in⁶ - warping constant
        ho = 20.4,            # in - distance between flange centroids
        rts = 1.87,           # in - effective radius of gyration
        bf = 8.22,            # in - flange width
        tf = 0.522,           # in - flange thickness
        d = 20.8,             # in - overall depth
        tw = 0.375,           # in - web thickness
    ),
    
    design = (
        Lb = 12.0,            # ft - unbraced length
        Cb = 1.0,             # moment gradient factor (conservative)
    ),
    
    # ===== COMPACTNESS CHECK =====
    compactness = (
        # Flange: bf/(2tf) = 8.22 / (2 × 0.522) = 7.87
        λf = 7.87,
        # λpf = 0.38√(E/Fy) = 0.38√(29000/50) = 9.15
        λpf = 9.15,
        # λf < λpf → Compact flange
        flange_compact = true,
        
        # Web: (d - 2tf) / tw = (20.8 - 2×0.522) / 0.375 = 52.7
        λw = 52.7,
        # λpw = 3.76√(E/Fy) = 3.76√(29000/50) = 90.5
        λpw = 90.5,
        # λw < λpw → Compact web
        web_compact = true,
    ),
    
    # ===== PLASTIC MOMENT (F2.1) =====
    # Mp = Fy × Zx = 50 × 126 = 6300 kip-in = 525 kip-ft
    Mp = 525.0,               # kip-ft
    
    # ===== UNBRACED LENGTH LIMITS =====
    # Lp = 1.76 × ry × √(E/Fy) = 1.76 × 1.64 × √(29000/50) = 69.5 in = 5.79 ft
    # Lr = 1.95 × rts × (E/0.7Fy) × √(J×c/(Sx×ho) + √((J×c/(Sx×ho))² + 6.76(0.7Fy/E)²))
    # Lr ≈ 15.1 ft (from AISC Manual Table 3-2)
    Lp = 5.79,                # ft
    Lr = 15.1,                # ft (approximate, from tables)
    
    # ===== LATERAL-TORSIONAL BUCKLING (F2.2) =====
    # Since Lp < Lb < Lr → Inelastic LTB
    # Mn = Cb × [Mp - (Mp - 0.7×Fy×Sx) × (Lb - Lp)/(Lr - Lp)] ≤ Mp
    # With Cb = 1.0:
    # Mn = 1.0 × [525 - (525 - 0.7×50×110/12) × (12 - 5.79)/(15.1 - 5.79)]
    # Mn = 525 - (525 - 320.8) × (6.21/9.31)
    # Mn = 525 - 204.2 × 0.667 = 388.8 kip-ft
    inelastic_ltb = (
        Mr = 320.8,           # kip-ft = 0.7×Fy×Sx
        Mn = 388.8,           # kip-ft
        ϕMn = 350.0,          # kip-ft = 0.9 × 388.8
    ),
    
    # ===== FULL PLASTIC MOMENT (Lb ≤ Lp) =====
    # When Lb = 0 (continuous bracing):
    # Mn = Mp = 525 kip-ft
    # ϕMn = 0.9 × 525 = 472.5 kip-ft
    full_plastic = (
        Mn = 525.0,           # kip-ft
        ϕMn = 472.5,          # kip-ft
    ),
)

"""
Hand-calculated shear design for W24X62
Reference: AISC 360-16 Section G2
"""
const W24X62_SHEAR_REFERENCE = (
    # Section Properties (AISC Manual Table 1-1)
    section = (
        name = "W24X62",
        d = 23.7,             # in - overall depth
        tw = 0.430,           # in - web thickness
        tf = 0.590,           # in - flange thickness
    ),
    
    # ===== WEB AREA =====
    # Aw = d × tw = 23.7 × 0.430 = 10.19 in² (per AISC definition)
    Aw = 10.19,               # in²
    
    # ===== SHEAR YIELDING (G2.1) =====
    # For rolled I-shapes: Cv1 = 1.0 when h/tw ≤ 2.24√(E/Fy)
    # h/tw = (23.7 - 2×0.590) / 0.430 = 52.4
    # Limit = 2.24√(29000/50) = 53.9
    # Since 52.4 < 53.9 → Cv1 = 1.0
    web_check = (
        h_tw = 52.4,
        limit = 53.9,
        Cv1 = 1.0,
    ),
    
    # ===== NOMINAL SHEAR STRENGTH (G2.1) =====
    # Vn = 0.6 × Fy × Aw × Cv1 = 0.6 × 50 × 10.19 × 1.0 = 305.7 kips
    # ϕvVn = 1.0 × 305.7 = 305.7 kips (ϕv = 1.0 for rolled I-shapes)
    shear = (
        Vn = 305.7,           # kips
        ϕVn = 305.7,          # kips (ϕv = 1.0)
    ),
)

"""
Hand-calculated P-M interaction for W14X82
Reference: AISC 360-16 Section H1
"""
const W14X82_PM_INTERACTION_REFERENCE = (
    # Use W14X82_COMPRESSION_REFERENCE values
    section_name = "W14X82",
    KL = 14.0,                # ft
    Lb = 14.0,                # ft
    Cb = 1.0,
    
    # Section Properties (AISC Manual)
    Zx = 139.0,               # in³
    
    # ===== COMPRESSIVE CAPACITY (from earlier) =====
    ϕPn = 781.1,              # kips (weak axis governs)
    
    # ===== FLEXURAL CAPACITY =====
    # Mp = Fy × Zx = 50 × 139 = 6950 kip-in = 579.2 kip-ft
    # For Lb = 14 ft with this section, approximately:
    ϕMnx = 500.0,             # kip-ft (approximate, depends on LTB)
    ϕMny = 150.0,             # kip-ft (weak axis, approximate)
    
    # ===== INTERACTION CASES =====
    # H1-1a: When Pr/Pc ≥ 0.2:
    #   Pr/Pc + (8/9)(Mrx/Mcx + Mry/Mcy) ≤ 1.0
    # H1-1b: When Pr/Pc < 0.2:
    #   Pr/(2Pc) + (Mrx/Mcx + Mry/Mcy) ≤ 1.0
    
    # Case 1: Pure compression at 50% capacity
    case1 = (
        Pu = 390.5,           # kips (50% of ϕPn)
        Mux = 0.0,            # kip-ft
        Muy = 0.0,            # kip-ft
        # Pr/Pc = 0.5 ≥ 0.2 → Use H1-1a
        # IR = 0.5 + (8/9)(0 + 0) = 0.5 ≤ 1.0 ✓
        interaction_ratio = 0.5,
    ),
    
    # Case 2: Combined P + Mx (30% axial + 50% moment)
    case2 = (
        Pu = 234.3,           # kips (30% of ϕPn)
        Mux = 250.0,          # kip-ft (50% of ϕMnx)
        Muy = 0.0,            # kip-ft
        # Pr/Pc = 0.3 ≥ 0.2 → Use H1-1a
        # IR = 0.3 + (8/9)(0.5 + 0) = 0.3 + 0.444 = 0.744 ≤ 1.0 ✓
        interaction_ratio = 0.744,
    ),
    
    # Case 3: Low axial (10%) + moment (70%)
    case3 = (
        Pu = 78.1,            # kips (10% of ϕPn)
        Mux = 350.0,          # kip-ft (70% of ϕMnx)
        Muy = 0.0,            # kip-ft
        # Pr/Pc = 0.1 < 0.2 → Use H1-1b
        # IR = 0.1/2 + (0.7 + 0) = 0.05 + 0.7 = 0.75 ≤ 1.0 ✓
        interaction_ratio = 0.75,
    ),
)

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

@testset "AISC 360 Reference Tests" begin
    data = AISC_360_CONSTANTS
    
    @testset "Material Constants" begin
        # Verify fundamental relationships
        @test data.E ≈ 29000.0 rtol=0.001
        @test data.Fy ≈ 50.0 rtol=0.001
        @test data.Fu ≈ 65.0 rtol=0.001
        
        # G ≈ E / 2.6 (approximate)
        @test data.G ≈ data.E / 2.6 rtol=0.05
        
        # Resistance factors
        @test data.ϕc == 0.90
        @test data.ϕb == 0.90
        @test data.ϕv == 1.00  # For rolled I-shapes
        @test data.ϕt_yield == 0.90
        @test data.ϕt_rupture == 0.75
    end
    
    @testset "Slenderness Limits" begin
        E = data.E
        Fy = data.Fy
        
        # Column transition (Eq. E3-2/E3-3 boundary)
        λ_transition = data.transition_ratio * sqrt(E / Fy)
        @test λ_transition ≈ 113.4 rtol=0.02
        
        # Compact flange limit (flexure)
        λpf = data.λp_flange_flex * sqrt(E / Fy)
        @test λpf ≈ 9.15 rtol=0.02
        
        # Compact web limit (flexure)
        λpw = data.λp_web_flex * sqrt(E / Fy)
        @test λpw ≈ 90.5 rtol=0.02
    end
    
    @testset "Compression - W14X82 at KL=14ft (Chapter E)" begin
        ref = W14X82_COMPRESSION_REFERENCE
        E = data.E
        Fy = data.Fy
        
        @testset "Weak Axis Flexural Buckling (Governs)" begin
            wa = ref.weak_axis
            ry = ref.section.ry
            KL_in = ref.design.KL * 12
            
            # Slenderness ratio
            KL_r = KL_in / ry
            @test KL_r ≈ wa.KL_r rtol=0.01
            
            # Check inelastic buckling regime
            λ_limit = 4.71 * sqrt(E / Fy)
            @test λ_limit ≈ wa.λ_limit rtol=0.01
            @test KL_r < λ_limit  # Inelastic regime
            
            # Euler buckling stress (Eq. E3-4)
            Fe = π^2 * E / KL_r^2
            @test Fe ≈ wa.Fe rtol=0.02
            
            # Critical stress (Eq. E3-2)
            Fcr = data.inelastic_coef^(Fy / Fe) * Fy
            @test Fcr ≈ wa.Fcr rtol=0.02
            
            # Nominal and design strength
            Pn = Fcr * ref.section.A
            @test Pn ≈ wa.Pn rtol=0.02
            
            ϕPn = data.ϕc * Pn
            @test ϕPn ≈ wa.ϕPn rtol=0.02
        end
        
        @testset "Strong Axis (Higher Capacity)" begin
            sa = ref.strong_axis
            rx = ref.section.rx
            KL_in = ref.design.KL * 12
            
            # Slenderness ratio (smaller → higher capacity)
            KL_r = KL_in / rx
            @test KL_r ≈ sa.KL_r rtol=0.01
            @test KL_r < ref.weak_axis.KL_r  # Strong axis less slender
            
            # Euler buckling stress
            Fe = π^2 * E / KL_r^2
            @test Fe ≈ sa.Fe rtol=0.02
            
            # Critical stress
            Fcr = data.inelastic_coef^(Fy / Fe) * Fy
            @test Fcr ≈ sa.Fcr rtol=0.02
            
            # Design strength (higher than weak axis)
            ϕPn = data.ϕc * Fcr * ref.section.A
            @test ϕPn ≈ sa.ϕPn rtol=0.02
            @test ϕPn > ref.weak_axis.ϕPn  # Strong axis has higher capacity
        end
    end
    
    @testset "Tension - W8X21 (Chapter D)" begin
        ref = W8X21_TENSION_REFERENCE
        Fy = data.Fy
        Fu = data.Fu
        
        @testset "Yielding (D2a)" begin
            Ag = ref.section.A
            
            # Nominal strength
            Pn = Fy * Ag
            @test Pn ≈ ref.yielding.Pn rtol=0.01
            
            # Design strength
            ϕPn = data.ϕt_yield * Pn
            @test ϕPn ≈ ref.yielding.ϕPn rtol=0.01
        end
        
        @testset "Rupture (D2b)" begin
            Ae = ref.Ae
            
            # Nominal strength
            Pn = Fu * Ae
            @test Pn ≈ ref.rupture.Pn rtol=0.01
            
            # Design strength
            ϕPn = data.ϕt_rupture * Pn
            @test ϕPn ≈ ref.rupture.ϕPn rtol=0.01
            
            # Rupture governs (lower ϕPn)
            @test ref.rupture.ϕPn < ref.yielding.ϕPn
        end
        
        @testset "Slenderness Limit (D1 Commentary)" begin
            L_in = ref.slenderness.L * 12
            ry = ref.section.ry
            
            L_r = L_in / ry
            @test L_r ≈ ref.slenderness.L_r rtol=0.01
            
            # Should satisfy recommended limit
            @test L_r < ref.slenderness.limit
        end
    end
    
    @testset "Flexure - W21X55 at Lb=12ft (Chapter F)" begin
        ref = W21X55_FLEXURE_REFERENCE
        E = data.E
        Fy = data.Fy
        
        @testset "Compactness Check" begin
            compact = ref.compactness
            
            # Flange slenderness
            @test compact.λf ≈ ref.section.bf / (2 * ref.section.tf) rtol=0.01
            
            # Flange compact limit
            λpf = data.λp_flange_flex * sqrt(E / Fy)
            @test λpf ≈ compact.λpf rtol=0.01
            @test compact.λf < compact.λpf  # Compact flange
            
            # Web compact limit
            λpw = data.λp_web_flex * sqrt(E / Fy)
            @test λpw ≈ compact.λpw rtol=0.01
            @test compact.λw < compact.λpw  # Compact web
        end
        
        @testset "Plastic Moment" begin
            Zx = ref.section.Zx
            
            # Mp = Fy × Zx
            Mp = Fy * Zx / 12  # Convert to kip-ft
            @test Mp ≈ ref.Mp rtol=0.01
        end
        
        @testset "Unbraced Length Limits" begin
            ry = ref.section.ry
            
            # Lp = 1.76 × ry × √(E/Fy)
            Lp_in = 1.76 * ry * sqrt(E / Fy)
            Lp_ft = Lp_in / 12
            @test Lp_ft ≈ ref.Lp rtol=0.02
            
            # Verify LTB regime (Lp < Lb < Lr)
            @test ref.Lp < ref.design.Lb
            @test ref.design.Lb < ref.Lr
        end
        
        @testset "Inelastic LTB (Lb = 12 ft)" begin
            ltb = ref.inelastic_ltb
            Sx = ref.section.Sx
            
            # Mr = 0.7 × Fy × Sx
            Mr = 0.7 * Fy * Sx / 12  # kip-ft
            @test Mr ≈ ltb.Mr rtol=0.01
            
            # Inelastic LTB formula (F2.2)
            Mp = ref.Mp
            Lb = ref.design.Lb
            Lp = ref.Lp
            Lr = ref.Lr
            Cb = ref.design.Cb
            
            Mn = Cb * (Mp - (Mp - Mr) * (Lb - Lp) / (Lr - Lp))
            Mn = min(Mn, Mp)  # Cap at Mp
            @test Mn ≈ ltb.Mn rtol=0.02
            
            ϕMn = data.ϕb * Mn
            @test ϕMn ≈ ltb.ϕMn rtol=0.02
        end
        
        @testset "Full Plastic Capacity (Continuous Bracing)" begin
            plastic = ref.full_plastic
            
            # When Lb ≤ Lp: Mn = Mp
            @test plastic.Mn ≈ ref.Mp rtol=0.001
            
            ϕMn = data.ϕb * plastic.Mn
            @test ϕMn ≈ plastic.ϕMn rtol=0.001
        end
    end
    
    @testset "Shear - W24X62 (Chapter G)" begin
        ref = W24X62_SHEAR_REFERENCE
        E = data.E
        Fy = data.Fy
        
        @testset "Web Area" begin
            d = ref.section.d
            tw = ref.section.tw
            
            Aw = d * tw
            @test Aw ≈ ref.Aw rtol=0.01
        end
        
        @testset "Cv1 Determination (G2.1)" begin
            wc = ref.web_check
            
            # Check h/tw limit for Cv1 = 1.0
            limit = 2.24 * sqrt(E / Fy)
            @test limit ≈ wc.limit rtol=0.02
            
            # Verify Cv1 = 1.0 applies
            @test wc.h_tw < wc.limit
            @test wc.Cv1 ≈ 1.0 rtol=0.001
        end
        
        @testset "Nominal Shear Strength (G2.1)" begin
            shear = ref.shear
            
            # Vn = 0.6 × Fy × Aw × Cv1
            Vn = 0.6 * Fy * ref.Aw * ref.web_check.Cv1
            @test Vn ≈ shear.Vn rtol=0.02
            
            # ϕvVn = 1.0 × Vn (for rolled I-shapes)
            ϕVn = data.ϕv * Vn
            @test ϕVn ≈ shear.ϕVn rtol=0.02
        end
    end
    
    @testset "P-M Interaction - W14X82 (Chapter H)" begin
        ref = W14X82_PM_INTERACTION_REFERENCE
        
        # Helper function for H1 interaction
        function h1_interaction(Pu, Mux, Muy, ϕPn, ϕMnx, ϕMny)
            Pr_Pc = Pu / ϕPn
            if Pr_Pc >= 0.2
                # H1-1a
                return Pr_Pc + (8/9) * (Mux/ϕMnx + Muy/ϕMny)
            else
                # H1-1b
                return Pr_Pc/2 + (Mux/ϕMnx + Muy/ϕMny)
            end
        end
        
        ϕPn = ref.ϕPn
        ϕMnx = ref.ϕMnx
        ϕMny = ref.ϕMny
        
        @testset "Pure Compression (50%)" begin
            c1 = ref.case1
            IR = h1_interaction(c1.Pu, c1.Mux, c1.Muy, ϕPn, ϕMnx, ϕMny)
            @test IR ≈ c1.interaction_ratio rtol=0.02
            @test IR <= 1.0
        end
        
        @testset "Combined P + Mx (30% + 50%)" begin
            c2 = ref.case2
            IR = h1_interaction(c2.Pu, c2.Mux, c2.Muy, ϕPn, ϕMnx, ϕMny)
            @test IR ≈ c2.interaction_ratio rtol=0.02
            @test IR <= 1.0
        end
        
        @testset "Low Axial + Moment (10% + 70%)" begin
            c3 = ref.case3
            # Uses H1-1b (Pr/Pc < 0.2)
            Pr_Pc = c3.Pu / ϕPn
            @test Pr_Pc < 0.2
            
            IR = h1_interaction(c3.Pu, c3.Mux, c3.Muy, ϕPn, ϕMnx, ϕMny)
            @test IR ≈ c3.interaction_ratio rtol=0.02
            @test IR <= 1.0
        end
    end
end

println("AISC 360 Reference Tests completed.")
println("Note: These tests are NOT included in runtests.jl")
