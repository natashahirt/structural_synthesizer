# =============================================================================
# Integration Tests for Doubly Reinforced RC Beam Design
# Validated against StructurePoint Example (ACI 318-14)
#
# Source: DE-Doubly-Reinforced-Concrete-Beam-Design-ACI-318-14-spBeam-v1000.pdf
#
# Cantilever beam with concentrated moment at free end. Section requires
# compression reinforcement to achieve the required capacity while remaining
# tension-controlled.
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
    b       = 14.0u"inch",
    h       = 29.0u"inch",
    d       = 26.0u"inch",        # depth to tension steel centroid
    d_prime = 3.0u"inch",         # depth to compression steel centroid

    # Materials
    fc      = 5000.0u"psi",
    fy      = 60000.0u"psi",
    Es      = 29000.0ksi,

    # Applied moments (unfactored, at free end)
    M_DL    = 234.0kip * u"ft",
    M_LL    = 414.0kip * u"ft",
)

# Factored moment
const Mu = 1.2 * SP.M_DL + 1.6 * SP.M_LL  # = 943.20 kip-ft

# =============================================================================
# Reference values from StructurePoint hand calculations
# =============================================================================
const REF = (
    # Factored moment
    Mu       = 943.20,  # kip-ft

    # Material properties
    β1       = 0.80,
    εy       = 0.00207,  # fy/Es

    # Singly reinforced limit (tension-controlled, εt = 0.005)
    c_max    = 9.75,     # in  (d × 0.003/0.008)
    a_max    = 7.80,     # in  (β1 × c_max)
    Cc       = 464.10,   # kips
    As_max   = 7.74,     # in² (max singly reinforced As)
    Mn_singly = 854.72,  # kip-ft

    # Required nominal moment
    Mn_required = 1048.00,  # kip-ft (Mu/φ)

    # Doubly reinforced design
    ΔMn          = 193.28,  # kip-ft
    Cs           = 100.84,  # kips
    εs_prime     = 0.00208, # compression steel strain (≈ 0.002077)
    As_compression = 1.81,  # in²  (A's)
    Ts           = 564.94,  # kips (total tension force)
    As_tension   = 9.42,    # in²  (total tension steel)

    # spBeam verification (Table 1)
    φMn_spBeam   = 943.29,  # kip-ft
)

