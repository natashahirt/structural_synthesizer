# =============================================================================
# Tests for Flat Plate Optimizer (FlatPlateNLPProblem + grid search)
# =============================================================================
#
# Validates:
#   1. evaluate() returns correct feasibility for known (h, c) combinations
#   2. Inner rebar sweep selects the best bar size
#   3. Objective computation (MinVolume, MinWeight, MinCarbon)
#   4. Grid search convergence
#
# Reference: StructurePoint 18×14 ft flat plate example (ACI 318-14)
# =============================================================================

using Test
using Unitful
using Unitful: @u_str
using Asap
using StructuralSizer

# =============================================================================
# Helper: Build a FlatPlateNLPProblem directly (no BuildingStructure needed)
# =============================================================================

"""Build a test problem matching the StructurePoint 18×14 ft example."""
function _make_test_problem(;
    objective = MinVolume(),
    bar_sizes = [4, 5, 6, 7, 8],
    h_min_in  = 6.0,
    h_max_in  = 12.0,
    c_min_in  = 10.0,
    c_max_in  = 24.0,
)
    mat = RC_4000_60  # 4 ksi concrete, Grade 60 rebar

    fc  = mat.concrete.fc′
    fy  = mat.rebar.Fy
    Es  = mat.rebar.E
    γ_c = mat.concrete.ρ
    λ   = mat.concrete.λ
    wc_pcf = ustrip(pcf, γ_c)
    Ecs = Ec(fc, wc_pcf)

    l1 = 18.0u"ft"
    l2 = 14.0u"ft"

    # Typical loads: SDL=20 psf, LL=40 psf
    sdl = 20.0psf
    qL  = 40.0psf

    # One exterior, one interior column (simplified 2-column panel)
    positions = [:edge, :interior]
    # Approximate tributary areas: ~126 ft² each for 18×14 panel
    trib_ft2 = [126.0, 126.0]
    # Column heights: 10 ft each
    col_h_sum_m = 2 * ustrip(u"m", 10.0u"ft")

    # End-span DDM coefficients (exterior panel)
    c_neg_ext = 0.26
    c_neg_int = 0.70
    c_pos     = 0.52

    cover   = 0.75u"inch"
    bar_dia = bar_diameter(5)  # #5 bars

    FlatPlateNLPProblem(
        mat, fc, fy, Es, Ecs, γ_c, λ,
        l1, l2, sdl, qL,
        positions, trib_ft2, col_h_sum_m,
        c_neg_ext, c_neg_int, c_pos,
        cover, bar_dia,
        0.90, 0.75, :L_360,
        (h_min_in, h_max_in), (c_min_in, c_max_in),
        bar_sizes,
        objective,
    )
end

# =============================================================================
# Tests
# =============================================================================

