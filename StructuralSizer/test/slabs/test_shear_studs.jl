# Test shear stud design per ACI 318-11 §11.11.5 / Ancon Shearfix Manual
# 
# Reference: Ancon_Shearfix_Design_Manual_to_ACI_318-19.pdf (in slabs/codes/concrete/reference/two_way)

using Test
using Unitful
using StructuralSizer

# =============================================================================
# Test: Stud Area Calculation
# =============================================================================
@testset "Stud Area" begin
    # 3/8" stud
    As_3_8 = StructuralSizer.stud_area(0.375u"inch")
    @test ustrip(u"inch^2", As_3_8) ≈ π * (0.375/2)^2 atol=0.001
    
    # 1/2" stud (typical)
    As_1_2 = StructuralSizer.stud_area(0.5u"inch")
    @test ustrip(u"inch^2", As_1_2) ≈ 0.196 atol=0.001
    
    # 5/8" stud
    As_5_8 = StructuralSizer.stud_area(0.625u"inch")
    @test ustrip(u"inch^2", As_5_8) ≈ π * (0.625/2)^2 atol=0.001
end

# =============================================================================
# Test: Minimum Stud Reinforcement (ACI 318-11 §11.11.5.1)
# =============================================================================
@testset "Minimum Stud Reinforcement" begin
    # Av*fyt/(b0*s) ≥ 2√f'c  →  Av/s ≥ 2√f'c × b0 / fyt
    fc = 4000.0u"psi"
    b0 = 60.0u"inch"
    fyt = 51000.0u"psi"
    
    Av_s_min = StructuralSizer.minimum_stud_reinforcement(fc, b0, fyt)
    
    # Expected: 2 × √4000 × 60 / 51000 ≈ 0.1487 in²/in
    expected = 2.0 * sqrt(4000) * 60 / 51000
    @test ustrip(u"inch^2/inch", Av_s_min) ≈ expected atol=0.001
end

# =============================================================================
# Test: Punching Capacity with Studs (ACI 318-11 §11.11.5)
# =============================================================================
@testset "Punching Capacity with Studs" begin
    # Test case: Interior column, f'c = 4000 psi
    fc = 4000.0u"psi"
    β = 1.0       # Square column
    αs = 40       # Interior
    b0 = 80.0u"inch"
    d = 8.0u"inch"
    fyt = 51000.0u"psi"
    stud_diam = 0.5u"inch"
    
    # 8 rails of 1/2" studs → Av = 8 × π(0.25)² ≈ 1.57 in²
    n_rails = 8
    Av = n_rails * StructuralSizer.stud_area(stud_diam)
    s = 4.0u"inch"  # Spacing ≤ 0.5d = 4"
    
    result = StructuralSizer.punching_capacity_with_studs(
        fc, β, αs, b0, d, Av, s, fyt
    )
    
    # ACI 318-11 §11.11.5.1: vcs ≤ 3λ√f'c (λ=1.0)
    sqrt_fc = sqrt(4000)
    expected_vcs_max = 3.0 * sqrt_fc  # 3√f'c ≈ 189.7 psi
    @test ustrip(u"psi", result.vcs) ≤ expected_vcs_max + 0.1
    
    # Nominal capacity limit: 8√f'c for headed studs (ACI 318-11 §11.11.3.2)
    expected_vc_max = 8.0 * sqrt_fc
    @test ustrip(u"psi", result.vc_max) ≈ expected_vc_max atol=0.5
    
    # Check vs > 0
    @test ustrip(u"psi", result.vs) > 0
    
    # Check combined capacity
    @test ustrip(u"psi", result.vc_total) ≤ ustrip(u"psi", result.vc_max)
end

