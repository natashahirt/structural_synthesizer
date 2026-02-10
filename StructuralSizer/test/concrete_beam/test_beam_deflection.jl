# =============================================================================
# Test RC Beam Deflection — StructurePoint Simply Supported Beam
# =============================================================================
#
# Source: DE-Simply-Supported-Reinforced-Concrete-Beam-Analysis-and-Design-
#         ACI-318-14-spBeam-v1000 (StructurePoint), pg. 11–14
#
# All reference values below are from the StructurePoint document.
# DO NOT adjust test expectations to match code output — fix the code instead.
#
# Problem:
#   Simply supported beam, L = 25 ft, b = 12 in, h = 20 in
#   f'c = 4.35 ksi, fy = 60 ksi, wc = 150 pcf
#   3-#9 bars (As = 3.00 in²), #3 stirrups, cover = 1.5 in
#   Service DL = 0.82 k/ft, LL = 1.00 k/ft
#
# StructurePoint reference results (pg. 11–14):
#   Ec  = 33 × 150^1.5 × √4350 = 3998.5 ksi  (ACI 19.2.2.1.a, wc=150)
#   fr  = 7.5 × √4350 = 494.66 psi
#   Ig  = 12 × 20³ / 12 = 8000 in⁴
#   n   = 29000 / 3998.5 = 7.25
#   kd  = 6.37 in (neutral axis, cracked)
#   Icr = 3759 in⁴
#   Mcr = fr × Ig / yt = 494.66 × 8000 / (10 × 12000) = 32.98 kip-ft
#
#   Ma_D   = 0.82 × 25² / 8 = 64.06 kip-ft
#   Ma_D+L = 1.82 × 25² / 8 = 142.19 kip-ft
#
#   Ie_D   = Icr + (Ig - Icr)(Mcr/Ma_D)³   = 4337 in⁴
#   Ie_D+L = Icr + (Ig - Icr)(Mcr/Ma_D+L)³ = 3812 in⁴
#
#   Δ_D    = 5 × 820 × 300⁴ / (384 × 3998500 × 4337) = 0.416 in
#   Δ_D+L  = 5 × 1820 × 300⁴ / (384 × 3998500 × 3812) = 1.050 in
#   Δ_LL   = 1.050 − 0.416 = 0.634 in
#   Limit  = L/360 = 300/360 = 0.833 in → Δ_LL = 0.634 < 0.833 ✓
# =============================================================================

using Test
using Unitful
using StructuralSizer
using Asap: kip, ksi, psf, ksf, pcf

# =============================================================================
# StructurePoint Reference Data (pg. 11–14)
# =============================================================================
const REF = (
    # Material
    Ec_ksi    = 3998.5,    # ksi — 33 × 150^1.5 × √4350
    fr_psi    = 494.66,    # psi — 7.5√4350
    n         = 7.25,      # Es/Ec = 29000/3998.5

    # Section
    Ig        = 8000.0,    # in⁴
    Icr       = 3759.0,    # in⁴
    Mcr_kipft = 32.98,     # kip-ft

    # Service moments
    Ma_D_kipft  = 64.06,   # kip-ft — wD × L² / 8
    Ma_DL_kipft = 142.19,  # kip-ft — (wD+wL) × L² / 8

    # Effective Ie
    Ie_D      = 4337.0,    # in⁴
    Ie_DL     = 3812.0,    # in⁴

    # Immediate deflections
    Δ_D       = 0.416,     # in
    Δ_DL      = 1.050,     # in
    Δ_LL      = 0.634,     # in (= Δ_DL − Δ_D)

    # Limit
    Δ_limit   = 0.833,     # in (L/360 = 300/360)
)

# =============================================================================
# Inputs (with units)
# =============================================================================
const DEF = (
    b      = 12.0u"inch",
    h      = 20.0u"inch",
    d      = 17.56u"inch",
    As     = 3.00u"inch^2",     # 3 #9 bars
    L      = 25.0u"ft",
    fc     = 4350.0u"psi",
    fy     = 60000.0u"psi",
    Es     = 29000.0ksi,
    wc_pcf = 150,                # pcf — concrete unit weight
    w_dead = 0.82kip / u"ft",
    w_live = 1.00kip / u"ft",
)

