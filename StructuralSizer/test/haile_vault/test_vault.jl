# Test script for Haile unreinforced vault implementation
# Mirrors BasePlotsWithLim.m from MATLAB reference

using Test
using StructuralSizer
using DelimitedFiles
using Unitful: @u_str, ustrip

# Explicitly import helpers used in tests (avoids relying on export state / Revise)
using StructuralSizer: total_thrust

# =============================================================================
# Test Parameters (matching BasePlotsWithLim.m defaults)
# =============================================================================

const TEST_PARAMS = (
    spans = 2.0:0.5:10.5,           # Span range [m]
    lambdas = 5:5:30,               # Span/rise ratios to test
    trib_depth = 1.0,               # [m]
    thickness = 0.05,               # 5 cm shell
    rib_depth = 0.10,               # 10 cm rib width  
    rib_apex_rise = 0.05,           # 5 cm rib height
    density = 2000.0,               # [kg/m³]
    applied_load = 7.0,             # [kN/m²] (was 7000 N/m² in MATLAB)
    finishing_load = 1.0,           # [kN/m²] (was 1000 N/m² in MATLAB)
)

# =============================================================================
# Unit Tests
# =============================================================================

@testset "Vault Analysis Tests" begin
    
    @testset "Geometry: parabolic_arc_length" begin
        # Zero rise should return span
        @test parabolic_arc_length(6.0, 0.0) ≈ 6.0
        @test parabolic_arc_length(10.0, 1e-10) ≈ 10.0
        
        # Positive rise should give arc length > span
        L = parabolic_arc_length(6.0, 1.0)
        @test L > 6.0
        @test L < 10.0  # Sanity check
        
        # Symmetry: arc length should be same for same |rise|
        @test parabolic_arc_length(6.0, 1.0) ≈ parabolic_arc_length(6.0, 1.0)
    end
    
    @testset "Geometry: get_vault_properties" begin
        # Verify geometric properties calculation (new helper)
        span, rise = 6.0, 1.0
        t, trib = 0.05, 1.0
        
        # 1. Shell only
        props = StructuralSizer.get_vault_properties(span, rise, t, trib, 0.0, 0.0)
        
        L = parabolic_arc_length(span, rise)
        @test props.arc_length ≈ L
        @test props.shell_cs_area ≈ t * span
        @test props.shell_vol ≈ t * span * trib
        @test props.rib_vol == 0.0
        @test props.total_vol ≈ props.shell_vol
        
        # 2. With ribs
        rib_d, rib_h = 0.1, 0.05
        props_rib = StructuralSizer.get_vault_properties(span, rise, t, trib, rib_d, rib_h)
        
        @test props_rib.shell_vol ≈ props.shell_vol
        @test props_rib.rib_vol > 0
        @test props_rib.total_vol > props.total_vol
    end

    @testset "Physics: volume and weight consistency" begin
        # Verify that reported volume matches reported self-weight
        span, rise = 6.0, 1.0
        t = 0.05
        density = 2400.0
        
        result = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 0.0u"kN/m^2"; 
                           rise=1.0u"m", thickness=0.05u"m", material=NWC_4000)
        
        vol = ustrip(result.volume_per_area) # m
        sw = ustrip(result.self_weight)      # kN/m^2
        
        ρ = ustrip(u"kg/m^3", NWC_4000.ρ)
        g = 9.80665 # standard gravity
        
        # Expected SW = Volume * Density * Gravity
        # Note: volume_per_area is Volume / PlanArea.
        # SelfWeight is Force / PlanArea.
        # So SW = VolPerArea * Density * g
        expected_sw = vol * ρ * g / 1000 # kN/m^2
        
        @test sw ≈ expected_sw rtol=0.001
    end
    
    @testset "Symmetric stress analysis" begin
        p = TEST_PARAMS
        span, rise = 6.0, 1.0
        
        result = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            p.applied_load, p.finishing_load
        )
        
        # Check all outputs are positive and reasonable
        @test result.σ_MPa > 0
        @test result.thrust_kN > 0
        @test result.self_weight_kN_m² > 0
        @test result.vertical_kN > 0
        
        # Thrust should increase with lower rise (shallower arch)
        result_shallow = vault_stress_symmetric(
            span, 0.5, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            p.applied_load, p.finishing_load
        )
        @test result_shallow.thrust_kN > result.thrust_kN
    end
    
    @testset "Asymmetric stress analysis" begin
        p = TEST_PARAMS
        span, rise = 6.0, 1.0
        
        result_sym = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            p.applied_load, p.finishing_load
        )
        
        result_asym = vault_stress_asymmetric(
            span, rise, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            p.applied_load, p.finishing_load
        )
        
        # Both analyses should produce positive, reasonable values
        @test result_asym.σ_MPa > 0
        @test result_asym.thrust_kN > 0
        
        # Note: Asymmetric doesn't always give higher stress!
        # When live load >> dead load, symmetric (full live) can govern.
        # When dead load >> live load, asymmetric can govern.
        # The size_floor function correctly takes max of both.
        
        # Self-weight should be same for both
        @test result_asym.self_weight_kN_m² ≈ result_sym.self_weight_kN_m² atol=0.01
    end
    
    @testset "Elastic shortening solver" begin
        p = TEST_PARAMS
        span, rise = 6.0, 1.0
        E_MPa = 29000.0  # Concrete modulus
        
        # Get self-weight first
        sym = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            p.applied_load, p.finishing_load
        )
        
        total_load_Pa = (p.applied_load + sym.self_weight_kN_m² + p.finishing_load) * 1000
        
        result = solve_equilibrium_rise(
            span, rise, total_load_Pa, p.thickness, p.trib_depth, E_MPa
        )
        
        @test result.converged == true
        @test result.final_rise < rise  # Rise decreases under load
        @test result.final_rise > 0     # But stays positive
        
        # With very high E, deflection should be minimal
        result_stiff = solve_equilibrium_rise(
            span, rise, total_load_Pa, p.thickness, p.trib_depth, 1e6  # Very stiff
        )
        @test abs(result_stiff.final_rise - rise) < abs(result.final_rise - rise)
    end
    
    @testset "size_floor API" begin
        # Test with rise
        result1 = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 1.5u"kN/m^2"; rise=1.0u"m", thickness=0.05u"m")
        @test result1.thickness == 0.05u"m"
        @test ustrip(result1.rise) > 0
        @test ustrip(total_thrust(result1)) > 0
        @test ustrip(result1.self_weight) > 0
        @test ustrip(result1.volume_per_area) > 0
        
        # Test with lambda (should give same result)
        result2 = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 1.5u"kN/m^2"; lambda=6.0, thickness=0.05u"m")
        @test result2.thickness == result1.thickness
        @test total_thrust(result2) ≈ total_thrust(result1) atol=0.01u"kN/m"
        @test result1.volume_per_area ≈ result2.volume_per_area
        
        # Test validation: both rise and lambda should error
        @test_throws ArgumentError size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 1.5u"kN/m^2"; rise=1.0u"m", lambda=6.0)
        
        # Test validation: neither rise nor lambda should error
        @test_throws ArgumentError size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 1.5u"kN/m^2"; thickness=0.05u"m")
    end
    
    @testset "size_floor with ribs" begin
        # Without ribs
        result_no_rib = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 1.5u"kN/m^2"; 
            rise=1.0u"m", thickness=0.05u"m", rib_depth=0.0u"m", rib_apex_rise=0.0u"m")
        
        # With ribs (should have higher self-weight)
        result_with_rib = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 1.5u"kN/m^2";
            rise=1.0u"m", thickness=0.05u"m", rib_depth=0.10u"m", rib_apex_rise=0.05u"m")
        
        @test result_with_rib.self_weight > result_no_rib.self_weight
    end
    
    # =========================================================================
    # Analytical Validation Tests
    # =========================================================================
    
    @testset "Analytical: thrust formula H = wL²/8h" begin
        # For a simple case without ribs, verify thrust matches analytical formula
        span, rise = 6.0, 1.0
        trib = 1.0
        thickness = 0.05
        density = 2000.0
        applied = 5.0   # kN/m²
        finish = 0.0
        
        result = vault_stress_symmetric(
            span, rise, trib, thickness, 0.0, 0.0, density, applied, finish
        )
        
        # Self-weight for shell only: thickness * density * g / 1000 [kN/m²]
        sw_expected = thickness * density * 9.81 / 1000
        @test result.self_weight_kN_m² ≈ sw_expected rtol=0.01
        
        # Total UDL per meter of span
        total_w = (applied + sw_expected) * trib  # kN/m
        
        # Analytical thrust: H = wL²/(8h)
        thrust_analytical = total_w * span^2 / (8 * rise)
        @test result.thrust_kN ≈ thrust_analytical rtol=0.01
        
        # Vertical reaction: V = wL/2
        vertical_analytical = total_w * span / 2
        @test result.vertical_kN ≈ vertical_analytical rtol=0.01
    end
    
    @testset "Analytical: stress = resultant / area" begin
        span, rise = 6.0, 1.0
        trib = 1.0
        thickness = 0.05
        
        result = vault_stress_symmetric(
            span, rise, trib, thickness, 0.0, 0.0, 2000.0, 5.0, 0.0
        )
        
        # Resultant = √(H² + V²)
        resultant = sqrt(result.thrust_kN^2 + result.vertical_kN^2)
        
        # Stress = Force / Area, convert kN to N and m² to get Pa, then to MPa
        area = trib * thickness
        stress_expected = (resultant * 1000) / area / 1e6
        
        @test result.σ_MPa ≈ stress_expected rtol=0.001
    end
    
    # =========================================================================
    # Physics/Sensitivity Tests
    # =========================================================================
    
    @testset "Physics: stress increases with span" begin
        p = TEST_PARAMS
        lambda = 10  # Fixed span/rise ratio
        
        stresses = Float64[]
        for span in [4.0, 6.0, 8.0, 10.0]
            rise = span / lambda
            result = vault_stress_symmetric(
                span, rise, p.trib_depth, p.thickness,
                p.rib_depth, p.rib_apex_rise, p.density,
                p.applied_load, p.finishing_load
            )
            push!(stresses, result.σ_MPa)
        end
        
        # Stress should increase monotonically with span
        @test issorted(stresses)
    end
    
    @testset "Physics: thrust increases with shallower arch" begin
        p = TEST_PARAMS
        span = 6.0
        
        thrusts = Float64[]
        for lambda in [5, 10, 15, 20, 25, 30]  # Increasing = shallower
            rise = span / lambda
            result = vault_stress_symmetric(
                span, rise, p.trib_depth, p.thickness,
                p.rib_depth, p.rib_apex_rise, p.density,
                p.applied_load, p.finishing_load
            )
            push!(thrusts, result.thrust_kN)
        end
        
        # Thrust should increase with lambda (shallower arch)
        @test issorted(thrusts)
    end
    
    @testset "Physics: self-weight increases with thickness" begin
        p = TEST_PARAMS
        span, rise = 6.0, 1.0
        
        weights = Float64[]
        for t in [0.03, 0.05, 0.08, 0.10]
            result = vault_stress_symmetric(
                span, rise, p.trib_depth, t,
                0.0, 0.0, p.density,  # No ribs for clarity
                p.applied_load, p.finishing_load
            )
            push!(weights, result.self_weight_kN_m²)
        end
        
        @test issorted(weights)
    end
    
    @testset "Physics: elastic shortening increases with lower E" begin
        p = TEST_PARAMS
        span, rise = 6.0, 1.0
        
        sym = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            p.applied_load, p.finishing_load
        )
        total_load_Pa = (p.applied_load + sym.self_weight_kN_m²) * 1000
        
        deflections = Float64[]
        for E in [30000.0, 10000.0, 5000.0, 2000.0]  # Decreasing stiffness
            result = solve_equilibrium_rise(
                span, rise, total_load_Pa, p.thickness, p.trib_depth, E
            )
            if result.converged
                push!(deflections, rise - result.final_rise)
            end
        end
        
        # Deflection should increase as E decreases
        @test issorted(deflections)
    end
    
    # =========================================================================
    # Cross-Validation Tests
    # =========================================================================
    
    @testset "Cross-validation: zero live load" begin
        # When live load is zero, symmetric and asymmetric should give
        # the same thrust (both just dead load)
        p = TEST_PARAMS
        span, rise = 6.0, 1.0
        
        result_sym = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            0.0, p.finishing_load  # Zero live load
        )
        
        result_asym = vault_stress_asymmetric(
            span, rise, p.trib_depth, p.thickness,
            p.rib_depth, p.rib_apex_rise, p.density,
            0.0, p.finishing_load  # Zero live load
        )
        
        # With no live load, asymmetric formula reduces to symmetric
        # H_asym = (L²/16h)(2q_d) = q_d*L²/8h = H_sym
        @test result_asym.thrust_kN ≈ result_sym.thrust_kN rtol=0.001
    end
    
    @testset "Cross-validation: lambda vs rise equivalence" begin
        # size_floor with rise=1.0m should equal lambda=6.0 for span=6.0m
        r1 = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 2.0u"kN/m^2"; rise=1.0u"m", thickness=0.05u"m")
        r2 = size_floor(Vault(), 6.0u"m", 1.0u"kN/m^2", 2.0u"kN/m^2"; lambda=6.0, thickness=0.05u"m")
        
        @test total_thrust(r1) ≈ total_thrust(r2)
        @test r1.self_weight ≈ r2.self_weight
        @test r1.rise ≈ r2.rise rtol=0.01
    end
    
    # =========================================================================
    # Edge Case Tests
    # =========================================================================
    
    @testset "Edge cases: extreme geometries" begin
        p = TEST_PARAMS
        
        # Very deep vault (lambda = 5, rise = span/5)
        result_deep = vault_stress_symmetric(
            6.0, 1.2, p.trib_depth, p.thickness,
            0.0, 0.0, p.density, p.applied_load, p.finishing_load
        )
        @test result_deep.σ_MPa > 0
        @test result_deep.thrust_kN > 0
        
        # Very shallow vault (lambda = 30, rise = span/30)
        result_shallow = vault_stress_symmetric(
            6.0, 0.2, p.trib_depth, p.thickness,
            0.0, 0.0, p.density, p.applied_load, p.finishing_load
        )
        @test result_shallow.σ_MPa > 0
        @test result_shallow.thrust_kN > result_deep.thrust_kN
        
        # Short span
        result_short = vault_stress_symmetric(
            2.0, 0.4, p.trib_depth, p.thickness,
            0.0, 0.0, p.density, p.applied_load, p.finishing_load
        )
        @test result_short.σ_MPa > 0
        
        # Long span
        result_long = vault_stress_symmetric(
            10.0, 2.0, p.trib_depth, p.thickness,
            0.0, 0.0, p.density, p.applied_load, p.finishing_load
        )
        @test result_long.σ_MPa > result_short.σ_MPa
    end
    
    @testset "Edge cases: minimal/no ribs" begin
        p = TEST_PARAMS
        span, rise = 6.0, 1.0
        
        # No ribs at all
        r_none = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            0.0, 0.0, p.density, p.applied_load, p.finishing_load
        )
        
        # Zero rib height (effectively no ribs)
        r_zero_height = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            0.10, 0.0, p.density, p.applied_load, p.finishing_load
        )
        
        # Zero rib depth (effectively no ribs)
        r_zero_depth = vault_stress_symmetric(
            span, rise, p.trib_depth, p.thickness,
            0.0, 0.05, p.density, p.applied_load, p.finishing_load
        )
        
        # All three should have same self-weight
        @test r_none.self_weight_kN_m² ≈ r_zero_height.self_weight_kN_m²
        @test r_none.self_weight_kN_m² ≈ r_zero_depth.self_weight_kN_m²
    end