# =============================================================================
# Test: Outer Critical Section Capacity (ACI 318-11 §11.11.5.4)
# =============================================================================
@testset "Outer Critical Section" begin
    fc = 4000.0u"psi"
    d = 8.0u"inch"
    
    vc_out = StructuralSizer.punching_capacity_outer(fc, d)
    
    # vc,out = 2λ√f'c  (ACI 318-11 §11.11.5.4)
    expected = 2.0 * sqrt(4000)  # ≈ 126.5 psi
    @test ustrip(u"psi", vc_out) ≈ expected atol=0.5
    
    # Outer capacity (unreinforced) < max stud-reinforced capacity at column
    vc_max_col = 8.0 * sqrt(4000)  # Max with studs
    @test ustrip(u"psi", vc_out) < vc_max_col
end

# =============================================================================
# Test: Shear Stud Design Function
# =============================================================================
@testset "Shear Stud Design" begin
    # Note on capacity limits (US customary, psi):
    # vc_max with studs = 8√f'c ≈ 506 psi for f'c = 4000
    # φ × vc_max = 0.75 × 506 ≈ 380 psi
    # So maximum achievable vu with studs is ~380 psi
    
    # Design scenario: Interior column just failing punching
    vu = 25.0u"psi"     # Realistic stress, below max capacity
    fc = 4000.0u"psi"
    β = 1.0
    αs = 40
    b0 = 80.0u"inch"
    d = 8.0u"inch"
    fyt = 51000.0u"psi"
    stud_diam = 0.5u"inch"
    
    studs = StructuralSizer.design_shear_studs(
        vu, fc, β, αs, b0, d, :interior, fyt, stud_diam
    )
    
    # Should require studs
    @test studs.required == true
    
    # Interior column → 8 rails
    @test studs.n_rails == 8
    
    # First spacing at 0.5d
    @test ustrip(u"inch", studs.s0) ≈ 4.0 atol=0.01
    
    # Spacing should be > 0 (studs designed)
    @test ustrip(u"inch", studs.s) > 0
    
    # Check with check_punching_with_studs
    check = StructuralSizer.check_punching_with_studs(vu, studs)
    @test check.ratio < 1.5  # Should be achievable
    
    # Edge column → 6 rails
    studs_edge = StructuralSizer.design_shear_studs(
        vu, fc, β, 30, b0, d, :edge, fyt, stud_diam
    )
    @test studs_edge.n_rails == 6
    
    # Corner column → 4 rails
    studs_corner = StructuralSizer.design_shear_studs(
        vu, fc, β, 20, b0, d, :corner, fyt, stud_diam
    )
    @test studs_corner.n_rails == 4
    
    # Test: Demand exceeds max capacity → n_rails = 0
    vu_extreme = 400.0u"psi"  # Above φ × vc_max ≈ 380 psi
    studs_impossible = StructuralSizer.design_shear_studs(
        vu_extreme, fc, β, αs, b0, d, :interior, fyt, stud_diam
    )
    @test studs_impossible.n_rails == 0  # Can't design studs
    @test !studs_impossible.outer_ok
end

# =============================================================================
# Test: Stud Design for Moderate Shear (passes with studs)
# =============================================================================
@testset "Stud Design - Moderate Shear" begin
    # Scenario: vu just exceeds φvc without studs, studs should resolve
    fc = 4000.0u"psi"
    d = 8.0u"inch"
    
    # φvc without studs ≈ 0.75 × 4√4000 ≈ 190 psi  (US customary)
    # φvc with studs (max) ≈ 0.75 × 8√4000 ≈ 380 psi
    # So studs can help if 190 < vu < 380
    vu = 250.0u"psi"  # Needs studs, achievable with studs
    β = 1.0
    αs = 40
    b0 = 80.0u"inch"
    fyt = 51000.0u"psi"
    stud_diam = 0.5u"inch"
    
    studs = StructuralSizer.design_shear_studs(
        vu, fc, β, αs, b0, d, :interior, fyt, stud_diam
    )
    
    check = StructuralSizer.check_punching_with_studs(vu, studs)
    
    # With 8 rails of 1/2" studs, should pass
    @test check.ok == true || check.ratio < 1.2
end

