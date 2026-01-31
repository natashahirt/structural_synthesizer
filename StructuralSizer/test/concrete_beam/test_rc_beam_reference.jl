# =============================================================================
# Reference Tests for Simply Supported RC Beam Design
# NOT INCLUDED IN runtests.jl - Standalone verification against StructurePoint
#
# IMPORTANT: These tests validate against published reference values.
# DO NOT MODIFY without verifying against source document.
#
# Source: DE-Simply-Supported-Reinforced-Concrete-Beam-Analysis-and-Design-ACI-318-14-spBeam-v1000.pdf
# Version: July-08-2025
# =============================================================================
#
# REFERENCE PROBLEM STATEMENT
# ===========================
# A simply supported rectangular RC beam with:
# - Span L = 25 ft (center-to-center)
# - Cross section: b = 12 in, h = 20 in
# - f'c = 4.35 ksi (normal weight, wc = 150 pcf)
# - fy = 60 ksi
# - DL = 0.82 kip/ft (EXCLUDES self-weight per document)
# - LL = 1.00 kip/ft
# - Clear cover = 1.5 in (ACI Table 20.6.1.3.1)
# - #9 bars for longitudinal, #3 bars for stirrups
#
# KEY RESULTS FROM SOURCE:
# - h_min = 18.75 in (ACI Table 9.3.1.1)
# - d = 17.56 in
# - wu = 2.58 k/ft
# - Vu = 32.30 kips
# - Mu = 201.88 kip-ft
# - As,req = 2.872 in², provide 3-#9 (As = 3.00 in²)
# - φVc = 20.85 kips, use #3 @ 8.3"
# - Δ_LL = 0.634 in < L/360 = 0.833 in
# =============================================================================

using Test
using Unitful
using Unitful: @u_str

# =============================================================================
# VERIFIED REFERENCE DATA
# Extracted directly from StructurePoint DE-Simply-Supported-Beam example
# =============================================================================