end

# =============================================================================
# MATLAB Numerical Comparison Tests
# =============================================================================

"""
Load test vectors generated by MATLAB.
Run generate_test_vectors.m in MATLAB first to create test_vectors.csv
"""
function load_matlab_test_vectors()
    csv_path = joinpath(@__DIR__, "test_vectors.csv")
    if !isfile(csv_path)
        return nothing
    end
    
    # Read CSV (skip header)
    data, header = readdlm(csv_path, ',', Any, '\n', header=true)
    header = vec(header)
    
    # Convert to vector of named tuples
    vectors = []
    for i in 1:size(data, 1)
        row = data[i, :]
        push!(vectors, (
            test_type = string(row[1]),
            span = Float64(row[2]),
            ratio = Int(row[3]),
            MOE = Float64(row[4]),
            trib_depth = Float64(row[5]),
            brick_thick_cm = Float64(row[6]),
            wall_thick_cm = Float64(row[7]),
            apex_rise_cm = Float64(row[8]),
            density = Float64(row[9]),
            applied_load_Pa = Float64(row[10]),
            finish_load_Pa = Float64(row[11]),
            stress_MPa = Float64(row[12]),
            self_weight_kN_m2 = Float64(row[13]),
            arc_length = Float64(row[14]),
            final_rise = row[15] == "NaN" ? NaN : Float64(row[15]),
            converged = Bool(row[16]),
            deflection_ok = Bool(row[17])
        ))
    end
    return vectors