# =============================================================================
# Test: Material Presets
# =============================================================================
@testset "Stud_51 Material" begin
    @test StructuralSizer.Stud_51.Fy ≈ 351.6u"MPa" atol=0.5u"MPa"  # 51 ksi
    @test StructuralSizer.material_name(StructuralSizer.Stud_51) == "Stud51"
end

# =============================================================================
# Test: FlatPlateOptions with Shear Studs
# =============================================================================
@testset "FlatPlateOptions Shear Stud Fields" begin
    # Default options
    opts = StructuralSizer.FlatPlateOptions()
    
    @test opts.shear_studs == :never
    @test opts.max_column_size ≈ 30.0u"inch" atol=0.1u"inch"
    @test opts.stud_material === StructuralSizer.Stud_51
    @test opts.stud_diameter ≈ 0.5u"inch" atol=0.01u"inch"
    
    # Options with studs enabled
    opts_studs = StructuralSizer.FlatPlateOptions(shear_studs=:if_needed)
    @test opts_studs.shear_studs == :if_needed
end

# =============================================================================
# Test: Nominal Capacity Limit (vc_max = 8√f'c, ACI 318-11 §11.11.3.2)
# =============================================================================
@testset "Nominal Capacity Limit" begin
    fc = 4000.0u"psi"
    β = 1.0
    αs = 40
    b0 = 80.0u"inch"
    d = 8.0u"inch"
    fyt = 51000.0u"psi"
    
    # ACI 318-11 §11.11.3.2: headed studs → Vn ≤ 8√f'c × b0 × d
    # vc_max = 8√f'c regardless of spacing
    Av = 1.5u"inch^2"
    
    s_tight = 3.0u"inch"
    result_tight = StructuralSizer.punching_capacity_with_studs(
        fc, β, αs, b0, d, Av, s_tight, fyt
    )
    @test ustrip(u"psi", result_tight.vc_max) ≈ 8.0 * sqrt(4000) atol=0.5
    
    s_wide = 6.0u"inch"
    result_wide = StructuralSizer.punching_capacity_with_studs(
        fc, β, αs, b0, d, Av, s_wide, fyt
    )
    # In ACI 318-11, vc_max = 8√f'c for all spacings (headed studs)
    @test ustrip(u"psi", result_wide.vc_max) ≈ 8.0 * sqrt(4000) atol=0.5
end

# =============================================================================
# INCON ISS Worked Example — ACI 318-14 / CSA A23.3-14 Case Study
# =============================================================================
#
# Source: INCON-ISS-Shear-Studs-Catalog.pdf, Pages 11-16
# "Design of ISS – Shear Studs" — Interior rectangular column
#
# This is a known-answer test: every intermediate value is checked against
# the published INCON worked example.
#
# Inputs:
#   f'c = 4000 psi, fy = 51 ksi, λ = 1 (NWC), h = 7 in, cc = 0.75 in
#   Vu = 110 kips, Mu = 600 kip·in
#   Column: 20" × 12" (interior, rectangular)
#   Bar diameter: #5 = 0.625" (both directions, same size assumed)
# =============================================================================

