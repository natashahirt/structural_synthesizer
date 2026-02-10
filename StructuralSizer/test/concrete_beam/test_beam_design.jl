# =============================================================================
# Integration Tests for RC Beam Design Functions
# Validated against StructurePoint Simply Supported Beam Example (ACI 318-14)
#
# Source: DE-Simply-Supported-Reinforced-Concrete-Beam-Analysis-and-Design-
#         ACI-318-14-spBeam-v1000.pdf
#
# This test calls actual StructuralSizer functions and compares outputs
# to the StructurePoint reference values.
# =============================================================================

using Test
using StructuralSizer
using Unitful
using Asap: kip, ksi, psf, ksf, pcf

# =============================================================================
# StructurePoint Reference Inputs
# =============================================================================
const SP = (
    # Geometry
    L      = 25.0u"ft",          # span (c/c)
    b      = 12.0u"inch",        # beam width
    h      = 20.0u"inch",        # total depth
    cover  = 1.5u"inch",         # clear cover (Table 20.6.1.3.1)

    # Materials
    fc     = 4350.0u"psi",       # f'c (= 4.35 ksi)
    fy     = 60000.0u"psi",      # fy  (= 60 ksi)
    Es     = 29000.0ksi,         # steel modulus

    # Loads (exclude self-weight per reference)
    wD     = 0.82kip / u"ft",    # dead load
    wL     = 1.00kip / u"ft",    # live load
)

# Derived from reference
const wu = 1.2 * SP.wD + 1.6 * SP.wL          # = 2.584 kip/ft
const Vu = wu * SP.L / 2                        # = 32.30 kips
const Mu = wu * SP.L^2 / 8                      # = 201.88 kip-ft

# =============================================================================
# TESTS
# =============================================================================