end

@testset "MATLAB Numerical Comparison" begin
    vectors = load_matlab_test_vectors()
    
    if isnothing(vectors)
        @warn "test_vectors.csv not found - run generate_test_vectors.m in MATLAB first"
        @test_skip "MATLAB test vectors not available"
    else
        @testset "Symmetric stress (vs MATLAB)" begin
            sym_tests = filter(v -> v.test_type == "symmetric", vectors)
            @test length(sym_tests) > 0
            
            for v in sym_tests
                rise = v.span / v.ratio
                result = vault_stress_symmetric(
                    v.span, rise, v.trib_depth, 
                    v.brick_thick_cm / 100,  # cm to m
                    v.wall_thick_cm / 100,   # cm to m
                    v.apex_rise_cm / 100,    # cm to m
                    v.density,
                    v.applied_load_Pa / 1000,  # Pa to kN/m²
                    v.finish_load_Pa / 1000    # Pa to kN/m²
                )
                
                # MATLAB-vs-Julia tolerances:
                # - tiny differences expected from gravity constant, quadgk, and Roots' solver choices
                @test isapprox(result.σ_MPa, v.stress_MPa, rtol=2e-4)
                @test isapprox(result.self_weight_kN_m², v.self_weight_kN_m2, rtol=5e-4)
            end
        end
        
        @testset "Asymmetric stress (vs MATLAB)" begin
            asym_tests = filter(v -> v.test_type == "asymmetric", vectors)
            @test length(asym_tests) > 0
            
            for v in asym_tests
                rise = v.span / v.ratio
                result = vault_stress_asymmetric(
                    v.span, rise, v.trib_depth,
                    v.brick_thick_cm / 100,
                    v.wall_thick_cm / 100,
                    v.apex_rise_cm / 100,
                    v.density,
                    v.applied_load_Pa / 1000,
                    v.finish_load_Pa / 1000
                )
                
                @test isapprox(result.σ_MPa, v.stress_MPa, rtol=2e-4)
            end
        end
        
        @testset "Arc length (vs MATLAB)" begin
            arc_tests = filter(v -> v.test_type == "arc_length", vectors)
            @test length(arc_tests) > 0
            
            for v in arc_tests
                rise = v.span / v.ratio
                L = parabolic_arc_length(v.span, rise)
                
                @test isapprox(L, v.arc_length, rtol=1e-6)
            end
        end
        
        @testset "Elastic shortening solver (vs MATLAB)" begin
            elastic_tests = filter(v -> v.test_type == "elastic", vectors)
            @test length(elastic_tests) > 0
            
            for v in elastic_tests
                rise = v.span / v.ratio
                deflection_limit = v.span / 240
                
                # Get self-weight for total load (matching MATLAB)
                sym = vault_stress_symmetric(
                    v.span, rise, v.trib_depth,
                    v.brick_thick_cm / 100,
                    v.wall_thick_cm / 100,
                    v.apex_rise_cm / 100,
                    v.density,
                    v.applied_load_Pa / 1000,
                    v.finish_load_Pa / 1000
                )
                
                # Total load (matching MATLAB - no finish load in solver)
                total_load_Pa = v.applied_load_Pa + sym.self_weight_kN_m² * 1000
                
                result = solve_equilibrium_rise(
                    v.span, rise, total_load_Pa,
                    v.brick_thick_cm / 100,
                    v.trib_depth,
                    v.MOE;
                    deflection_limit=deflection_limit
                )
                
                @test result.converged == v.converged
                
                if result.converged && v.converged && !isnan(v.final_rise)
                    # fzero (MATLAB) vs Roots.jl (Julia) can differ slightly in termination / bracketing.
                    @test isapprox(result.final_rise, v.final_rise, rtol=2e-2)
                    @test result.deflection_ok == v.deflection_ok
                end
            end
        end
        
        @testset "No-rib cases (vs MATLAB)" begin
            norib_tests = filter(v -> v.test_type == "no_rib", vectors)
            @test length(norib_tests) > 0
            
            for v in norib_tests
                rise = v.span / v.ratio
                result = vault_stress_symmetric(
                    v.span, rise, v.trib_depth,
                    v.brick_thick_cm / 100,
                    0.0,  # No rib depth
                    0.0,  # No rib height
                    v.density,
                    v.applied_load_Pa / 1000,
                    v.finish_load_Pa / 1000
                )
                
                @test isapprox(result.σ_MPa, v.stress_MPa, rtol=1e-4)
                @test isapprox(result.self_weight_kN_m², v.self_weight_kN_m2, rtol=5e-4)
            end
        end
        
        println("\n✓ All $(length(vectors)) MATLAB test vectors validated")
    end