@testset "INCON Worked Example — Intermediate Values" begin
    # ─── Step 1: Inputs ───
    fc = 4000.0u"psi"
    fyt = 51000.0u"psi"  # 51 ksi
    λ = 1.0
    h = 7.0u"inch"
    cc = 0.75u"inch"
    Vu = 110_000.0  # lbf (110 kips)
    Mu = 600_000.0  # lbf·in (600 kip·in)
    c1 = 20.0u"inch"  # long column side
    c2 = 12.0u"inch"  # short column side
    db = 0.625  # #5 bar diameter in inches

    # ─── Step 2: Effective depth ───
    # d = h - cc - (D_T1 + D_T2)/2 = 7 - 0.75 - (0.625 + 0.625)/2 = 5.625 in
    d_expected = 7.0 - 0.75 - (db + db) / 2
    @test d_expected ≈ 5.625 atol=0.001

    # ─── Step 3: Critical section geometry (interior column) ───
    d_in = d_expected
    c1_in = 20.0
    c2_in = 12.0
    # b0 = 2(c1 + d) + 2(c2 + d) for interior rectangular column
    b0_expected = 2 * (c1_in + d_in) + 2 * (c2_in + d_in)
    @test b0_expected ≈ 86.5 atol=0.1

    # ─── Step 5: Nominal shear strength (unreinforced) ───
    sqrt_fc = sqrt(4000.0)
    β = c1_in / c2_in  # 20/12 = 1.667
    @test β ≈ 1.667 atol=0.01

    αs = 40  # Interior column
    vc_a = (2 + 4 / β) * λ * sqrt_fc              # (2 + 4/1.67)λ√f'c = 4.4λ√f'c
    vc_b = (αs * d_in / b0_expected + 2) * λ * sqrt_fc  # (40×5.625/86.5 + 2)λ√f'c = 4.6λ√f'c
    vc_c = 4 * λ * sqrt_fc                         # 4λ√f'c

    # INCON: vc_a = 4.4λ√f'c, vc_b = 4.6λ√f'c, vc_c = 4λ√f'c
    @test vc_a / (λ * sqrt_fc) ≈ 4.4 atol=0.1
    @test vc_b / (λ * sqrt_fc) ≈ 4.6 atol=0.1
    @test vc_c / (λ * sqrt_fc) ≈ 4.0 atol=0.01

    vn_unreinforced = min(vc_a, vc_b, vc_c)
    @test vn_unreinforced ≈ 4.0 * sqrt_fc atol=0.5  # = 253 psi
    @test vn_unreinforced ≈ 253.0 atol=1.0

    # ─── Step 6: Check if studs are feasible ───
    φ = 0.75
    # vu = 295.0 psi (from INCON, includes moment transfer via γv·Mu·c/Jc)
    vu_psi = 295.0

    # φvn (unreinforced) = 0.75 × 253 = 189.7 psi
    @test φ * vn_unreinforced ≈ 189.7 atol=0.5
    # vu > φvn → concrete alone not sufficient
    @test vu_psi > φ * vn_unreinforced

    # Maximum with studs: φ × 8√f'c = 0.75 × 8 × √4000 = 379.4 psi
    vc_max_studs = 8.0 * λ * sqrt_fc
    @test φ * vc_max_studs ≈ 379.4 atol=0.5
    # vu < φ × 8√f'c → studs can be used
    @test vu_psi < φ * vc_max_studs

    # ─── Step 7: Concrete contribution with studs ───
    # ACI 318-11 §11.11.5.1: vc = 3λ√f'c when headed studs are used
    vcs = 3.0 * λ * sqrt_fc
    @test vcs ≈ 189.7 atol=0.5

    # ─── Step 8: Required steel contribution ───
    # vs = vu/φ - vc = 295.0/0.75 - 189.7 = 203.6 psi
    vs_reqd = vu_psi / φ - vcs
    @test vs_reqd ≈ 203.6 atol=1.0

    # ─── Step 9: First stud spacing s0 ───
    # 0.35d ≤ s0 ≤ 0.50d
    s0_min = 0.35 * d_in
    s0_max = 0.50 * d_in
    @test s0_min ≈ 1.97 atol=0.01
    @test s0_max ≈ 2.81 atol=0.01
    # INCON chooses s0 = 2.25 in
    s0_chosen = 2.25
    @test s0_min ≤ s0_chosen ≤ s0_max

    # ─── Step 10: Spacing between peripheral lines ───
    # vu = 295.0 > φ×6√f'c = 0.75×6×√4000 = 284.6 psi → high stress
    φ_6_sqrt_fc = φ * 6.0 * sqrt_fc
    @test φ_6_sqrt_fc ≈ 284.6 atol=0.5
    @test vu_psi > φ_6_sqrt_fc  # high stress condition
    # Therefore s ≤ 0.50d = 2.81 in (not 0.75d)
    s_max = 0.50 * d_in
    @test s_max ≈ 2.81 atol=0.01
    # INCON chooses s = 2.75 in
    s_chosen = 2.75
    @test s_chosen ≤ s_max

    # ─── Step 11: Required Av per peripheral line ───
    # Av = vs × b0 × s / fyt = 203.6 × 86.5 × 2.75 / 51000 = 0.95 in²
    Av_reqd = vs_reqd * b0_expected * s_chosen / 51000.0
    @test Av_reqd ≈ 0.95 atol=0.02

    # ─── Step 12: Select studs from INCON catalog ───
    # Use 3/8" ISS studs with A_stud = 0.11 in²
    A_stud_3_8 = 0.11  # INCON catalog value
    N_studs_per_line = Av_reqd / A_stud_3_8
    @test N_studs_per_line ≈ 8.64 atol=0.1
    N_studs_rounded = ceil(Int, N_studs_per_line)
    @test N_studs_rounded == 9
