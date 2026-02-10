# =============================================================================
# Test RC Beam Shear Design — StructurePoint Validation
# =============================================================================
#
# Source: DE-Simply-Supported-Reinforced-Concrete-Beam-Analysis-and-Design-
#         ACI-318-14-spBeam-v1000 (StructurePoint)
#
# Problem: Same simply supported beam as flexure test.
#
# Reference results (shear design, §5):
#   Vu = 32.30 kips at support
#   Vu@d = 28.52 kips (design shear at d from support)
#   Vc = 27.80 kips, φVc = 20.85 kips
#   Vs,req = 10.23 kips
#   Vs,max = 111.19 kips (section adequate)
#   Av/s_min = 0.0100 in²/in
#   s_max = 8.78 in (d/2 governs)
#   Provided: #3 @ 8.3" → Av = 0.22 in²
#   φVn = 41.79 kips > 28.52 kips ✓
# =============================================================================

using Test
using Unitful
using Unitful: @u_str
using StructuralSizer

# Asap units
using Asap: kip, ksi

# =============================================================================
# Reference values (from StructurePoint, unitless for comparison)
# =============================================================================
const SP_SHEAR = (
    b       = 12.0,     # in
    d       = 17.56,    # in
    L_in    = 300.0,    # in
    fc_psi  = 4350.0,   # psi
    fy_psi  = 60000.0,  # psi (= fyt for stirrups)
    Vu_kip  = 32.30,    # kips at support
    Vu_at_d = 28.52,    # kips at d from support face
    Vc_kip  = 27.80,    # kips (nominal)
    φVc_kip = 20.85,    # kips (design)
    Vs_req  = 10.23,    # kips
    Vs_max  = 111.19,   # kips
    Avs_min = 0.0100,   # in²/in (min Av/s)
    s_max   = 8.78,     # in (d/2 governs)
    Av      = 0.22,     # in² (2 legs #3)
    s_prov  = 8.30,     # in (provided spacing)
    φVn_kip = 41.79,    # kips (final capacity)
)

# Inputs with units
const bw_u  = SP_SHEAR.b * u"inch"
const d_u2  = SP_SHEAR.d * u"inch"
const fc_u2 = SP_SHEAR.fc_psi * u"psi"
const fy_u2 = SP_SHEAR.fy_psi * u"psi"
const Vu_at_d_u = SP_SHEAR.Vu_at_d * kip

# =============================================================================
@testset "RC Beam Shear — StructurePoint Validation" begin
# =============================================================================

    @testset "Concrete Shear Capacity (ACI 22.5.5.1)" begin
        Vc = Vc_beam(bw_u, d_u2, fc_u2)
        Vc_kip = ustrip(u"lbf", Vc) / 1000
        @test Vc_kip ≈ SP_SHEAR.Vc_kip rtol=0.02

        # Design capacity
        φVc = 0.75 * Vc
        @test ustrip(u"lbf", φVc) / 1000 ≈ SP_SHEAR.φVc_kip rtol=0.02
    end

    @testset "Maximum Vs (ACI 22.5.1.2)" begin
        Vs_max = Vs_max_beam(bw_u, d_u2, fc_u2)
        @test ustrip(u"lbf", Vs_max) / 1000 ≈ SP_SHEAR.Vs_max rtol=0.02
    end

    @testset "Required Shear Reinforcement" begin
        Vc = Vc_beam(bw_u, d_u2, fc_u2)
        Vs = Vs_required(Vu_at_d_u, Vc)
        @test ustrip(u"lbf", Vs) / 1000 ≈ SP_SHEAR.Vs_req rtol=0.03

        # Section is adequate
        Vs_max = Vs_max_beam(bw_u, d_u2, fc_u2)
        @test ustrip(u"lbf", Vs) ≤ ustrip(u"lbf", Vs_max)
    end

    @testset "Minimum Shear Reinforcement (ACI 9.6.3.3)" begin
        Avs_min = min_shear_reinforcement(bw_u, fc_u2, fy_u2)
        @test ustrip(u"inch^2/inch", Avs_min) ≈ SP_SHEAR.Avs_min rtol=0.02
    end

    @testset "Maximum Stirrup Spacing (ACI 9.7.6.2.2)" begin
        Vc = Vc_beam(bw_u, d_u2, fc_u2)
        Vs = Vs_required(Vu_at_d_u, Vc)
        s_max = max_stirrup_spacing(d_u2, Vs, bw_u, fc_u2)
        @test ustrip(u"inch", s_max) ≈ SP_SHEAR.s_max rtol=0.02
    end

    @testset "Stirrup Design" begin
        Vc = Vc_beam(bw_u, d_u2, fc_u2)
        Vs = Vs_required(Vu_at_d_u, Vc)
        stir = design_stirrups(Vs, d_u2, fy_u2; bar_size=3)

        # Two-leg #3 stirrup area
        @test ustrip(u"inch^2", stir.Av) ≈ SP_SHEAR.Av rtol=0.01
    end

    @testset "Full design_beam_shear()" begin
        result = design_beam_shear(Vu_at_d_u, bw_u, d_u2, fc_u2, fy_u2; stirrup_bar=3)

        # Vc
        @test ustrip(u"lbf", result.Vc) / 1000 ≈ SP_SHEAR.Vc_kip rtol=0.02

        # φVc
        @test ustrip(u"lbf", result.φVc) / 1000 ≈ SP_SHEAR.φVc_kip rtol=0.02

        # Vs,req
        @test ustrip(u"lbf", result.Vs_req) / 1000 ≈ SP_SHEAR.Vs_req rtol=0.03

        # Section adequate
        @test result.section_adequate == true

        # s_max
        @test ustrip(u"inch", result.s_max) ≈ SP_SHEAR.s_max rtol=0.02

        # Design spacing ≤ max spacing
        @test ustrip(u"inch", result.s_design) ≤ SP_SHEAR.s_max + 0.01

        # Final capacity exceeds demand
        @test ustrip(u"lbf", result.φVn) / 1000 > SP_SHEAR.Vu_at_d
    end

    @testset "Edge Cases" begin
        # When Vu < φVc/2, minimum stirrups may still be required
        small_Vu = 5.0 * kip
        result = design_beam_shear(small_Vu, bw_u, d_u2, fc_u2, fy_u2)
        @test result.section_adequate == true

        # φVn should still exceed demand
        @test ustrip(u"lbf", result.φVn) / 1000 ≥ 5.0
    end

end  # testset

println("\n✓ All RC beam shear tests passed (StructurePoint validated)")