# =============================================================================
@testset "Doubly Reinforced Beam — StructurePoint Validation" begin

    # -----------------------------------------------------------------
    # §1  Material Properties
    # -----------------------------------------------------------------
    @testset "Material properties" begin
        @test beta1(SP.fc) ≈ REF.β1 atol=0.001
        εy = ustrip(u"psi", SP.fy) / ustrip(u"psi", SP.Es)
        @test εy ≈ REF.εy rtol=0.01
    end

    # -----------------------------------------------------------------
    # §2  Factored Moment
    # -----------------------------------------------------------------
    @testset "Factored moment" begin
        Mu_kft = ustrip(kip * u"ft", Mu)
        @test Mu_kft ≈ REF.Mu rtol=0.001
    end

    # -----------------------------------------------------------------
    # §3  Max Singly Reinforced Capacity
    # -----------------------------------------------------------------
    @testset "Max singly reinforced capacity" begin
        sr = max_singly_reinforced(SP.b, SP.d, SP.fc, SP.fy)

        @test ustrip(u"inch", sr.c_max) ≈ REF.c_max rtol=0.01
        @test ustrip(u"inch", sr.a_max) ≈ REF.a_max rtol=0.01
        @test ustrip(kip, sr.Cc) ≈ REF.Cc rtol=0.01
        @test ustrip(u"inch^2", sr.As_max) ≈ REF.As_max rtol=0.01
        @test sr.β1 ≈ REF.β1 atol=0.001

        Mn_kft = ustrip(kip * u"ft", sr.Mn_max)
        @test Mn_kft ≈ REF.Mn_singly rtol=0.01
    end

    # -----------------------------------------------------------------
    # §4  Compression Steel Strain Check
    # -----------------------------------------------------------------
    @testset "Compression steel strain" begin
        sr = max_singly_reinforced(SP.b, SP.d, SP.fc, SP.fy)
        comp = compression_steel_stress(sr.c_max, SP.d_prime, SP.fc, SP.fy, SP.Es)

        # ε's ≈ 0.00208 ≥ εy = 0.00207 → yields
        @test comp.εs_prime ≈ REF.εs_prime rtol=0.02
        @test comp.yields == true
        # Compression steel stress = fy (since it yields)
        @test ustrip(u"psi", comp.fs_prime) ≈ ustrip(u"psi", SP.fy) rtol=0.01
    end

    # -----------------------------------------------------------------
    # §5  Full Doubly Reinforced Design (Direct Call)
    # -----------------------------------------------------------------
    @testset "Doubly reinforced design (direct)" begin
        result = design_beam_flexure_doubly(Mu, SP.b, SP.d, SP.d_prime, SP.fc, SP.fy, SP.Es)

        @test result.doubly_reinforced == true
        @test result.tension_controlled == true
        @test result.φ ≈ 0.90 atol=0.001

        @testset "Excess moment" begin
            ΔMn_kft = ustrip(kip * u"ft", result.ΔMn)
            @test ΔMn_kft ≈ REF.ΔMn rtol=0.01
        end

        @testset "Compression couple force" begin
            Cs_kip = ustrip(kip, result.Cs)
            @test Cs_kip ≈ REF.Cs rtol=0.01
        end

        @testset "Compression steel area" begin
            As_comp = ustrip(u"inch^2", result.As_compression)
            @test As_comp ≈ REF.As_compression rtol=0.02
        end

        @testset "Total tension steel area" begin
            As_tens = ustrip(u"inch^2", result.As_tension)
            @test As_tens ≈ REF.As_tension rtol=0.01
        end

        @testset "Compression steel yields" begin
            @test result.comp_steel_yields == true
            @test result.εs_prime ≈ REF.εs_prime rtol=0.02
        end
    end

    # -----------------------------------------------------------------
    # §6  Auto-Dispatch (design_beam_flexure detects doubly reinforced)
    # -----------------------------------------------------------------
    @testset "Auto-dispatch to doubly reinforced" begin
        result = design_beam_flexure(Mu, SP.b, SP.d, SP.fc, SP.fy, SP.Es;
                    d_prime=SP.d_prime)

        @test result.doubly_reinforced == true
        @test ustrip(u"inch^2", result.As_tension) ≈ REF.As_tension rtol=0.01
        @test ustrip(u"inch^2", result.As_compression) ≈ REF.As_compression rtol=0.02
    end

    # -----------------------------------------------------------------
    # §7  Singly Reinforced Still Works (sanity check)
    # -----------------------------------------------------------------
    @testset "Singly reinforced auto-dispatch" begin
        Mu_small = 200.0kip * u"ft"
        result = design_beam_flexure(Mu_small, SP.b, SP.d, SP.fc, SP.fy, SP.Es)

        @test result.doubly_reinforced == false
        @test haskey(result, :As_design)
        @test result.tension_controlled == true
    end

    # -----------------------------------------------------------------
    # §8  Capacity Verification (φMn ≥ Mu)
    # -----------------------------------------------------------------
    @testset "Capacity verification" begin
        result = design_beam_flexure_doubly(Mu, SP.b, SP.d, SP.d_prime, SP.fc, SP.fy, SP.Es)

        # Verify total nominal moment = Mn_singly + ΔMn
        Mn_total_kft = ustrip(kip * u"ft", result.Mn_singly) +
                       ustrip(kip * u"ft", result.ΔMn)
        φMn = 0.90 * Mn_total_kft

        # Should be ≥ Mu
        @test φMn ≥ ustrip(kip * u"ft", Mu) - 0.5  # small tolerance

        # Should match spBeam within 1%
        @test φMn ≈ REF.Mn_required * 0.90 rtol=0.01
    end
end

println("\n✓ Doubly reinforced beam tests passed (StructurePoint validation)")