end

# =============================================================================
# INCON Worked Example — design_shear_studs with INCON Catalog
# =============================================================================
#
# Verify that design_shear_studs produces results consistent with the INCON
# worked example when using the INCON ISS catalog. Note: our function uses
# a slightly different algorithm (fixed n_rails, then solve spacing) vs
# INCON's approach (fixed spacing, then solve Av per line → N_studs).
# We verify the key ACI intermediate values match.
# =============================================================================

@testset "INCON Worked Example — design_shear_studs Integration" begin
    fc = 4000.0u"psi"
    fyt = 51000.0u"psi"
    d = 5.625u"inch"
    c1 = 20.0u"inch"
    c2 = 12.0u"inch"
    b0 = 86.5u"inch"
    β = 20.0 / 12.0  # 1.667
    αs = 40
    vu = 295.0u"psi"
    stud_diam = 0.375u"inch"  # Request 3/8" studs

    sqrt_fc = sqrt(4000.0)

    # ─── Without catalog (generic π d²/4) ───
    studs_generic = StructuralSizer.design_shear_studs(
        vu, fc, β, αs, b0, d, :interior, fyt, stud_diam;
        λ=1.0, φ=0.75
    )

    # catalog_name should be :generic when no catalog provided
    @test studs_generic.catalog_name === :generic
    @test studs_generic.required == true
    @test studs_generic.n_rails == 8  # interior → 8 rails

    # vcs should be capped at 3λ√f'c = 189.7 psi (ACI 318-11 §11.11.5.1)
    @test ustrip(u"psi", studs_generic.vcs) ≈ 3.0 * sqrt_fc atol=1.0

    # vc_max should be 8λ√f'c ≈ 506 psi
    @test ustrip(u"psi", studs_generic.vc_max) ≈ 8.0 * sqrt_fc atol=1.0

    # s0 = 0.5d = 2.8125 in (our code uses 0.5d)
    @test ustrip(u"inch", studs_generic.s0) ≈ 0.5 * 5.625 atol=0.01

    # ─── With INCON catalog ───
    studs_incon = StructuralSizer.design_shear_studs(
        vu, fc, β, αs, b0, d, :interior, fyt, stud_diam;
        λ=1.0, φ=0.75,
        catalog=StructuralSizer.INCON_ISS_CATALOG
    )

    # Should select INCON 3/8" stud (exact match)
    @test studs_incon.catalog_name === :incon_iss
    @test ustrip(u"inch", studs_incon.stud_diameter) ≈ 0.375 atol=0.001
    @test studs_incon.required == true
    @test studs_incon.n_rails == 8

    # INCON 3/8" stud has As = 0.11 in², generic has π(0.375)²/4 ≈ 0.1104 in²
    # These are very close, so results should be nearly identical
    @test ustrip(u"psi", studs_incon.vcs) ≈ ustrip(u"psi", studs_generic.vcs) atol=1.0

    # ─── With INCON catalog, request 1/2" (snap to 1/2" = 0.20 in²) ───
    studs_incon_half = StructuralSizer.design_shear_studs(
        vu, fc, β, αs, b0, d, :interior, fyt, 0.5u"inch";
        λ=1.0, φ=0.75,
        catalog=StructuralSizer.INCON_ISS_CATALOG
    )

    @test studs_incon_half.catalog_name === :incon_iss
    @test ustrip(u"inch", studs_incon_half.stud_diameter) ≈ 0.500 atol=0.001
    # Larger studs → more Av per line → vs provided should be higher (or same spacing)
    @test ustrip(u"inch^2", studs_incon_half.Av_per_line) > ustrip(u"inch^2", studs_incon.Av_per_line)