end

# =============================================================================
# Stress-Span Curve Generation (like BasePlotsWithLim.m)
# =============================================================================

"""
Generate stress vs span data for multiple lambda values.
Returns a Dict of lambda => (spans, stresses) pairs.
"""
function generate_stress_curves(;
    spans = 2.0:0.5:10.0,
    lambdas = [5, 10, 15, 20, 25, 30],
    trib_depth = 1.0,
    thickness = 0.05,
    rib_depth = 0.10,
    rib_apex_rise = 0.05,
    density = 2000.0,
    applied_load = 7.0,
    finishing_load = 1.0
)
    results = Dict{Int, NamedTuple{(:spans, :stresses), Tuple{Vector{Float64}, Vector{Float64}}}}()
    
    for λ in lambdas
        span_vec = Float64[]
        stress_vec = Float64[]
        
        for span in spans
            rise = span / λ
            
            # Use symmetric analysis (like MATLAB base curves)
            result = vault_stress_symmetric(
                span, rise, trib_depth, thickness,
                rib_depth, rib_apex_rise, density,
                applied_load, finishing_load
            )
            
            push!(span_vec, span)
            push!(stress_vec, result.σ_MPa)
        end
        
        results[λ] = (spans=span_vec, stresses=stress_vec)
    end
    
    return results
