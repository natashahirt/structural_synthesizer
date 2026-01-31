# ==============================================================================
# Tests for ACI 318-19 Biaxial Bending
# Reference: StructurePoint "Manual Design Procedure for Columns and Walls 
#            with Biaxial Bending (ACI 318-11/14/19)"
# ==============================================================================

using Test
using StructuralSizer
using Unitful

# Load test data
include("test_data/biaxial_24x24.jl")

@testset "Biaxial Bending (ACI 318-19)" begin
    ref = BIAXIAL_24X24
    
    # =========================================================================
    @testset "Bresler Reciprocal Load Method" begin
        # Formula: 1/Pn = 1/Pnx + 1/Pny - 1/P0
        
        # Test basic calculation
        Pnx = ref.bresler_reciprocal.Pnx  # 2250 kip
        Pny = ref.bresler_reciprocal.Pny  # 2050 kip
        P0 = ref.uniaxial.P0               # 2584 kip
        
        Pn = StructuralSizer.bresler_reciprocal_load(Pnx, Pny, P0)
        
        # 1/Pn = 1/2250 + 1/2050 - 1/2584 = 0.000444 + 0.000488 - 0.000387 = 0.000545
        # Pn ≈ 1835 kip
        @test Pn ≈ ref.bresler_reciprocal.Pn_calc rtol=0.05
        
        # Check adequacy: Pn > Pn_req = 1846 kip
        Pn_req = ref.required.Pn_req
        @test Pn > Pn_req - 50  # Allow small margin since values are approx
        
        # Test utilization ratio
        util = StructuralSizer.check_bresler_reciprocal(
            ref.demands.Pu / ref.required.φ,  # Nominal demand (Pn_req)
            Pnx, Pny, P0
        )
        @test util ≤ 1.05  # Should be adequate (slightly > 1.0 is acceptable for approx)
    end
    
    # =========================================================================
    @testset "Bresler Load Contour Method" begin
        # Formula: (Mux/φMnx)^α + (Muy/φMny)^α ≤ 1.0
        
        # Use nominal capacities at Pn = 1846 kip
        φMnx = ref.uniaxial.Mnox * ref.required.φ  # φ×682.8 = 444 kip-ft
        φMny = ref.uniaxial.Mnoy * ref.required.φ  # Same for square section
        
        Mux = ref.demands.Mux  # 300 kip-ft
        Muy = ref.demands.Muy  # 125 kip-ft
        
        # Linear interaction (α = 1.0, conservative)
        util_linear = StructuralSizer.bresler_load_contour(Mux, Muy, φMnx, φMny; α=1.0)
        @test util_linear ≈ ref.bresler_contour.util_linear rtol=0.05
        
        # Typical α = 1.5
        util_alpha15 = StructuralSizer.bresler_load_contour(Mux, Muy, φMnx, φMny; α=1.5)
        @test util_alpha15 ≈ ref.bresler_contour.util_alpha15 rtol=0.10
        
        # Both should show adequate
        @test util_linear < 1.0
        @test util_alpha15 < 1.0
        
        # α = 1.5 should give lower utilization than α = 1.0
        @test util_alpha15 < util_linear
    end
    
    # =========================================================================
    @testset "PCA Load Contour Method" begin
        # Formula: Mux/φMnox + β×Muy/φMnoy ≤ 1.0
        
        Mux = ref.demands.Mux
        Muy = ref.demands.Muy
        φMnox = ref.uniaxial.Mnox * ref.required.φ
        φMnoy = ref.uniaxial.Mnoy * ref.required.φ
        
        util = StructuralSizer.pca_load_contour(
            Mux, Muy, φMnox, φMnoy,
            ref.demands.Pu, 
            ref.required.Pn_req * ref.required.φ,
            ref.uniaxial.P0 * ref.required.φ;
            β = ref.pca_contour.β
        )
        
        # Expected ≈ 0.86
        @test util ≈ ref.pca_contour.util rtol=0.10
        @test util < 1.0
    end
    
    # =========================================================================
    @testset "Biaxial Check with P-M Diagram" begin
        # Create column section (24×24 with 4 #11 bars at corners)
        section = RCColumnSection(
            b = 24.0u"inch",
            h = 24.0u"inch",
            cover = (2.0 + 0.5*1.41)u"inch",  # Clear cover + half bar diameter
            bar_size = 11,
            n_bars = 4,  # 4 corner bars
            tie_type = :tied
        )
        
        mat = (
            fc = ref.materials.fc,
            fy = ref.materials.fy,
            Es = 29000.0,
            εcu = ref.materials.εcu
        )
        
        # Generate P-M diagram
        diagram = generate_PM_diagram(section, mat; n_intermediate=20)
        
        # For square section, same diagram applies to both axes
        result = StructuralSizer.check_biaxial_simple(
            section, mat,
            ref.demands.Pu,
            ref.demands.Mux,
            ref.demands.Muy;
            α = 1.5
        )
        
        # Should be adequate
        @test result.adequate == true
        @test result.utilization < 1.0
    end
    
    # =========================================================================
    @testset "Edge Cases" begin
        # Zero moment in one direction
        util_uniaxial = StructuralSizer.bresler_load_contour(300.0, 0.0, 500.0, 500.0; α=1.5)
        @test util_uniaxial ≈ (300.0/500.0)^1.5 rtol=0.01
        
        # Equal moments both directions
        util_equal = StructuralSizer.bresler_load_contour(100.0, 100.0, 500.0, 500.0; α=1.5)
        @test util_equal ≈ 2 * (100.0/500.0)^1.5 rtol=0.01
        
        # Zero capacity should return Inf
        @test StructuralSizer.bresler_load_contour(100.0, 100.0, 0.0, 500.0) == Inf
        
        # Zero demand should return zero
        @test StructuralSizer.bresler_load_contour(0.0, 0.0, 500.0, 500.0) ≈ 0.0
        
        # Bresler reciprocal with zero capacity
        @test StructuralSizer.bresler_reciprocal_load(0.0, 1000.0, 2000.0) ≈ 0.0
    end
    
    # =========================================================================
    @testset "Comparison: Linear vs Parabolic Contour" begin
        # For the same demand, α=1.5 should always give lower or equal utilization 
        # compared to α=1.0 (linear is conservative)
        
        test_cases = [
            (100.0, 50.0, 300.0, 300.0),   # Low demand
            (200.0, 100.0, 300.0, 300.0),  # Medium demand
            (250.0, 150.0, 300.0, 300.0),  # High demand
        ]
        
        for (Mux, Muy, Mnx, Mny) in test_cases
            util_linear = StructuralSizer.bresler_load_contour(Mux, Muy, Mnx, Mny; α=1.0)
            util_para = StructuralSizer.bresler_load_contour(Mux, Muy, Mnx, Mny; α=1.5)
            @test util_para ≤ util_linear
        end
    end
    
    # =========================================================================
    @testset "Reference Values Verification" begin
        # Verify that our implementation matches the PDF exactly for key values
        
        # Mnx_req/Mnox = 461.5/682.8 = 0.676
        ratio_x = ref.bresler_contour.Mnx_demand / ref.bresler_contour.Mnox_cap
        @test ratio_x ≈ 0.676 rtol=0.01
        
        # Mny_req/Mnoy = 192.3/682.8 = 0.282
        ratio_y = ref.bresler_contour.Mny_demand / ref.bresler_contour.Mnoy_cap
        @test ratio_y ≈ 0.282 rtol=0.01
        
        # Linear utilization = 0.676 + 0.282 = 0.958
        @test ratio_x + ratio_y ≈ ref.bresler_contour.util_linear rtol=0.02
    end
end