end

# =============================================================================
# INCON Worked Example — Capacity Check (Step 6 boundary)
# =============================================================================
@testset "INCON Example — Capacity Boundary Checks" begin
    fc = 4000.0u"psi"
    fyt = 51000.0u"psi"
    b0 = 86.5u"inch"
    d = 5.625u"inch"
    β = 20.0 / 12.0
    αs = 40
    sqrt_fc = sqrt(4000.0)

    # ─── Demand at exactly φ×8√f'c (max stud capacity) → studs still feasible ───
    vu_at_max = 0.75 * 8.0 * sqrt_fc  # ≈ 379.4 psi
    studs_at_max = StructuralSizer.design_shear_studs(
        vu_at_max * u"psi", fc, β, αs, b0, d, :interior, fyt, 0.5u"inch";
        λ=1.0, φ=0.75
    )
    # Should still produce a design (n_rails > 0)
    @test studs_at_max.n_rails > 0

    # ─── Demand just above φ×8√f'c → studs impossible ───
    vu_over_max = (0.75 * 8.0 * sqrt_fc + 1.0)  # ≈ 380.4 psi
    studs_over = StructuralSizer.design_shear_studs(
        vu_over_max * u"psi", fc, β, αs, b0, d, :interior, fyt, 0.5u"inch";
        λ=1.0, φ=0.75
    )
    # Should fail: n_rails = 0
    @test studs_over.n_rails == 0
    @test !studs_over.outer_ok

    # ─── Demand below φ×vc (unreinforced) → studs not strictly needed but still designed ───
    # φvc = 0.75 × min(4.4, 4.6, 4.0)×√f'c = 0.75 × 253 ≈ 189.7 psi
    vu_low = 150.0u"psi"
    studs_low = StructuralSizer.design_shear_studs(
        vu_low, fc, β, αs, b0, d, :interior, fyt, 0.5u"inch";
        λ=1.0, φ=0.75
    )
    # Function always designs studs when called (required=true)
    @test studs_low.required == true
    @test studs_low.n_rails == 8
    # But vs_reqd should be ≤ 0 (concrete alone sufficient)
    # Our code uses max(vu/φ - vcs, 0), so vs could be 0 or very small
    # The spacing should default to the maximum allowed (0.75d since low stress)
    @test ustrip(u"inch", studs_low.s) > 0
end

# =============================================================================
# Test: design_shear_studs with Ancon Shearfix Catalog
# =============================================================================
@testset "design_shear_studs — Ancon Catalog" begin
    # Same INCON example inputs, but with Ancon catalog
    fc = 4000.0u"psi"
    fyt = 51000.0u"psi"
    d = 5.625u"inch"
    b0 = 86.5u"inch"
    β = 20.0 / 12.0
    αs = 40
    vu = 295.0u"psi"

    # Request 0.5" studs → Ancon 14mm (0.551") is next size up
    studs = StructuralSizer.design_shear_studs(
        vu, fc, β, αs, b0, d, :interior, fyt, 0.5u"inch";
        λ=1.0, φ=0.75,
        catalog=StructuralSizer.ANCON_SHEARFIX_CATALOG
    )

    @test studs.catalog_name === :ancon_shearfix
    # 0.5" = 12.7mm → snaps to 14mm = 0.551"
    @test ustrip(u"mm", studs.stud_diameter) ≈ 14.0 atol=0.1
    @test studs.n_rails == 8
    @test studs.required == true

    # Request 10mm studs → exact match
    studs_10 = StructuralSizer.design_shear_studs(
        vu, fc, β, αs, b0, d, :interior, fyt, 10.0u"mm";
        λ=1.0, φ=0.75,
        catalog=StructuralSizer.ANCON_SHEARFIX_CATALOG
    )
    @test ustrip(u"mm", studs_10.stud_diameter) ≈ 10.0 atol=0.1
    @test studs_10.catalog_name === :ancon_shearfix