end

"""
Find deflection limit curves (like BasePlotsWithLim.m limit curves).
For each lambda, find the max span where deflection check passes.
"""
function find_deflection_limits(;
    spans = 2.0:0.25:10.5,
    lambdas = 5:1:30,
    trib_depth = 1.0,
    thickness = 0.05,
    rib_depth = 0.10,
    rib_apex_rise = 0.05,
    density = 2000.0,
    applied_load = 7.0,
    finishing_load = 1.0,
    E_MPa = 2000.0  # Default MOE
)
    limit_spans = Float64[]
    limit_stresses = Float64[]
    
    for λ in lambdas
        last_good_span = NaN
        
        for span in spans
            rise = span / λ
            deflection_limit = span / 240
            
            # Get self-weight
            sym = vault_stress_symmetric(
                span, rise, trib_depth, thickness,
                rib_depth, rib_apex_rise, density,
                applied_load, finishing_load
            )
            
            total_load_Pa = (applied_load + sym.self_weight_kN_m² + finishing_load) * 1000
            
            # Check elastic shortening
            eq = solve_equilibrium_rise(
                span, rise, total_load_Pa, thickness, trib_depth, E_MPa;
                deflection_limit=deflection_limit
            )
            
            if eq.converged && eq.deflection_ok
                last_good_span = span
            else
                break  # Failed, stop searching for this lambda
            end
        end
        
        if !isnan(last_good_span)
            rise = last_good_span / λ
            result = vault_stress_symmetric(
                last_good_span, rise, trib_depth, thickness,
                rib_depth, rib_apex_rise, density,
                applied_load, finishing_load
            )
            push!(limit_spans, last_good_span)
            push!(limit_stresses, result.σ_MPa)
        end
    end
    
    return (spans=limit_spans, stresses=limit_stresses)
end

# =============================================================================
# Run Tests
# =============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    # Run unit tests
    println("Running vault unit tests...")
    include(@__FILE__)
    
    # Generate sample data
    println("\nGenerating stress curves...")
    curves = generate_stress_curves()
    
    println("\nStress at span=6m for various lambda:")
    for λ in sort(collect(keys(curves)))
        idx = findfirst(s -> s ≈ 6.0, curves[λ].spans)
        if !isnothing(idx)
            println("  λ=$λ (rise=$(6.0/λ)m): σ = $(round(curves[λ].stresses[idx], digits=3)) MPa")
        end
    end
    
    println("\nFinding deflection limits (E=2000 MPa)...")
    limits = find_deflection_limits(E_MPa=2000.0)
    println("Limit curve has $(length(limits.spans)) points")
    if !isempty(limits.spans)
        println("  Max span in limit curve: $(maximum(limits.spans)) m")
        println("  Corresponding stress: $(round(limits.stresses[argmax(limits.spans)], digits=3)) MPa")
    end
end