"""
Reference data from StructurePoint Simply Supported RC Beam Design Example.
All values verified against source document.
"""
const RC_BEAM_STRUCTUREPOINT = (
    # ===== GEOMETRY =====
    geometry = (
        L = 25.0,                 # ft - span length (c/c)
        L_in = 300.0,             # in - span length
        b = 12.0,                 # in - beam width
        h = 20.0,                 # in - beam depth
        cover = 1.50,             # in - clear cover (Table 20.6.1.3.1)
        d_stirrup = 0.375,        # in - #3 stirrup diameter
        d_bar = 1.128,            # in - #9 bar diameter
        A_bar = 1.00,             # in² - #9 bar area
        # d = h - cover - d_stirrup - d_bar/2
        # d = 20 - 1.50 - 0.375 - 1.128/2 = 17.56 in
        d = 17.56,                # in - effective depth
    ),

    # ===== MATERIALS =====
    materials = (
        fc = 4350.0,              # psi - concrete compressive strength
        fy = 60000.0,             # psi - steel yield strength
        wc = 150.0,               # pcf - concrete unit weight
        # Ec = wc^1.5 × 33 × √f'c = 150^1.5 × 33 × √4350 = 3998.5 ksi
        Ec = 3998.5,              # ksi - concrete modulus (ACI 19.2.2.1.a)
        Es = 29000.0,             # ksi - steel modulus
        # β1 = 0.85 - 0.05(f'c - 4000)/1000 for 4000 < f'c ≤ 8000 psi
        # β1 = 0.85 - 0.05(4350 - 4000)/1000 = 0.83
        β1 = 0.83,                # stress block factor (Table 22.2.2.4.3)
        # n = Es / Ec = 29000 / 3998.5 = 7.25
        n = 7.25,                 # modular ratio
    ),

    # ===== LOADS (from pg. 4) =====
    # NOTE: Self-weight is EXCLUDED per reference document
    loads = (
        DL = 0.82,                # k/ft - dead load (excludes self-weight)
        LL = 1.00,                # k/ft - live load
        # wu = 1.2×DL + 1.6×LL = 1.2×0.82 + 1.6×1.00 = 2.58 k/ft
        wu = 2.58,                # k/ft - factored load
    ),

    # ===== MINIMUM THICKNESS (from pg. 4) =====
    # ACI 318-14 Table 9.3.1.1 for non-prestressed beams
    thickness_limits = (
        # Simply supported: h_min = L/16 = 300/16 = 18.75 in
        h_min = 18.75,            # in
    ),

    # ===== STRUCTURAL ANALYSIS (from pg. 6-7) =====
    analysis = (
        # Vu = wu × L / 2 = 2.58 × 25 / 2 = 32.30 kips
        Vu = 32.30,               # kips - maximum shear at support
        # Mu = wu × L² / 8 = 2.58 × 25² / 8 = 201.88 kip-ft
        Mu = 201.88,              # kip-ft - maximum moment at midspan
    ),

    # ===== FLEXURAL DESIGN (from pg. 5-8) =====
    flexural = (
        # Initial iteration:
        # jd = 0.889×d = 0.889×17.56 = 15.62 in
        jd_assumed = 15.62,       # in - assumed lever arm
        # As = Mu / (φ×fy×jd) = 201.88×12000 / (0.9×60000×15.62)
        As_initial = 2.872,       # in² - initial steel area calculation
        
        # Refined iteration:
        # a = As×fy / (0.85×f'c×b) = 2.872×60000 / (0.85×4350×12) = 3.88 in
        a = 3.88,                 # in - stress block depth
        # c = a / β1 = 3.88 / 0.83 = 4.67 in
        c = 4.67,                 # in - neutral axis depth
        # εt = 0.003×(dt - c)/c = 0.003×(17.56 - 4.67)/4.67 = 0.0083
        εt = 0.0083,              # in/in - tensile strain (> 0.005 → tension-controlled)
        
        # Final As = Mu / [φ×fy×(d - a/2)]
        # = 201.88×12000 / [0.9×60000×(17.56 - 3.88/2)] = 2.872 in²
        As_final = 2.872,         # in²
        
        # Minimum reinforcement (ACI 9.6.1.2):
        # (a) 3√f'c × bw × d / fy = 3×√4350×12×17.56/60000 = 0.695 in²
        As_min_a = 0.695,         # in² (Eq. 9.6.1.2a)
        # (b) 200 × bw × d / fy = 200×12×17.56/60000 = 0.702 in²
        As_min_b = 0.702,         # in² (Eq. 9.6.1.2b)
        As_min = 0.702,           # in² (governs)
        
        # Provided: 3 - #9 bars
        n_bars = 3,
        As_provided = 3.00,       # in²
        
        # Spacing:
        s_provided = 3.38,        # in - actual bar spacing
        s_min = 2.26,             # in - minimum spacing (CRSI)
        s_max = 10.31,            # in - maximum spacing (Table 24.3.2)
    ),

    # ===== SHEAR DESIGN (from pg. 8-10) =====
    shear = (
        # Vu@d = Vu × (L/2 - d) / (L/2) = 32.3 × (150 - 17.56) / 150 = 28.52 kips
        Vu_at_d = 28.52,          # kips - design shear at d from support
        
        # Vc = 2×λ×√f'c×bw×d / 1000 = 2×1×√4350×12×17.56/1000 = 27.80 kips
        Vc = 27.80,               # kips - (implied from φVc/φ)
        # φVc = 0.75 × Vc = 20.85 kips (per document)
        φVc = 20.85,              # kips
        
        # Vs = Vu@d/φ - Vc = 28.52/0.75 - 27.80 = 10.23 kips
        Vs_req = 10.23,           # kips
        
        # Maximum Vs = 8×√f'c×bw×d / 1000 = 111.19 kips → section adequate
        Vs_max = 111.19,          # kips
        
        # Minimum stirrup requirements:
        # Avs_min = max(0.75√f'c×bw/fyt, 50×bw/fyt)
        # = max(0.75×√4350×12/60000, 50×12/60000)
        # = max(0.0099, 0.0100) = 0.0100 in²/in
        Avs_min = 0.0100,         # in²/in
        Avs_req = 0.0097,         # in²/in (from demand)
        
        # Maximum spacing: min(d/2, 24") = min(8.78, 24) = 8.78 in
        s_max = 8.78,             # in (governs)
        
        # Provided: #3 @ 8.3"
        Av = 0.22,                # in² - 2 legs × 0.11
        s_provided = 8.30,        # in
        
        # φVn = φ(Av/s × fyt × d + Vc) = 0.75(0.22/8.3 × 60 × 17.56 + 27.80) = 41.79 kips
        φVn = 41.79,              # kips > Vu@d = 28.52 kips ✓
        
        # Distance where stirrups can stop:
        x_stop = 101.59,          # in from support face
    ),

    # ===== DEFLECTION (from pg. 11-14) =====
    deflection = (
        # Gross moment of inertia: Ig = b×h³/12 = 12×20³/12 = 8000 in⁴
        Ig = 8000.0,              # in⁴
        
        # Cracking moment parameters:
        # fr = 7.5×λ×√f'c = 7.5×1×√4350 = 494.66 psi
        fr = 494.66,              # psi - modulus of rupture (Eq. 19.2.3.1)
        yt = 10.0,                # in - distance to tension fiber
        # Mcr = fr×Ig/(yt×12000) = 494.66×8000/(10×12000) = 32.98 kip-ft
        Mcr = 32.98,              # kip-ft - cracking moment
        
        # Cracked section analysis:
        # B = b/(n×As) = 12/(7.25×3) = 0.552 in⁻¹
        B = 0.552,                # in⁻¹
        # kd = (√(2×d×B+1) - 1) / B = 6.37 in
        kd = 6.37,                # in - neutral axis depth (cracked)
        # Icr = b×(kd)³/3 + n×As×(d-kd)² = 3759 in⁴
        Icr = 3759.0,             # in⁴ - cracked moment of inertia
        
        # Service load moments:
        # M_D = wD×L²/8 = 0.82×25²/8 = 64.06 kip-ft
        Ma_D = 64.06,             # kip-ft
        # M_D+L = (wD+wL)×L²/8 = 1.82×25²/8 = 142.19 kip-ft
        Ma_DL = 142.19,           # kip-ft
        
        # Effective moment of inertia:
        # Ie = Icr + (Ig - Icr)×(Mcr/Ma)³
        # Ie_D = 3759 + (8000-3759)×(32.98/64.06)³ = 4337 in⁴
        Ie_D = 4337.0,            # in⁴
        # Ie_D+L = 3759 + (8000-3759)×(32.98/142.19)³ = 3812 in⁴
        Ie_DL = 3812.0,           # in⁴
        
        # Immediate deflections (5wL⁴/384EI):
        # Δ_D = 5×820×300⁴ / (384×3998.5×1000×4337) = 0.416 in
        Δ_D = 0.416,              # in - dead load deflection
        # Δ_D+L = 5×1820×300⁴ / (384×3998.5×1000×3812) = 1.050 in
        Δ_DL = 1.050,             # in - total deflection
        # Δ_LL = Δ_D+L - Δ_D = 0.634 in
        Δ_LL = 0.634,             # in - live load deflection
        
        # Limit: L/360 = 300/360 = 0.833 in
        Δ_limit = 0.833,          # in (Table 24.2.2)
    ),
)

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

