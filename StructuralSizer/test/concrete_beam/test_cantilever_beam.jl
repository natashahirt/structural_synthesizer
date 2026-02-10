# =============================================================================
# Integration Tests for Cantilever RC Beam Design
# Validated against StructurePoint Cantilever Beam Example (ACI 318-14)
#
# Source: DE-Reinforced-Concrete-Cantilever-Beam-Analysis-and-Design-
#         ACI-318-14-spBeam-v1000.pdf
#
# Singly reinforced cantilever, point load at free end.
# This verifies the existing code works for all support conditions.
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
    L      = 100.0u"inch",       # span (= 8.33 ft)
    b      = 16.0u"inch",        # beam width
    h      = 24.0u"inch",        # total depth
    cover  = 1.5u"inch",         # clear cover (Table 20.6.1.3.1)

    # Materials
    fc     = 4000.0u"psi",       # f'c
    fy     = 60000.0u"psi",      # fy
    Es     = 29000.0ksi,         # steel modulus

    # Point loads at free end
    P_DL   = 12.0kip,
    P_LL   = 12.0kip,
)

# Derived
const Pu  = 1.2 * SP.P_DL + 1.6 * SP.P_LL      # = 33.6 kip
const Vu  = Pu                                     # constant shear along cantilever
const L_ft = uconvert(u"ft", SP.L)
const Mu  = Pu * L_ft                              # = 280 kip-ft at fixed end

# Cantilever beam: d with #4 stirrups, #9 bars
const d_ref = 21.44u"inch"  # 24 - 1.50 - 0.50 - 1.128/2

# =============================================================================
@testset "Cantilever RC Beam — StructurePoint Validation" begin

    # -----------------------------------------------------------------
    # §1  Minimum Depth
    # -----------------------------------------------------------------
    @testset "Minimum depth (Table 9.3.1.1)" begin
        h_min = beam_min_depth(SP.L, :cantilever)
        # Reference: L/8 = 100/8 = 12.5 in
        @test ustrip(u"inch", h_min) ≈ 12.5 rtol=0.01
        @test SP.h ≥ h_min
    end

    # -----------------------------------------------------------------
    # §2  Effective Depth
    # -----------------------------------------------------------------
    @testset "Effective depth" begin
        d = beam_effective_depth(SP.h; cover=SP.cover,
                d_stirrup=0.50u"inch", d_bar=1.128u"inch")
        # d = 24 - 1.50 - 0.50 - 1.128/2 = 21.436 in
        @test ustrip(u"inch", d) ≈ 21.436 atol=0.01
    end

    # -----------------------------------------------------------------
    # §3  Factored Loads
    # -----------------------------------------------------------------
    @testset "Factored loads" begin
        @test ustrip(kip, Pu) ≈ 33.6 rtol=0.01
        @test ustrip(kip * u"ft", Mu) ≈ 280.0 rtol=0.01
    end

    # -----------------------------------------------------------------
    # §4  Flexural Design
    # -----------------------------------------------------------------
    @testset "Flexural design" begin
        result = design_beam_flexure(Mu, SP.b, d_ref, SP.fc, SP.fy, SP.Es;
                    cover=SP.cover, d_stirrup=0.50u"inch")

        @testset "Required reinforcement" begin
            As_in = ustrip(u"inch^2", result.As_required)
            # Reference: As = 3.16 in²
            @test As_in ≈ 3.16 rtol=0.02
        end

        @testset "Minimum reinforcement (ACI 9.6.1.2)" begin
            As_min_in = ustrip(u"inch^2", result.As_min)
            # Reference: As_min = max(1.085, 1.143) = 1.143 in²
            @test As_min_in ≈ 1.143 rtol=0.02
        end

        @testset "Stress block" begin
            # β1 = 0.85 for 4000 psi
            @test beta1(SP.fc) ≈ 0.85 atol=0.001

            a_in = ustrip(u"inch", result.a)
            c_in = ustrip(u"inch", result.c)
            # Reference: a = 3.48 in, c = 4.10 in
            @test a_in ≈ 3.48 rtol=0.03
            @test c_in ≈ 4.10 rtol=0.03
        end

        @testset "Strain and φ" begin
            # Reference: εt = 0.0127
            @test result.εt ≈ 0.0127 rtol=0.05
            @test result.tension_controlled == true
            @test result.φ ≈ 0.90 atol=0.001
        end

        @testset "Bar selection" begin
            bars = result.bars
            @test ustrip(u"inch^2", bars.As_provided) ≥ ustrip(u"inch^2", result.As_design)
            @test ustrip(u"inch", bars.s_clear) ≥ 1.0  # ACI 25.2.1
        end
    end

    # -----------------------------------------------------------------
    # §5  Shear Design
    # -----------------------------------------------------------------
    @testset "Shear design" begin
        # For cantilevers, Vu is constant along span (no reduction at d)
        Vu_design = Vu

        @testset "Concrete shear capacity" begin
            Vc = Vc_beam(SP.b, d_ref, SP.fc)
            Vc_kip = ustrip(kip, Vc)
            # Nominal: 2√4000 × 16 × 21.44 / 1000 ≈ 43.39 kips
            @test Vc_kip ≈ 43.39 rtol=0.02
            # φVc ≈ 32.54 kips
            @test 0.75 * Vc_kip ≈ 32.54 rtol=0.02
        end

        @testset "Required Vs (small — minimum governs)" begin
            Vc = Vc_beam(SP.b, d_ref, SP.fc)
            Vs = Vs_required(Vu_design, Vc)
            # Vs = 33.6/0.75 - 43.39 ≈ 1.41 kips (very small)
            @test ustrip(kip, Vs) ≈ 1.41 rtol=0.10
        end

        @testset "Minimum Av/s governs" begin
            Avs_min = min_shear_reinforcement(SP.b, SP.fc, SP.fy)
            # Reference: max(0.0127, 0.0133) = 0.0133 in²/in
            @test ustrip(u"inch^2/inch", Avs_min) ≈ 0.0133 rtol=0.02
        end

        @testset "Section adequacy" begin
            Vs_max = Vs_max_beam(SP.b, d_ref, SP.fc)
            # Reference: 173.53 kips
            @test ustrip(kip, Vs_max) ≈ 173.53 rtol=0.02
        end

        @testset "Maximum stirrup spacing" begin
            Vc = Vc_beam(SP.b, d_ref, SP.fc)
            Vs = Vs_required(Vu_design, Vc)
            s_max = max_stirrup_spacing(d_ref, Vs, SP.b, SP.fc)
            # Reference: min(d/2, 24) = min(10.72, 24) = 10.72 in
            @test ustrip(u"inch", s_max) ≈ 10.72 rtol=0.01
        end

        @testset "Full shear pipeline" begin
            result = design_beam_shear(Vu_design, SP.b, d_ref,
                        SP.fc, SP.fy; stirrup_bar=4)

            @test result.section_adequate == true

            # Spacing governed by max_spacing, not demand (Vs is tiny)
            @test ustrip(u"inch", result.s_design) ≤ ustrip(u"inch", result.s_max)

            # φVn ≥ Vu
            @test ustrip(kip, result.φVn) ≥ ustrip(kip, Vu_design)
        end
    end
end

println("\n✓ Cantilever RC beam tests passed (StructurePoint validation)")
