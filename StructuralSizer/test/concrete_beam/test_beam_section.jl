# =============================================================================
# Test RCBeamSection — Construction and Properties
# =============================================================================

using Test
using Unitful
using StructuralSizer
using Asap: kip, ksi

# =============================================================================
@testset "RCBeamSection" begin
# =============================================================================

    # -----------------------------------------------------------------
    # §1  Singly Reinforced Constructor
    # -----------------------------------------------------------------
    @testset "Singly reinforced (3 #9 bars)" begin
        sec = RCBeamSection(b=12u"inch", h=20u"inch",
                            bar_size=9, n_bars=3, stirrup_size=3)

        @test ustrip(u"inch", sec.b) ≈ 12.0
        @test ustrip(u"inch", sec.h) ≈ 20.0

        # Effective depth: 20 − 1.5 (cover) − 0.375 (#3 stirrup) − 1.128/2 (#9)
        @test ustrip(u"inch", sec.d) ≈ 17.561 rtol=0.01

        # As = 3 × 1.00 in² = 3.00 in²
        @test ustrip(u"inch^2", sec.As) ≈ 3.00 rtol=0.001

        # No compression steel
        @test sec.n_bars_prime == 0
        @test ustrip(u"inch^2", sec.As_prime) ≈ 0.0

        # Auto-name
        @test sec.name == "12x20-3#9"
    end

    # -----------------------------------------------------------------
    # §2  Doubly Reinforced Constructor
    # -----------------------------------------------------------------
    @testset "Doubly reinforced (4 #9 + 2 #6)" begin
        sec = RCBeamSection(b=14u"inch", h=26u"inch",
                            bar_size=9, n_bars=4,
                            bar_size_prime=6, n_bars_prime=2,
                            stirrup_size=4)

        @test ustrip(u"inch^2", sec.As) ≈ 4.00 rtol=0.001
        @test ustrip(u"inch^2", sec.As_prime) ≈ 2 * 0.44 rtol=0.01
        @test sec.n_bars_prime == 2
        @test sec.name == "14x26-4#9+2#6"

        @test is_doubly_reinforced(sec) == true

        # d_prime = cover + stirrup + db'/2 = 1.5 + 0.5 + 0.75/2 = 2.375
        @test ustrip(u"inch", sec.d_prime) ≈ 2.375 rtol=0.02
    end

    # -----------------------------------------------------------------
    # §3  Interface
    # -----------------------------------------------------------------
    @testset "Section interface" begin
        sec = RCBeamSection(b=12u"inch", h=20u"inch",
                            bar_size=8, n_bars=3)

        Ag = section_area(sec)
        @test ustrip(u"inch^2", Ag) ≈ 240.0

        @test section_depth(sec) == sec.h
        @test section_width(sec) == sec.b

        ρ = rho(sec)
        @test 0.005 < ρ < 0.05  # sanity
    end

    # -----------------------------------------------------------------
    # §4  Gross Section Properties
    # -----------------------------------------------------------------
    @testset "Gross moment of inertia" begin
        sec = RCBeamSection(b=12u"inch", h=20u"inch",
                            bar_size=9, n_bars=3)
        Ig = gross_moment_of_inertia(sec)
        @test ustrip(u"inch^4", Ig) ≈ 8000.0 rtol=0.001

        Sb = section_modulus_bottom(sec)
        @test ustrip(u"inch^3", Sb) ≈ 800.0 rtol=0.001
    end

    # -----------------------------------------------------------------
    # §5  Custom Cover / Stirrup
    # -----------------------------------------------------------------
    @testset "Custom cover and stirrup" begin
        sec = RCBeamSection(b=16u"inch", h=24u"inch",
                            bar_size=10, n_bars=4,
                            cover=2.0u"inch", stirrup_size=4)

        # d = 24 − 2.0 (cover) − 0.5 (#4 stirrup) − 1.27/2 (#10)
        expected_d = 24.0 - 2.0 - 0.5 - 1.27 / 2
        @test ustrip(u"inch", sec.d) ≈ expected_d rtol=0.01
    end

end

println("\n✓ RCBeamSection tests passed")
