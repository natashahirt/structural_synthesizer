# =============================================================================
# Test RC Beam Flexural Design — StructurePoint Validation
# =============================================================================
#
# Source: DE-Simply-Supported-Reinforced-Concrete-Beam-Analysis-and-Design-
#         ACI-318-14-spBeam-v1000 (StructurePoint)
#
# Problem:
#   Simply supported beam, L = 25 ft, b = 12 in, h = 20 in
#   f'c = 4.35 ksi, fy = 60 ksi, wc = 150 pcf
#   DL = 0.82 k/ft, LL = 1.00 k/ft (self-weight excluded per reference)
#   #9 longitudinal bars, #3 stirrups, clear cover = 1.5 in
#
# Reference results:
#   d = 17.56 in, Mu = 201.88 kip-ft
#   As,req = 2.872 in², As,min = 0.702 in² → 3-#9 (As = 3.00 in²)
#   a = 3.88 in, c = 4.67 in, εt = 0.0083 (tension-controlled)
# =============================================================================

using Test
using Unitful
using Unitful: @u_str
using StructuralSizer

# Asap units
using Asap: kip, ksi

# =============================================================================
# Reference values (from StructurePoint, all unitless for comparison)
# =============================================================================
const SP = (
    L       = 25.0,     # ft
    L_in    = 300.0,    # in
    b       = 12.0,     # in
    h       = 20.0,     # in
    cover   = 1.50,     # in
    d_stir  = 0.375,    # in (#3 stirrup)
    d_bar   = 1.128,    # in (#9 bar)
    d       = 17.56,    # in (effective depth)
    fc_psi  = 4350.0,   # psi
    fy_psi  = 60000.0,  # psi
    Mu_kipft = 201.88,  # kip-ft
    As_req  = 2.872,    # in²
    As_min_a = 0.695,   # in² (Eq. 9.6.1.2a)
    As_min_b = 0.702,   # in² (Eq. 9.6.1.2b)
    As_min  = 0.702,    # in² (governs)
    a       = 3.88,     # in (stress block depth)
    c       = 4.67,     # in (neutral axis depth)
    εt      = 0.0083,   # tensile strain
    β1      = 0.83,     # stress block factor
    h_min   = 18.75,    # in (Table 9.3.1.1 simply supported = L/16)
)

# =============================================================================
# Inputs with units
# =============================================================================
const b_u  = SP.b * u"inch"
const h_u  = SP.h * u"inch"
const d_u  = SP.d * u"inch"
const fc_u = SP.fc_psi * u"psi"
const fy_u = SP.fy_psi * u"psi"
const Es_u = 29000.0ksi              # steel modulus
const Mu_u = SP.Mu_kipft * kip * u"ft"
const L_u  = SP.L * u"ft"

# =============================================================================
@testset "RC Beam Flexure — StructurePoint Validation" begin
# =============================================================================

    @testset "Minimum Depth (ACI Table 9.3.1.1)" begin
        h_min = beam_min_depth(L_u, :simply_supported)
        @test ustrip(u"inch", h_min) ≈ SP.h_min rtol=0.01

        # Selected depth satisfies minimum
        @test SP.h ≥ SP.h_min
    end

    @testset "Effective Depth" begin
        d_calc = beam_effective_depth(h_u;
            cover    = SP.cover * u"inch",
            d_stirrup = SP.d_stir * u"inch",
            d_bar    = SP.d_bar * u"inch",
        )
        @test ustrip(u"inch", d_calc) ≈ SP.d rtol=0.01
    end

    @testset "Minimum Reinforcement (ACI 9.6.1.2)" begin
        As_min = beam_min_reinforcement(b_u, d_u, fc_u, fy_u)
        As_min_in = ustrip(u"inch^2", As_min)

        # Should match governing value (200bwd/fy)
        @test As_min_in ≈ SP.As_min rtol=0.02
    end

    @testset "Required Reinforcement (Whitney Block)" begin
        As_req = required_reinforcement(Mu_u, b_u, d_u, fc_u, fy_u)
        @test ustrip(u"inch^2", As_req) ≈ SP.As_req rtol=0.02
    end

    @testset "Stress Block Geometry" begin
        As_u = SP.As_req * u"inch^2"

        # Stress block depth: a = As·fy / (0.85·f'c·b)
        a = stress_block_depth(As_u, fc_u, fy_u, b_u)
        @test ustrip(u"inch", a) ≈ SP.a rtol=0.02

        # Neutral axis: c = a / β1
        c = neutral_axis_depth(a, fc_u)
        @test ustrip(u"inch", c) ≈ SP.c rtol=0.02
    end

    @testset "Strain Check" begin
        As_u = SP.As_req * u"inch^2"
        a = stress_block_depth(As_u, fc_u, fy_u, b_u)
        c = neutral_axis_depth(a, fc_u)

        εt = tensile_strain(d_u, c)
        @test εt ≈ SP.εt rtol=0.05

        # Must be tension-controlled
        @test is_tension_controlled(εt)

        # φ = 0.9 for tension-controlled
        @test flexure_phi(εt) == 0.9
    end

    @testset "β₁ Factor" begin
        β1_val = beta1(fc_u)
        @test β1_val ≈ SP.β1 rtol=0.02
    end

    @testset "Full design_beam_flexure()" begin
        result = design_beam_flexure(Mu_u, b_u, d_u, fc_u, fy_u, Es_u)

        @test ustrip(u"inch^2", result.As_required) ≈ SP.As_req rtol=0.02
        @test ustrip(u"inch^2", result.As_min)      ≈ SP.As_min rtol=0.02
        @test ustrip(u"inch",   result.a)            ≈ SP.a     rtol=0.03
        @test ustrip(u"inch",   result.c)            ≈ SP.c     rtol=0.03
        @test result.εt ≈ SP.εt rtol=0.05
        @test result.tension_controlled == true
        @test result.φ == 0.9

        # Provided reinforcement must exceed required
        @test ustrip(u"inch^2", result.bars.As_provided) ≥ SP.As_req
    end

    @testset "Edge Cases" begin
        # Minimum reinforcement governs for lightly loaded beams
        small_Mu = 20.0 * kip * u"ft"   # very small moment
        result = design_beam_flexure(small_Mu, b_u, d_u, fc_u, fy_u, Es_u)
        @test ustrip(u"inch^2", result.As_design) ≈ ustrip(u"inch^2", result.As_min) rtol=0.001

        # Cantilever minimum depth
        h_cant = beam_min_depth(L_u, :cantilever)
        @test ustrip(u"inch", h_cant) ≈ SP.L_in / 8 rtol=0.01
    end

    @testset "φ Transition Zone" begin
        # εt < 0.002 → compression-controlled
        @test flexure_phi(0.001) == 0.65

        # εt = 0.0035 → transition
        φ_trans = flexure_phi(0.0035)
        @test 0.65 < φ_trans < 0.90

        # εt ≥ 0.005 → tension-controlled
        @test flexure_phi(0.005) == 0.90
        @test flexure_phi(0.010) == 0.90
    end

end  # testset

println("\n✓ All RC beam flexure tests passed (StructurePoint validated)")