# =============================================================================
@testset "RC Beam Deflection — StructurePoint Validation" begin
# =============================================================================

    result = design_beam_deflection(
        DEF.b, DEF.h, DEF.d, DEF.As,
        DEF.fc, DEF.fy, DEF.Es,
        DEF.L, DEF.w_dead, DEF.w_live;
        support = :simply_supported,
        wc_pcf  = DEF.wc_pcf,
    )

    # -----------------------------------------------------------------
    # §1  Material Properties
    # -----------------------------------------------------------------
    @testset "Material properties (SP pg. 11)" begin
        Ec_ksi_val = ustrip(ksi, result.Ec)
        # SP: Ec = 33 × 150^1.5 × √4350 = 3998.5 ksi
        @test Ec_ksi_val ≈ REF.Ec_ksi rtol=0.01

        fr_psi_val = ustrip(u"psi", result.fr)
        # SP: fr = 7.5 × √4350 = 494.66 psi
        @test fr_psi_val ≈ REF.fr_psi rtol=0.01

        # Modular ratio n = Es / Ec
        n = ustrip(u"psi", DEF.Es) / ustrip(u"psi", result.Ec)
        @test n ≈ REF.n rtol=0.01
    end

    # -----------------------------------------------------------------
    # §2  Gross Section Properties
    # -----------------------------------------------------------------
    @testset "Gross section Ig (SP pg. 11)" begin
        Ig_in4 = ustrip(u"inch^4", result.Ig)
        # SP: Ig = 12 × 20³ / 12 = 8000 in⁴
        @test Ig_in4 ≈ REF.Ig rtol=0.001
    end

    # -----------------------------------------------------------------
    # §3  Cracking Moment
    # -----------------------------------------------------------------
    @testset "Cracking moment Mcr (SP pg. 12)" begin
        Mcr_kft = ustrip(kip * u"ft", result.Mcr)
        # SP: Mcr = 494.66 × 8000 / (10 × 12000) = 32.98 kip-ft
        @test Mcr_kft ≈ REF.Mcr_kipft rtol=0.02
    end

    # -----------------------------------------------------------------
    # §4  Cracked Moment of Inertia
    # -----------------------------------------------------------------
    @testset "Cracked Icr (SP pg. 12)" begin
        Icr_in4 = ustrip(u"inch^4", result.Icr)
        # SP: n=7.25, kd=6.37 → Icr = 3759 in⁴
        @test Icr_in4 ≈ REF.Icr rtol=0.02
    end

    # -----------------------------------------------------------------
    # §5  Service Moments
    # -----------------------------------------------------------------
    @testset "Service moments (SP pg. 13)" begin
        Ma_D_kft  = ustrip(kip * u"ft", result.Ma_dead)
        Ma_DL_kft = ustrip(kip * u"ft", result.Ma_total)

        # SP: Ma_D = 0.82 × 25² / 8 = 64.06 kip-ft
        @test Ma_D_kft ≈ REF.Ma_D_kipft rtol=0.01

        # SP: Ma_D+L = 1.82 × 25² / 8 = 142.19 kip-ft
        @test Ma_DL_kft ≈ REF.Ma_DL_kipft rtol=0.01

        # Both must exceed Mcr (section is cracked)
        @test Ma_D_kft > REF.Mcr_kipft
        @test Ma_DL_kft > REF.Mcr_kipft
    end

    # -----------------------------------------------------------------
    # §6  Effective Moment of Inertia
    # -----------------------------------------------------------------
    @testset "Effective Ie (SP pg. 13)" begin
        Ie_D_in4  = ustrip(u"inch^4", result.Ie_D)
        Ie_DL_in4 = ustrip(u"inch^4", result.Ie_DL)

        # SP: Ie_D = 4337 in⁴
        @test Ie_D_in4 ≈ REF.Ie_D rtol=0.02

        # SP: Ie_DL = 3812 in⁴
        @test Ie_DL_in4 ≈ REF.Ie_DL rtol=0.02

        # Ie_D > Ie_DL (lower load → closer to Ig)
        @test Ie_D_in4 > Ie_DL_in4

        # Both bounded by [Icr, Ig]
        @test REF.Icr ≤ Ie_D_in4 ≤ REF.Ig
        @test REF.Icr ≤ Ie_DL_in4 ≤ REF.Ig
    end

    # -----------------------------------------------------------------
    # §7  Immediate Deflections
    # -----------------------------------------------------------------
    @testset "Immediate deflections (SP pg. 14)" begin
        Δ_D_in  = ustrip(u"inch", result.Δ_D)
        Δ_DL_in = ustrip(u"inch", result.Δ_DL)
        Δ_LL_in = ustrip(u"inch", result.Δ_LL)

        # SP: Δ_D = 0.416 in
        @test Δ_D_in ≈ REF.Δ_D rtol=0.05

        # SP: Δ_DL = 1.050 in
        @test Δ_DL_in ≈ REF.Δ_DL rtol=0.05

        # SP: Δ_LL = Δ_DL − Δ_D = 0.634 in
        @test Δ_LL_in ≈ REF.Δ_LL rtol=0.05

        # Subtraction identity
        @test Δ_LL_in ≈ Δ_DL_in - Δ_D_in rtol=0.001

        # Physical sanity
        @test Δ_D_in > 0
        @test Δ_LL_in > 0
        @test Δ_LL_in < Δ_DL_in
    end

    # -----------------------------------------------------------------
    # §8  Long-Term Deflection
    # -----------------------------------------------------------------
    @testset "Long-term deflection" begin
        # λΔ = ξ/(1+50ρ') = 2.0/(1+0) = 2.0 (no compression steel)
        @test result.λΔ ≈ 2.0 rtol=0.001

        # Δ_total = λΔ × Δ_D + Δ_LL
        Δ_total_in = ustrip(u"inch", result.Δ_total)
        Δ_D_in     = ustrip(u"inch", result.Δ_D)
        Δ_LL_in    = ustrip(u"inch", result.Δ_LL)
        @test Δ_total_in ≈ 2.0 * Δ_D_in + Δ_LL_in rtol=0.001
    end

    # -----------------------------------------------------------------
    # §9  Deflection Limits (ACI Table 24.2.2)
    # -----------------------------------------------------------------
    @testset "Deflection limits (SP pg. 14)" begin
        L_in = ustrip(u"inch", DEF.L)

        # L/360 = 300/360 = 0.833 in
        @test ustrip(u"inch", result.checks[:immediate_ll].limit) ≈ REF.Δ_limit rtol=0.001

        # L/240 = 300/240 = 1.25 in
        @test ustrip(u"inch", result.checks[:total].limit) ≈ L_in / 240 rtol=0.001

        # SP: Δ_LL = 0.634 < L/360 = 0.833 → immediate LL check PASSES
        @test result.checks[:immediate_ll].ok == true
    end

    # -----------------------------------------------------------------
    # §10  Compression Steel Reduces Long-Term
    # -----------------------------------------------------------------
    @testset "Compression steel effect" begin
        result_comp = design_beam_deflection(
            DEF.b, DEF.h, DEF.d, DEF.As,
            DEF.fc, DEF.fy, DEF.Es,
            DEF.L, DEF.w_dead, DEF.w_live;
            support = :simply_supported,
            wc_pcf  = DEF.wc_pcf,
            As_prime = 1.00u"inch^2"
        )

        # ρ' = 1.00/(12 × 17.56) = 0.00475
        # λΔ = 2.0/(1 + 50 × 0.00475) = 2.0/1.237 = 1.616
        @test result_comp.λΔ < result.λΔ
        @test result_comp.λΔ ≈ 1.616 rtol=0.02
        @test ustrip(u"inch", result_comp.Δ_total) < ustrip(u"inch", result.Δ_total)
    end

    # -----------------------------------------------------------------
    # §11  Simplified Ec Formula (wc_pcf = nothing)
    # -----------------------------------------------------------------
    @testset "Simplified Ec formula (57000√fc)" begin
        result_simple = design_beam_deflection(
            DEF.b, DEF.h, DEF.d, DEF.As,
            DEF.fc, DEF.fy, DEF.Es,
            DEF.L, DEF.w_dead, DEF.w_live;
            support = :simply_supported,
            wc_pcf  = nothing,  # use 57000√fc
        )

        # Simplified Ec = 57000√4350 ≈ 3759 ksi (lower than SP's 3998)
        Ec_simple_ksi = ustrip(ksi, result_simple.Ec)
        @test Ec_simple_ksi ≈ 3759.0 rtol=0.02
        @test Ec_simple_ksi < ustrip(ksi, result.Ec)

        # Lower Ec → larger deflections
        @test ustrip(u"inch", result_simple.Δ_DL) > ustrip(u"inch", result.Δ_DL)
    end
end

println("\n✓ Beam deflection tests passed (StructurePoint pg. 11–14 validated)")