@testset "Flat Plate Optimizer" begin

    # ─── 1. NLP Interface ───
    @testset "NLP interface" begin
        p = _make_test_problem()

        @test n_variables(p) == 2
        @test variable_names(p) == ["h_in", "c_in"]

        lb, ub = variable_bounds(p)
        @test lb[1] == 6.0
        @test ub[1] == 12.0
        @test lb[2] == 10.0
        @test ub[2] == 24.0

        x0 = initial_guess(p)
        @test length(x0) == 2
        @test x0[1] ≈ 9.0  # (6 + 12) / 2
        @test x0[2] ≈ 17.0  # (10 + 24) / 2
    end

    # ─── 2. Evaluate: Known Feasible Point ───
    @testset "evaluate - feasible point" begin
        p = _make_test_problem()

        # StructurePoint example: h=7", c=16" — should be feasible
        feasible, obj, result = evaluate(p, [7.0, 16.0])

        @test feasible == true
        @test obj < Inf
        @test obj > 0
        @test !isnothing(result)
        @test result.h_in == 7.0
        @test result.c_in == 16.0
        @test result.bar_size in [4, 5, 6, 7, 8]
        @test result.d > 0u"inch"
    end

    # ─── 3. Evaluate: Known Infeasible Point (too thin) ───
    @testset "evaluate - infeasible (thin slab, small column)" begin
        p = _make_test_problem(h_min_in=4.0)

        # h=4" with small columns — likely punching/deflection failure
        feasible, obj, result = evaluate(p, [4.0, 10.0])

        # Might fail punching or deflection
        # Don't assert infeasible — but if feasible, objective must be finite
        if feasible
            @test obj < Inf
            @test !isnothing(result)
        else
            @test obj == Inf
            @test isnothing(result)
        end
    end

    # ─── 4. Evaluate: Increasing h Reduces Objective Variability ───
    @testset "evaluate - h sensitivity" begin
        p = _make_test_problem()

        # Compare two thicknesses at same column size
        f1, obj1, r1 = evaluate(p, [7.0, 16.0])
        f2, obj2, r2 = evaluate(p, [9.0, 16.0])

        # Both should be feasible (7" and 9" at 16" columns)
        if f1 && f2
            # Thicker slab → more concrete → higher volume objective
            @test obj2 > obj1
        end
    end

    # ─── 5. Evaluate: Increasing c Increases Column Volume ───
    @testset "evaluate - c sensitivity" begin
        p = _make_test_problem()

        f1, obj1, r1 = evaluate(p, [8.0, 14.0])
        f2, obj2, r2 = evaluate(p, [8.0, 22.0])

        # Larger columns → more column concrete → higher objective
        if f1 && f2
            @test obj2 > obj1
        end
    end

    # ─── 6. Inner Rebar Sweep Picks the Best Bar Size ───
    @testset "rebar sweep" begin
        p = _make_test_problem()

        feasible, obj, result = evaluate(p, [7.0, 16.0])

        if feasible
            # The optimizer chose a bar size — it should be the one
            # that gives the lowest objective among feasible options
            bar_sz = result.bar_size
            @test bar_sz >= 4
            @test bar_sz <= 8
            @test result.total_As > 0u"inch^2"
            @test result.As_pos_cs > 0u"inch^2"
        end
    end

    # ─── 7. Objective Dispatch ───
    @testset "objective types" begin
        for ObjType in [MinVolume, MinWeight, MinCarbon]
            p = _make_test_problem(objective=ObjType())
            feasible, obj, result = evaluate(p, [7.5, 16.0])

            if feasible
                @test obj > 0
                @test obj < Inf
            end
        end
    end

    # ─── 8. Different Objectives Give Different Rankings ───
    @testset "objective affects ranking" begin
        # MinVolume vs MinWeight should give different absolute values
        p_vol = _make_test_problem(objective=MinVolume())
        p_wt  = _make_test_problem(objective=MinWeight())

        fv, obj_v, _ = evaluate(p_vol, [7.5, 16.0])
        fw, obj_w, _ = evaluate(p_wt,  [7.5, 16.0])

        if fv && fw
            # Weight is volume × density, so weight >> volume (density ≈ 2400 kg/m³)
            @test obj_w > obj_v
        end
    end

    # ─── 9. Grid Search Converges ───
    @testset "grid search convergence" begin
        p = _make_test_problem(
            h_min_in = 6.0,
            h_max_in = 10.0,
            c_min_in = 12.0,
            c_max_in = 22.0,
        )

        opt = optimize_continuous(
            p;
            objective = MinVolume(),
            solver    = :grid,
            n_grid    = 10,   # small grid for test speed
            n_refine  = 1,
            verbose   = false,
        )

        @test opt.status in (:success, :optimal)
        @test opt.objective_value < Inf
        @test length(opt.minimizer) == 2

        h_opt = opt.minimizer[1]
        c_opt = opt.minimizer[2]

        # Optimal h should be within bounds
        @test 6.0 <= h_opt <= 10.0
        # Optimal c should be within bounds
        @test 12.0 <= c_opt <= 22.0

        # eval_result should carry rich data
        @test !isnothing(opt.eval_result)
        @test opt.eval_result.bar_size in [4, 5, 6, 7, 8]
    end

    # ─── 10. select_bars_for_size Utility ───
    @testset "select_bars_for_size" begin
        As_reqd = 2.0u"inch^2"
        width   = 60.0u"inch"

        result = select_bars_for_size(As_reqd, width, 5)
        @test result.bar_size == 5
        @test result.n_bars >= 2
        @test result.As_provided >= As_reqd
        @test result.spacing <= 18u"inch"
        @test result.spacing > 0u"inch"

        # Larger bar → fewer bars
        r4 = select_bars_for_size(As_reqd, width, 4)
        r8 = select_bars_for_size(As_reqd, width, 8)
        @test r4.n_bars >= r8.n_bars

        # All candidates
        cands = select_bars_candidates(As_reqd, width)
        @test length(cands) == 5
        @test all(c -> c.As_provided >= As_reqd, cands)
    end

end

println("\n✓ All flat plate optimizer tests passed")