@testset "RC Beam Design — StructurePoint Validation" begin

    # -----------------------------------------------------------------
    # §1  Preliminary Sizing (ACI Table 9.3.1.1)
    # -----------------------------------------------------------------
    @testset "Minimum depth (Table 9.3.1.1)" begin
        h_min = beam_min_depth(SP.L, :simply_supported)
        # Reference: 300 in / 16 = 18.75 in
        @test ustrip(u"inch", h_min) ≈ 18.75 rtol=0.01
        @test SP.h ≥ h_min  # selected h satisfies minimum

        # Other support conditions (spot-check formulas)
        @test ustrip(u"inch", beam_min_depth(SP.L, :cantilever)) ≈ 300 / 8 rtol=0.01
        @test ustrip(u"inch", beam_min_depth(SP.L, :both_ends_continuous)) ≈ 300 / 21 rtol=0.01
    end

    # -----------------------------------------------------------------
    # §2  Effective Depth
    # -----------------------------------------------------------------
    @testset "Effective depth" begin
        d = beam_effective_depth(SP.h; cover=SP.cover,
                d_stirrup=0.375u"inch", d_bar=1.128u"inch")
        # Reference: d = 20 - 1.50 - 0.375 - 1.128/2 = 17.561 in
        @test ustrip(u"inch", d) ≈ 17.561 atol=0.01
    end

    # Use reference d for remaining tests (avoids compounding rounding)
    d_ref = 17.56u"inch"

    # -----------------------------------------------------------------
    # §3  Factored Loads / Analysis
    # -----------------------------------------------------------------
    @testset "Factored loads" begin
        @test ustrip(kip / u"ft", wu) ≈ 2.584 rtol=0.01
        @test ustrip(kip, Vu)         ≈ 32.30 rtol=0.01
        @test ustrip(kip * u"ft", Mu) ≈ 201.88 rtol=0.01
    end

    # -----------------------------------------------------------------
    # §4  Flexural Design
    # -----------------------------------------------------------------
    @testset "Flexural design" begin
        result = design_beam_flexure(Mu, SP.b, d_ref, SP.fc, SP.fy, SP.Es)

        @testset "Required reinforcement (Whitney block)" begin
            As_in = ustrip(u"inch^2", result.As_required)
            # Reference: As = 2.872 in²
            @test As_in ≈ 2.872 rtol=0.02
        end

        @testset "Minimum reinforcement (ACI 9.6.1.2)" begin
            As_min_in = ustrip(u"inch^2", result.As_min)
            # Reference: max(0.695, 0.702) = 0.702 in²
            @test As_min_in ≈ 0.702 rtol=0.02

            # Verify individual components
            fc_psi = ustrip(u"psi", SP.fc)
            fy_psi = ustrip(u"psi", SP.fy)
            bw = ustrip(u"inch", SP.b)
            d  = ustrip(u"inch", d_ref)
            As_a = 3 * sqrt(fc_psi) * bw * d / fy_psi
            As_b = 200 * bw * d / fy_psi
            @test As_a ≈ 0.695 rtol=0.02  # Eq. 9.6.1.2(a)
            @test As_b ≈ 0.702 rtol=0.01  # Eq. 9.6.1.2(b) — governs
        end

        @testset "Stress block depth" begin
            a_in = ustrip(u"inch", result.a)
            # Reference: a = 3.88 in
            @test a_in ≈ 3.88 rtol=0.03
        end

        @testset "Neutral axis depth" begin
            c_in = ustrip(u"inch", result.c)
            # Reference: c = 4.67 in
            @test c_in ≈ 4.67 rtol=0.03
        end

        @testset "Tensile strain (ACI 21.2.2)" begin
            # Reference: εt = 0.0083
            @test result.εt ≈ 0.0083 rtol=0.05
            @test result.tension_controlled == true
            @test result.φ ≈ 0.90 atol=0.001
        end

        @testset "Bar selection" begin
            bars = result.bars
            # Must provide ≥ As_design
            As_prov = ustrip(u"inch^2", bars.As_provided)
            As_des  = ustrip(u"inch^2", result.As_design)
            @test As_prov ≥ As_des

            # Clear spacing ≥ minimum (ACI 25.2.1)
            @test ustrip(u"inch", bars.s_clear) ≥ 1.0
        end
    end

    # Also test individual helper functions
    @testset "Helper functions" begin
        @testset "stress_block_depth" begin
            As = 2.872u"inch^2"
            a = stress_block_depth(As, SP.fc, SP.fy, SP.b)
            @test ustrip(u"inch", a) ≈ 3.88 rtol=0.02
        end

        @testset "neutral_axis_depth" begin
            a = 3.88u"inch"
            c = neutral_axis_depth(a, SP.fc)
            @test ustrip(u"inch", c) ≈ 4.67 rtol=0.02
        end

        @testset "tensile_strain" begin
            εt = tensile_strain(d_ref, 4.67u"inch")
            @test εt ≈ 0.00828 rtol=0.03
            @test is_tension_controlled(εt)
        end

        @testset "flexure_phi" begin
            @test flexure_phi(0.006) ≈ 0.90
            @test flexure_phi(0.001) ≈ 0.65
            @test flexure_phi(0.0035) ≈ 0.65 + 0.25 * (0.0035 - 0.002) / 0.003 rtol=0.001
        end

        @testset "beam_max_bar_spacing" begin
            s_max = beam_max_bar_spacing(SP.fy)
            # Reference: s_max = min(10.31, 12) = 10.31 in
            @test ustrip(u"inch", s_max) ≈ 10.31 rtol=0.02
        end
    end

    # -----------------------------------------------------------------
    # §5  Shear Design
    # -----------------------------------------------------------------

    # Shear at d from support face
    Vu_at_d = Vu * (SP.L / 2 - d_ref) / (SP.L / 2)

    @testset "Shear design" begin
        @testset "Vu at d from support" begin
            @test ustrip(kip, Vu_at_d) ≈ 28.52 rtol=0.02
        end

        @testset "Concrete shear capacity (ACI 22.5.5.1)" begin
            Vc = Vc_beam(SP.b, d_ref, SP.fc)
            Vc_kip = ustrip(kip, Vc)
            @test Vc_kip ≈ 27.80 rtol=0.02
            @test 0.75 * Vc_kip ≈ 20.85 rtol=0.02  # φVc
        end

        @testset "Required Vs" begin
            Vc = Vc_beam(SP.b, d_ref, SP.fc)
            Vs = Vs_required(Vu_at_d, Vc)
            @test ustrip(kip, Vs) ≈ 10.23 rtol=0.05
        end

        @testset "Section adequacy — Vs,max (ACI 22.5.1.2)" begin
            Vs_max = Vs_max_beam(SP.b, d_ref, SP.fc)
            # Reference: 111.19 kips
            @test ustrip(kip, Vs_max) ≈ 111.19 rtol=0.02
            Vc = Vc_beam(SP.b, d_ref, SP.fc)
            Vs = Vs_required(Vu_at_d, Vc)
            @test ustrip(kip, Vs) < ustrip(kip, Vs_max)  # section adequate
        end

        @testset "Minimum Av/s (ACI 9.6.3.3)" begin
            fyt = SP.fy
            Avs_min = min_shear_reinforcement(SP.b, SP.fc, fyt)
            @test ustrip(u"inch^2/inch", Avs_min) ≈ 0.0100 rtol=0.02
        end

        @testset "Maximum stirrup spacing (ACI 9.7.6.2.2)" begin
            Vc = Vc_beam(SP.b, d_ref, SP.fc)
            Vs = Vs_required(Vu_at_d, Vc)
            s_max = max_stirrup_spacing(d_ref, Vs, SP.b, SP.fc)
            # Reference: min(d/2, 24) = min(8.78, 24) = 8.78 in
            @test ustrip(u"inch", s_max) ≈ 8.78 rtol=0.01
        end

        @testset "Full shear design pipeline" begin
            result = design_beam_shear(Vu_at_d, SP.b, d_ref, SP.fc, SP.fy)

            @test ustrip(kip, result.Vc)     ≈ 27.80 rtol=0.02
            @test ustrip(kip, result.φVc)    ≈ 20.85 rtol=0.02
            @test ustrip(kip, result.Vs_req) ≈ 10.23 rtol=0.05
            @test result.section_adequate == true

            # Design spacing ≤ max spacing
            @test ustrip(u"inch", result.s_design) ≤ ustrip(u"inch", result.s_max)

            # φVn ≥ Vu (capacity exceeds demand)
            @test ustrip(kip, result.φVn) ≥ ustrip(kip, Vu_at_d)
        end
    end
end

println("\n✓ All RC beam design tests passed (StructurePoint reference validation)")
