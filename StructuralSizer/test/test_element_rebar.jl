# =============================================================================
# Tests for Per-Element Rebar Sizing (area_design.jl)
# =============================================================================
#
# Tests the Whitney stress block per-element function, minimum steel
# enforcement, and the field builder.
# =============================================================================

using Test
using Unitful
using StructuralSizer

# Access internal functions via the module
const SS = StructuralSizer

# =============================================================================
# Unit tests for _element_As (bare SI)
# =============================================================================

@testset "Per-Element Rebar Sizing" begin

    @testset "_element_As — Whitney stress block (unit width)" begin
        # Standard NWC: f'c = 4000 psi ≈ 27.58 MPa, fy = 60 ksi ≈ 413.7 MPa
        fc_Pa = 27.58e6
        fy_Pa = 413.7e6

        # d = 7 in ≈ 0.1778 m (typical 9" slab with 0.75" cover + #5 bar)
        d_m = 0.1778

        @testset "Zero moment → zero steel" begin
            As, ok = SS._element_As(0.0, d_m, fc_Pa, fy_Pa)
            @test As == 0.0
            @test ok == true
        end

        @testset "Negative moment → zero steel (caller should negate hogging)" begin
            As, ok = SS._element_As(-1000.0, d_m, fc_Pa, fy_Pa)
            @test As == 0.0
            @test ok == true
        end

        @testset "Moderate sagging moment — hand check" begin
            # Mu = 20 kN·m/m = 20_000 N·m/m
            # Rn = 20000 / (0.9 × 1.0 × 0.1778²) = 703,000 Pa ≈ 102 psi
            # β1 = 0.85 (f'c ≤ 4000 psi)
            # term = 2 × 703000 / (0.85 × 27.58e6) = 0.0600
            # ρ = (0.85 × 27.58e6 / 413.7e6) × (1 - √(1 - 0.0600))
            #   = 0.0567 × 0.0309 = 0.001752
            # As = 0.001752 × 1.0 × 0.1778 = 3.11e-4 m²/m ≈ 311 mm²/m
            Mu = 20_000.0
            As, ok = SS._element_As(Mu, d_m, fc_Pa, fy_Pa)
            @test ok == true
            @test As > 0.0
            # Verify against hand calculation (within 5%)
            @test isapprox(As, 3.11e-4, rtol=0.05)
        end

        @testset "Very large moment — section inadequate" begin
            # Mu = 500 kN·m/m on a 7" slab → term > 1.0 → inadequate
            As, ok = SS._element_As(500_000.0, d_m, fc_Pa, fy_Pa)
            @test ok == false
        end

        @testset "β1 varies with f'c" begin
            # f'c = 8000 psi = 55.16 MPa → β1 = 0.65
            fc_8k = 55.16e6
            Mu = 20_000.0
            As_8k, ok_8k = SS._element_As(Mu, d_m, fc_8k, fy_Pa)
            @test ok_8k == true
            # Higher f'c → lower β1 → slightly different ρ (but still reasonable)
            @test As_8k > 0.0

            # f'c = 6000 psi = 41.37 MPa → β1 between 0.65 and 0.85
            fc_6k = 41.37e6
            As_6k, ok_6k = SS._element_As(Mu, d_m, fc_6k, fy_Pa)
            @test ok_6k == true
            @test As_6k > 0.0
        end
    end

    @testset "_design_area_reinforcement — minimum steel enforcement" begin
        # Build a vector of AreaDesignMoments with zero moments
        # All elements should get As_min
        fc = 4000.0u"psi"
        fy = 60_000.0u"psi"
        h = 9.0u"inch"
        d = 7.0u"inch"

        zero_moms = [
            SS.AreaDesignMoment(k, 0.5 * k, 0.5, 0.01,
                                0.0, 0.0, 0.0, 0.0)
            for k in 1:5
        ]

        results = SS._design_area_reinforcement(zero_moms, h, d, fc, fy)

        @test length(results) == 5
        for r in results
            @test r.section_adequate == true
            # All steel areas should equal As_min (moments are zero)
            @test r.As_x_bot ≈ r.As_min
            @test r.As_x_top ≈ r.As_min
            @test r.As_y_bot ≈ r.As_min
            @test r.As_y_top ≈ r.As_min
        end

        # Verify As_min value: ρ_min = 0.0018 (Grade 60), h = 9" = 0.2286 m
        # As_min = 0.0018 × 1.0 × 0.2286 = 4.115e-4 m²/m ≈ 411 mm²/m
        @test isapprox(results[1].As_min, 0.0018 * ustrip(u"m", h), rtol=0.01)
    end

    @testset "_design_area_reinforcement — sagging moment governs over minimum" begin
        fc = 4000.0u"psi"
        fy = 60_000.0u"psi"
        h = 9.0u"inch"
        d = 7.0u"inch"

        # One element with a large sagging moment in x'
        moms = [SS.AreaDesignMoment(1, 1.0, 1.0, 0.01,
                                     40_000.0,  # Mx_bot = 40 kN·m/m (large)
                                     0.0,       # Mx_top
                                     0.0,       # My_bot
                                     0.0)]      # My_top

        results = SS._design_area_reinforcement(moms, h, d, fc, fy)
        r = results[1]
        @test r.section_adequate == true
        # As_x_bot should exceed As_min
        @test r.As_x_bot > r.As_min
        # Other directions at minimum
        @test r.As_x_top ≈ r.As_min
        @test r.As_y_bot ≈ r.As_min
        @test r.As_y_top ≈ r.As_min
    end

    @testset "_design_area_reinforcement — hogging moment (top steel)" begin
        fc = 4000.0u"psi"
        fy = 60_000.0u"psi"
        h = 9.0u"inch"
        d = 7.0u"inch"

        # Element with large hogging moment in x' (Mx_top is negative).
        # 60 kN·m/m is large enough to exceed ACI minimum steel for a 9" slab.
        # Field order: elem_idx, cx, cy, area, Mx_bot, My_bot, Mx_top, My_top
        moms = [SS.AreaDesignMoment(1, 1.0, 1.0, 0.01,
                                     0.0,        # Mx_bot
                                     0.0,        # My_bot
                                     -60_000.0,  # Mx_top (hogging)
                                     0.0)]       # My_top

        results = SS._design_area_reinforcement(moms, h, d, fc, fy)
        r = results[1]
        @test r.section_adequate == true
        # As_x_top should exceed As_min (hogging needs top steel)
        @test r.As_x_top > r.As_min
        # As_x_bot should be at minimum (no sagging moment)
        @test r.As_x_bot ≈ r.As_min
    end

    @testset "_design_area_reinforcement — section inadequate" begin
        fc = 4000.0u"psi"
        fy = 60_000.0u"psi"
        h = 6.0u"inch"   # thin slab
        d = 4.0u"inch"

        # Extremely large moment on thin slab
        moms = [SS.AreaDesignMoment(1, 1.0, 1.0, 0.01,
                                     500_000.0,  # 500 kN·m/m — way too much
                                     0.0, 0.0, 0.0)]

        results = SS._design_area_reinforcement(moms, h, d, fc, fy)
        @test results[1].section_adequate == false
    end

    @testset "_build_element_rebar_field — field metadata" begin
        fc = 4000.0u"psi"
        fy = 60_000.0u"psi"
        h = 9.0u"inch"
        d = 7.0u"inch"

        moms = [
            SS.AreaDesignMoment(k, Float64(k), 0.0, 0.01,
                                10_000.0, 0.0, 5_000.0, 0.0)
            for k in 1:3
        ]

        field = SS._build_element_rebar_field(moms, h, d, fc, fy, :wood_armer)

        @test field.moment_transform == :wood_armer
        @test field.section_adequate == true
        @test length(field.elements) == 3
        @test field.h ≈ ustrip(u"m", h)
        @test field.d ≈ ustrip(u"m", d)
        @test field.fc ≈ ustrip(u"Pa", fc)
        @test field.fy ≈ ustrip(u"Pa", fy)
    end

    @testset "Grade 40 steel → higher ρ_min (0.0020)" begin
        fc = 4000.0u"psi"
        fy = 40_000.0u"psi"  # Grade 40
        h = 9.0u"inch"
        d = 7.0u"inch"

        zero_moms = [SS.AreaDesignMoment(1, 0.5, 0.5, 0.01, 0.0, 0.0, 0.0, 0.0)]
        results = SS._design_area_reinforcement(zero_moms, h, d, fc, fy)

        # ρ_min = 0.0020 for fy < 60 ksi
        expected_As_min = 0.0020 * ustrip(u"m", h)
        @test isapprox(results[1].As_min, expected_As_min, rtol=0.01)
    end

    @testset "Grade 80 steel → reduced ρ_min" begin
        fc = 4000.0u"psi"
        fy = 80_000.0u"psi"  # Grade 80
        h = 9.0u"inch"
        d = 7.0u"inch"

        zero_moms = [SS.AreaDesignMoment(1, 0.5, 0.5, 0.01, 0.0, 0.0, 0.0, 0.0)]
        results = SS._design_area_reinforcement(zero_moms, h, d, fc, fy)

        # ρ_min = max(0.0014, 0.0018 × 60000 / 80000) = max(0.0014, 0.00135) = 0.0014
        expected_As_min = 0.0014 * ustrip(u"m", h)
        @test isapprox(results[1].As_min, expected_As_min, rtol=0.01)
    end

end