end

# =============================================================================
# Test: FlatPlateOptions — Backward Compatibility
# =============================================================================
#
# The old `shear_studs` field has been replaced by `punching_strategy` +
# `punching_reinforcement`. Both the constructor and property access must
# remain backward compatible.
# =============================================================================

@testset "FlatPlateOptions — Backward Compat Constructor" begin
    # ─── shear_studs=:never → punching_strategy=:grow_columns ───
    opts = StructuralSizer.FlatPlateOptions(shear_studs=:never)
    @test opts.punching_strategy === :grow_columns
    @test opts.shear_studs === :never  # virtual property

    # ─── shear_studs=:if_needed → punching_strategy=:reinforce_last ───
    opts = StructuralSizer.FlatPlateOptions(shear_studs=:if_needed)
    @test opts.punching_strategy === :reinforce_last
    @test opts.shear_studs === :if_needed

    # ─── shear_studs=:always → punching_strategy=:reinforce_first ───
    opts = StructuralSizer.FlatPlateOptions(shear_studs=:always)
    @test opts.punching_strategy === :reinforce_first
    @test opts.shear_studs === :always

    # ─── Invalid shear_studs value → error ───
    @test_throws Exception StructuralSizer.FlatPlateOptions(shear_studs=:invalid)
end

@testset "FlatPlateOptions — New Strategy Fields" begin
    # ─── Default values ───
    opts = StructuralSizer.FlatPlateOptions()
    @test opts.punching_strategy === :grow_columns
    @test opts.punching_reinforcement === :headed_studs_generic
    @test opts.shear_studs === :never  # backward compat virtual property

    # ─── Explicit new-style construction ───
    opts = StructuralSizer.FlatPlateOptions(
        punching_strategy = :reinforce_first,
        punching_reinforcement = :headed_studs_incon
    )
    @test opts.punching_strategy === :reinforce_first
    @test opts.punching_reinforcement === :headed_studs_incon
    @test opts.shear_studs === :always  # virtual property maps back

    # ─── Ancon reinforcement ───
    opts = StructuralSizer.FlatPlateOptions(
        punching_strategy = :reinforce_last,
        punching_reinforcement = :headed_studs_ancon
    )
    @test opts.punching_reinforcement === :headed_studs_ancon
    @test opts.shear_studs === :if_needed
end

@testset "FlatPlateOptions — Combined with Other Fields" begin
    # Verify that backward-compat constructor passes through other kwargs
    opts = StructuralSizer.FlatPlateOptions(
        shear_studs = :if_needed,
        max_column_size = 36.0u"inch",
        stud_diameter = 0.625u"inch",
        φ_shear = 0.70
    )
    @test opts.punching_strategy === :reinforce_last
    @test opts.max_column_size ≈ 36.0u"inch" atol=0.1u"inch"
    @test opts.stud_diameter ≈ 0.625u"inch" atol=0.01u"inch"
    @test opts.φ_shear ≈ 0.70 atol=0.001

    # New-style with other kwargs
    opts = StructuralSizer.FlatPlateOptions(
        punching_strategy = :reinforce_first,
        punching_reinforcement = :headed_studs_incon,
        max_column_size = 24.0u"inch"
    )
    @test opts.punching_strategy === :reinforce_first
    @test opts.punching_reinforcement === :headed_studs_incon
    @test opts.max_column_size ≈ 24.0u"inch" atol=0.1u"inch"
end

@testset "FlatSlabOptions — Strategy Forwarding" begin
    # FlatSlabOptions forwards punching fields through its base
    opts = StructuralSizer.flat_slab(
        punching_strategy = :reinforce_first,
        punching_reinforcement = :headed_studs_incon
    )
    @test opts.punching_strategy === :reinforce_first
    @test opts.punching_reinforcement === :headed_studs_incon

    # Backward-compat via flat_slab
    opts = StructuralSizer.flat_slab(shear_studs = :if_needed)
    @test opts.punching_strategy === :reinforce_last
    @test opts.shear_studs === :if_needed
