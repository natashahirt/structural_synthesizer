# ==============================================================================
# Tests for RCColumnSection
# ==============================================================================
# Phase 1.1: Section struct construction and basic properties
# Uses verified StructurePoint 16x16 example data

using Test
using Unitful
using StructuralSizer

# Load test data (only if not already loaded by runtests.jl)
if !@isdefined(TIED_16X16_SPCOLUMN)
    include("test_data/tied_column_16x16.jl")
end

@testset "RCColumnSection" begin

    # ==========================================================================
    # Test 1: Basic Construction
    # ==========================================================================
    @testset "Basic Construction" begin
        # Create the 16x16 column from test data
        data = TIED_16X16_SPCOLUMN
        
        # Cover calculation to get d' = 2.5" (edge to bar center)
        # edge_to_center = cover + tie_diam + bar_diam/2 = 2.5"
        # cover = 2.5 - 0.5 - 0.564 ≈ 1.436"
        cover = 1.436u"inch"
        
        sec = RCColumnSection(
            b = data.geometry.b * u"inch",
            h = data.geometry.h * u"inch",
            bar_size = data.reinforcement.bar_size,
            n_bars = data.reinforcement.n_bars,
            cover = cover,
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # Check basic properties
        @test sec.b ≈ 16.0u"inch"
        @test sec.h ≈ 16.0u"inch"
        @test sec.tie_type == :tied
        @test length(sec.bars) == 8
        
        # Check name auto-generation
        @test sec.name == "16x16-8#9"
    end

    # ==========================================================================
    # Test 2: Gross Area Calculation
    # ==========================================================================
    @testset "Gross Area" begin
        data = TIED_16X16_SPCOLUMN
        cover = 1.436u"inch"
        
        sec = RCColumnSection(
            b = data.geometry.b * u"inch",
            h = data.geometry.h * u"inch",
            bar_size = data.reinforcement.bar_size,
            n_bars = data.reinforcement.n_bars,
            cover = cover,
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # Ag = 16 × 16 = 256 in²
        @test StructuralSizer.section_area(sec) ≈ 256.0u"inch^2"
    end

    # ==========================================================================
    # Test 3: Reinforcement Ratio
    # ==========================================================================
    @testset "Reinforcement Ratio" begin
        data = TIED_16X16_SPCOLUMN
        cover = 1.436u"inch"
        
        sec = RCColumnSection(
            b = data.geometry.b * u"inch",
            h = data.geometry.h * u"inch",
            bar_size = data.reinforcement.bar_size,
            n_bars = data.reinforcement.n_bars,
            cover = cover,
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # ρg = As/Ag = 8.0/256 = 0.03125
        expected_rho = 8.0 / 256.0
        @test StructuralSizer.rho(sec) ≈ expected_rho rtol=0.001
        
        # Should be within ACI limits (0.01 to 0.08)
        @test 0.01 ≤ StructuralSizer.rho(sec) ≤ 0.08
    end

    # ==========================================================================
    # Test 4: Bar Positions (Two-Layer Arrangement)
    # ==========================================================================
    @testset "Bar Positions - Two Layer" begin
        data = TIED_16X16_SPCOLUMN
        cover = 1.436u"inch"
        
        sec = RCColumnSection(
            b = data.geometry.b * u"inch",
            h = data.geometry.h * u"inch",
            bar_size = data.reinforcement.bar_size,
            n_bars = data.reinforcement.n_bars,
            cover = cover,
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # Bars should be in two layers only
        y_coords = sort([ustrip(u"inch", bar.y) for bar in sec.bars])
        
        # 4 bars at bottom (y ≈ 2.5")
        bottom_bars = count(y -> isapprox(y, 2.5, atol=0.1), y_coords)
        @test bottom_bars == 4
        
        # 4 bars at top (y ≈ 13.5")
        top_bars = count(y -> isapprox(y, 13.5, atol=0.1), y_coords)
        @test top_bars == 4
        
        # No bars in between
        middle_bars = count(y -> 4.0 < y < 12.0, y_coords)
        @test middle_bars == 0
    end
    
    # ==========================================================================
    # Test 5: Bar Positions (Perimeter Arrangement)
    # ==========================================================================
    @testset "Bar Positions - Perimeter" begin
        sec = RCColumnSection(
            b = 18u"inch",
            h = 18u"inch",
            bar_size = 9,
            n_bars = 8,
            cover = 1.5u"inch",
            tie_type = :tied,
            arrangement = :perimeter
        )
        
        # Perimeter arrangement should have bars around all faces
        y_coords = sort([ustrip(u"inch", bar.y) for bar in sec.bars])
        x_coords = sort([ustrip(u"inch", bar.x) for bar in sec.bars])
        
        # Should have bars at multiple y levels (corners + sides)
        unique_y = unique(round.(y_coords, digits=1))
        @test length(unique_y) >= 2  # At least top and bottom
        
        # Should have bars at multiple x levels
        unique_x = unique(round.(x_coords, digits=1))
        @test length(unique_x) >= 2  # At least left and right
    end

    # ==========================================================================
    # Test 6: Effective Depth
    # ==========================================================================
    @testset "Effective Depth" begin
        data = TIED_16X16_SPCOLUMN
        cover = 1.436u"inch"
        
        sec = RCColumnSection(
            b = data.geometry.b * u"inch",
            h = data.geometry.h * u"inch",
            bar_size = data.reinforcement.bar_size,
            n_bars = data.reinforcement.n_bars,
            cover = cover,
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # Effective depth d = h - y_bottom_bars = 16 - 2.5 = 13.5"
        d = StructuralSizer.effective_depth(sec)
        @test ustrip(u"inch", d) ≈ 13.5 rtol=0.02
        
        # Compression steel depth d' = h - y_top_bars = 16 - 13.5 = 2.5"
        d_prime = StructuralSizer.compression_steel_depth(sec)
        @test ustrip(u"inch", d_prime) ≈ 2.5 rtol=0.02
    end

    # ==========================================================================
    # Test 7: Moment of Inertia
    # ==========================================================================
    @testset "Moment of Inertia" begin
        sec = RCColumnSection(
            b = 16u"inch",
            h = 16u"inch",
            bar_size = 9,
            n_bars = 8,
            cover = 1.5u"inch",
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # Ig = bh³/12 = 16 × 16³ / 12 = 5461.3 in⁴
        Ig = StructuralSizer.moment_of_inertia(sec)
        @test ustrip(u"inch^4", Ig) ≈ 5461.3 rtol=0.01
    end

    # ==========================================================================
    # Test 8: Radius of Gyration
    # ==========================================================================
    @testset "Radius of Gyration" begin
        sec = RCColumnSection(
            b = 16u"inch",
            h = 20u"inch",  # Rectangular
            bar_size = 9,
            n_bars = 8,
            cover = 1.5u"inch",
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # r = 0.3h for rectangular sections (ACI 6.2.5.1)
        r_x = StructuralSizer.radius_of_gyration(sec; axis=:x)
        @test ustrip(u"inch", r_x) ≈ 0.3 * 20 rtol=0.01
        
        r_y = StructuralSizer.radius_of_gyration(sec; axis=:y)
        @test ustrip(u"inch", r_y) ≈ 0.3 * 16 rtol=0.01
    end

    # ==========================================================================
    # Test 9: Explicit Bar Positions Constructor
    # ==========================================================================
    @testset "Explicit Bar Constructor" begin
        # Create section with explicit bar positions
        As = 1.0u"inch^2"
        bars = [
            StructuralSizer.RebarLocation(2.5u"inch", 2.5u"inch", As),
            StructuralSizer.RebarLocation(13.5u"inch", 2.5u"inch", As),
            StructuralSizer.RebarLocation(2.5u"inch", 13.5u"inch", As),
            StructuralSizer.RebarLocation(13.5u"inch", 13.5u"inch", As),
        ]
        
        sec = RCColumnSection(16u"inch", 16u"inch", bars;
            cover = 1.5u"inch",
            tie_type = :tied,
            name = "Custom-4#9"
        )
        
        @test sec.name == "Custom-4#9"
        @test length(sec.bars) == 4
        @test ustrip(u"inch^2", sec.As_total) ≈ 4.0
    end

    # ==========================================================================
    # Test 10: Spiral Column
    # ==========================================================================
    @testset "Spiral Column" begin
        # Spiral columns require minimum 6 bars
        sec = RCColumnSection(
            b = 20u"inch",
            h = 20u"inch",
            bar_size = 8,
            n_bars = 8,
            cover = 1.5u"inch",
            tie_type = :spiral,
            arrangement = :perimeter
        )
        
        @test sec.tie_type == :spiral
    end

    # ==========================================================================
    # Test 11: Input Validation
    # ==========================================================================
    @testset "Input Validation" begin
        # Too few bars for tied column (minimum 4)
        @test_throws ErrorException RCColumnSection(
            b = 16u"inch", h = 16u"inch",
            bar_size = 9, n_bars = 3,
            cover = 1.5u"inch", tie_type = :tied
        )
        
        # Too few bars for spiral column (minimum 6)
        @test_throws ErrorException RCColumnSection(
            b = 20u"inch", h = 20u"inch",
            bar_size = 9, n_bars = 4,
            cover = 1.5u"inch", tie_type = :spiral
        )
    end

    # ==========================================================================
    # Test 12: Section Interface
    # ==========================================================================
    @testset "Section Interface" begin
        sec = RCColumnSection(
            b = 16u"inch",
            h = 16u"inch",
            bar_size = 9,
            n_bars = 8,
            cover = 1.5u"inch",
            tie_type = :tied,
            arrangement = :two_layer
        )
        
        # Width and depth
        @test StructuralSizer.section_width(sec) ≈ 16.0u"inch"
        @test StructuralSizer.section_depth(sec) ≈ 16.0u"inch"
        
        # Square check
        @test StructuralSizer.is_square(sec) == true
        
        # Number of bars
        @test StructuralSizer.n_bars(sec) == 8
    end

end