@testset "Simply Supported RC Beam Reference Tests (StructurePoint)" begin
    data = RC_BEAM_STRUCTUREPOINT
    
    @testset "Geometry Verification" begin
        # Effective depth: d = h - cover - d_stirrup - d_bar/2
        d_calc = data.geometry.h - data.geometry.cover - 
                 data.geometry.d_stirrup - data.geometry.d_bar / 2
        @test d_calc ≈ data.geometry.d rtol=0.01
        
        # Span conversion
        @test data.geometry.L * 12 ≈ data.geometry.L_in rtol=0.001
    end
    
    @testset "Material Properties" begin
        fc = data.materials.fc
        wc = data.materials.wc
        
        # Concrete modulus: Ec = wc^1.5 × 33 × √f'c / 1000
        Ec_calc = (wc^1.5) * 33 * sqrt(fc) / 1000
        @test Ec_calc ≈ data.materials.Ec rtol=0.01
        
        # Beta1: 0.85 - 0.05×(f'c - 4000)/1000 for f'c > 4000 psi
        β1_calc = 0.85 - 0.05 * (fc - 4000) / 1000
        @test β1_calc ≈ data.materials.β1 rtol=0.01
        
        # Modular ratio
        n_calc = data.materials.Es / data.materials.Ec
        @test n_calc ≈ data.materials.n rtol=0.01
    end
    
    @testset "Minimum Thickness (ACI Table 9.3.1.1)" begin
        # Simply supported beam: h_min = L/16
        h_min_calc = data.geometry.L_in / 16
        @test h_min_calc ≈ data.thickness_limits.h_min rtol=0.01
        
        # Selected depth satisfies minimum
        @test data.geometry.h ≥ data.thickness_limits.h_min
    end
    
    @testset "Factored Loads" begin
        DL = data.loads.DL
        LL = data.loads.LL
        
        # wu = 1.2D + 1.6L
        wu_calc = 1.2 * DL + 1.6 * LL
        @test wu_calc ≈ data.loads.wu rtol=0.01
    end
    
    @testset "Structural Analysis - Simply Supported" begin
        wu = data.loads.wu
        L = data.geometry.L
        
        # Maximum shear: Vu = wu × L / 2
        Vu_calc = wu * L / 2
        @test Vu_calc ≈ data.analysis.Vu rtol=0.01
        
        # Maximum moment: Mu = wu × L² / 8
        Mu_calc = wu * L^2 / 8
        @test Mu_calc ≈ data.analysis.Mu rtol=0.01
    end
    
    @testset "Flexural Design" begin
        fc = data.materials.fc
        fy = data.materials.fy
        β1 = data.materials.β1
        b = data.geometry.b
        d = data.geometry.d
        Mu = data.analysis.Mu
        
        @testset "Required Reinforcement" begin
            φ = 0.9
            
            # Assumed lever arm
            jd = 0.889 * d
            @test jd ≈ data.flexural.jd_assumed rtol=0.01
            
            # Initial As estimate: Mu / (φ × fy × jd)
            As_init = Mu * 12000 / (φ * fy * jd)
            @test As_init ≈ data.flexural.As_initial rtol=0.02
            
            # Stress block depth: a = As × fy / (0.85 × f'c × b)
            As = data.flexural.As_final
            a_calc = As * fy / (0.85 * fc * b)
            @test a_calc ≈ data.flexural.a rtol=0.02
            
            # Neutral axis: c = a / β1
            c_calc = a_calc / β1
            @test c_calc ≈ data.flexural.c rtol=0.02
            
            # Tensile strain: εt = 0.003 × (d - c) / c
            εt_calc = 0.003 * (d - c_calc) / c_calc
            @test εt_calc ≈ data.flexural.εt rtol=0.05
            
            # Verify tension-controlled
            @test εt_calc > 0.005
        end
        
        @testset "Minimum Reinforcement (ACI 9.6.1.2)" begin
            # Eq. 9.6.1.2(a): 3√f'c × bw × d / fy
            As_min_a = 3 * sqrt(fc) * b * d / fy
            @test As_min_a ≈ data.flexural.As_min_a rtol=0.02
            
            # Eq. 9.6.1.2(b): 200 × bw × d / fy
            As_min_b = 200 * b * d / fy
            @test As_min_b ≈ data.flexural.As_min_b rtol=0.01
            
            # Governing minimum
            As_min = max(As_min_a, As_min_b)
            @test As_min ≈ data.flexural.As_min rtol=0.01
            
            # Required > minimum
            @test data.flexural.As_final > data.flexural.As_min
        end
        
        @testset "Provided Reinforcement" begin
            # Provided area
            As_prov = data.flexural.n_bars * data.geometry.A_bar
            @test As_prov ≈ data.flexural.As_provided rtol=0.001
            
            # Provided ≥ required
            @test data.flexural.As_provided ≥ data.flexural.As_final
            
            # Spacing within limits
            @test data.flexural.s_provided ≥ data.flexural.s_min
            @test data.flexural.s_provided ≤ data.flexural.s_max
        end
    end
    
    @testset "Shear Design" begin
        fc = data.materials.fc
        fy = data.materials.fy
        b = data.geometry.b
        d = data.geometry.d
        L_in = data.geometry.L_in
        Vu = data.analysis.Vu
        
        @testset "Design Shear at d" begin
            # Vu@d = Vu × (L/2 - d) / (L/2)
            Vu_at_d_calc = Vu * (L_in / 2 - d) / (L_in / 2)
            @test Vu_at_d_calc ≈ data.shear.Vu_at_d rtol=0.01
        end
        
        @testset "Concrete Shear Capacity (ACI 22.5.5.1)" begin
            φ = 0.75
            λ = 1.0  # normal weight concrete
            
            # Vc = 2×λ×√f'c×bw×d
            Vc_calc = 2 * λ * sqrt(fc) * b * d / 1000
            @test Vc_calc ≈ data.shear.Vc rtol=0.02
            
            # φVc
            φVc_calc = φ * Vc_calc
            @test φVc_calc ≈ data.shear.φVc rtol=0.02
            
            # Stirrups required since Vu@d > φVc/2
            @test data.shear.Vu_at_d > data.shear.φVc / 2
        end
        
        @testset "Steel Shear Requirement" begin
            φ = 0.75
            
            # Vs = Vu@d/φ - Vc
            Vs_calc = data.shear.Vu_at_d / φ - data.shear.Vc
            @test Vs_calc ≈ data.shear.Vs_req rtol=0.02
            
            # Section adequate: Vs < 8√f'c × bw × d
            Vs_max_calc = 8 * sqrt(fc) * b * d / 1000
            @test Vs_max_calc ≈ data.shear.Vs_max rtol=0.02
            @test data.shear.Vs_req < data.shear.Vs_max
        end
        
        @testset "Stirrup Spacing (ACI 9.7.6.2.2)" begin
            # Vs < 4√f'c×bw×d, so s_max = min(d/2, 24")
            s_max_calc = min(d / 2, 24.0)
            @test s_max_calc ≈ data.shear.s_max rtol=0.01
            
            # Provided spacing within limit
            @test data.shear.s_provided ≤ data.shear.s_max
        end
        
        @testset "Final Shear Capacity" begin
            φ = 0.75
            
            # φVn = φ(Av/s × fyt × d + Vc)
            fyt = fy  # Same for stirrups
            φVn_calc = φ * (data.shear.Av / data.shear.s_provided * fyt * d / 1000 + data.shear.Vc)
            @test φVn_calc ≈ data.shear.φVn rtol=0.02
            
            # Capacity exceeds demand
            @test data.shear.φVn > data.shear.Vu_at_d
        end
    end
    
    @testset "Deflection (Serviceability)" begin
        Ec = data.materials.Ec
        fc = data.materials.fc
        n = data.materials.n
        b = data.geometry.b
        h = data.geometry.h
        d = data.geometry.d
        As = data.flexural.As_provided
        L = data.geometry.L_in
        
        @testset "Section Properties" begin
            # Gross moment of inertia: Ig = b×h³/12
            Ig_calc = b * h^3 / 12
            @test Ig_calc ≈ data.deflection.Ig rtol=0.001
            
            # Modulus of rupture: fr = 7.5×√f'c
            λ = 1.0
            fr_calc = 7.5 * λ * sqrt(fc)
            @test fr_calc ≈ data.deflection.fr rtol=0.01
            
            # Distance to tension fiber
            yt_calc = h / 2
            @test yt_calc ≈ data.deflection.yt rtol=0.001
        end
        
        @testset "Cracking Moment" begin
            Ig = data.deflection.Ig
            fr = data.deflection.fr
            yt = data.deflection.yt
            
            # Mcr = fr × Ig / (yt × 12000) [convert to kip-ft]
            Mcr_calc = fr * Ig / (yt * 12000)
            @test Mcr_calc ≈ data.deflection.Mcr rtol=0.01
        end
        
        @testset "Cracked Section Analysis" begin
            # B = b / (n × As)
            B_calc = b / (n * As)
            @test B_calc ≈ data.deflection.B rtol=0.01
            
            # kd = (√(2×d×B + 1) - 1) / B
            B = data.deflection.B
            kd_calc = (sqrt(2 * d * B + 1) - 1) / B
            @test kd_calc ≈ data.deflection.kd rtol=0.02
            
            # Icr = b×(kd)³/3 + n×As×(d-kd)²
            kd = data.deflection.kd
            Icr_calc = b * kd^3 / 3 + n * As * (d - kd)^2
            @test Icr_calc ≈ data.deflection.Icr rtol=0.02
        end
        
        @testset "Service Load Moments" begin
            DL = data.loads.DL
            LL = data.loads.LL
            L_ft = data.geometry.L
            
            # Dead load moment: wD×L²/8
            Ma_D_calc = DL * L_ft^2 / 8
            @test Ma_D_calc ≈ data.deflection.Ma_D rtol=0.01
            
            # Total load moment: (wD+wL)×L²/8
            Ma_DL_calc = (DL + LL) * L_ft^2 / 8
            @test Ma_DL_calc ≈ data.deflection.Ma_DL rtol=0.01
        end
        
        @testset "Effective Moment of Inertia (ACI 24.2.3.5a)" begin
            Ig = data.deflection.Ig
            Icr = data.deflection.Icr
            Mcr = data.deflection.Mcr
            Ma_D = data.deflection.Ma_D
            Ma_DL = data.deflection.Ma_DL
            
            # Section is cracked (Ma > Mcr)
            @test Ma_D > Mcr
            @test Ma_DL > Mcr
            
            # Ie = Icr + (Ig - Icr) × (Mcr/Ma)³
            Ie_D_calc = Icr + (Ig - Icr) * (Mcr / Ma_D)^3
            @test Ie_D_calc ≈ data.deflection.Ie_D rtol=0.02
            
            Ie_DL_calc = Icr + (Ig - Icr) * (Mcr / Ma_DL)^3
            @test Ie_DL_calc ≈ data.deflection.Ie_DL rtol=0.02
        end
        
        @testset "Immediate Deflections" begin
            w_D = data.loads.DL * 1000 / 12  # lb/in
            w_DL = (data.loads.DL + data.loads.LL) * 1000 / 12  # lb/in
            Ie_D = data.deflection.Ie_D
            Ie_DL = data.deflection.Ie_DL
            
            # Δ = 5×w×L⁴ / (384×E×I)
            Δ_D_calc = 5 * w_D * L^4 / (384 * Ec * 1000 * Ie_D)
            @test Δ_D_calc ≈ data.deflection.Δ_D rtol=0.05
            
            Δ_DL_calc = 5 * w_DL * L^4 / (384 * Ec * 1000 * Ie_DL)
            @test Δ_DL_calc ≈ data.deflection.Δ_DL rtol=0.05
            
            # Live load deflection
            Δ_LL_calc = data.deflection.Δ_DL - data.deflection.Δ_D
            @test Δ_LL_calc ≈ data.deflection.Δ_LL rtol=0.02
        end
        
        @testset "Deflection Limits (Table 24.2.2)" begin
            # L/360 for floors supporting non-structural elements
            Δ_limit_calc = L / 360
            @test Δ_limit_calc ≈ data.deflection.Δ_limit rtol=0.01
            
            # Live load deflection within limit
            @test data.deflection.Δ_LL < data.deflection.Δ_limit
        end
    end
end

println("Simply Supported RC Beam Reference Tests completed.")
println("Note: These tests are NOT included in runtests.jl")