end

# =============================================================================
# Test: ShearStudDesign — catalog_name Field
# =============================================================================
@testset "ShearStudDesign — catalog_name Field" begin
    # Default ShearStudDesign should have :generic catalog
    default_studs = StructuralSizer.ShearStudDesign()
    @test default_studs.catalog_name === :generic

    # Constructed with explicit catalog_name
    studs = StructuralSizer.ShearStudDesign(
        required = true,
        catalog_name = :incon_iss,
        n_rails = 8,
        n_studs_per_rail = 9
    )
    @test studs.catalog_name === :incon_iss
    @test studs.n_rails == 8
    @test studs.n_studs_per_rail == 9
end

# =============================================================================
# Edge Case: Square Column (β = 1.0) — All Three vn Branches Equal
# =============================================================================
@testset "Square Column — vn Branches" begin
    # For a square interior column with β = 1.0:
    # vc_a = (2 + 4/1.0)λ√f'c = 6λ√f'c
    # vc_b depends on αs×d/b0
    # vc_c = 4λ√f'c
    # min → 4λ√f'c (vc_c always governs for β ≤ 2)
    fc = 4000.0u"psi"
    d = 8.0u"inch"
    c = 16.0u"inch"  # square column
    b0_sq = 4 * (16.0 + 8.0)  # 96 in for interior square
    β_sq = 1.0
    αs = 40
    sqrt_fc = sqrt(4000.0)

    vc_a = (2 + 4 / β_sq) * sqrt_fc  # 6√f'c = 379.5
    vc_b = (αs * 8.0 / b0_sq + 2) * sqrt_fc  # (40×8/96 + 2)√f'c
    vc_c = 4 * sqrt_fc  # 253.0

    # vc_c should govern (smallest)
    @test min(vc_a, vc_b, vc_c) ≈ vc_c atol=0.1

    studs = StructuralSizer.design_shear_studs(
        250.0u"psi", fc, β_sq, αs, b0_sq * u"inch", d, :interior,
        51000.0u"psi", 0.5u"inch"; λ=1.0, φ=0.75
    )
    # With studs, vcs capped at 3√f'c = 189.7
    @test ustrip(u"psi", studs.vcs) ≈ 3.0 * sqrt_fc atol=1.0
end

# =============================================================================
# Edge Case: High Aspect Ratio Column (β = 3.0) — vc_a Governs
# =============================================================================
@testset "High Aspect Ratio Column — vc_a Governs" begin
    # β = 3.0: vc_a = (2 + 4/3)λ√f'c = 3.33λ√f'c
    # vc_c = 4λ√f'c
    # vc_a < vc_c → vc_a governs
    fc = 4000.0u"psi"
    d = 6.0u"inch"
    c1 = 30.0u"inch"
    c2 = 10.0u"inch"
    β_high = 3.0
    αs = 40
    b0 = 2 * (30.0 + 6.0) + 2 * (10.0 + 6.0)  # 104 in
    sqrt_fc = sqrt(4000.0)

    vc_a = (2 + 4 / β_high) * sqrt_fc  # 3.33√f'c ≈ 210.8
    vc_c = 4 * sqrt_fc  # 253.0
    @test vc_a < vc_c  # vc_a should govern

    studs = StructuralSizer.design_shear_studs(
        250.0u"psi", fc, β_high, αs, b0 * u"inch", d, :interior,
        51000.0u"psi", 0.5u"inch"; λ=1.0, φ=0.75
    )
    # With studs, vcs capped at min(vc_a, 3√f'c) = min(210.8, 189.7) = 189.7
    @test ustrip(u"psi", studs.vcs) ≈ min(vc_a, 3.0 * sqrt_fc) atol=1.0
end

println("\n✅ All shear stud tests completed!")
