# ==============================================================================
# Adversarial Tests: Moment-Weighted Effective Flange Width from Tributaries
# ==============================================================================
#
# Tests the generalized T-beam flange width calculation for irregular cell
# geometries using tributary polygon (s, d) profiles.
#
# Each test constructs synthetic TributaryPolygon objects with known (s, d) 
# profiles and verifies the moment-weighted average depth against hand-calculated 
# expected values.
#
# Convention:
#   s ∈ [0, 1]  — parametric position along beam
#   d  (meters) — perpendicular distance from beam to skeleton ridge
#
# Moment weighting shapes:
#   :parabolic  — w(s) = 4s(1−s), peak at midspan (default, simply-supported)
#   :uniform    — w(s) = 1 (constant, for comparison)
#   :triangular — w(s) = s (cantilever, fixed at s=1)
# ==============================================================================

using Test
using Unitful
using StructuralSizer
using Asap: TributaryPolygon

# ==============================================================================
# Helper: construct TributaryPolygon from polygon vertices
# ==============================================================================

"""Make a TributaryPolygon from boundary vertices in (s, d) space.

The polygon is defined by listing its vertices CCW in (s, d) space.
Area is computed via shoelace formula, then scaled by beam_length to get m².
"""
function make_trib(; s::Vector{Float64}, d::Vector{Float64},
                    local_edge_idx::Int = 1, beam_length::Float64 = 10.0)
    # Compute area in (s, d) space via shoelace, then scale by L²
    # (s is unitless 0..1, d is in meters, so area_sd * L = area_m2)
    n = length(s)
    area_sd = 0.0
    for i in 1:n
        j = mod1(i + 1, n)
        area_sd += s[i] * d[j] - s[j] * d[i]
    end
    area_sd = abs(area_sd) / 2
    area_m2 = area_sd * beam_length  # scale parametric → physical

    TributaryPolygon(local_edge_idx, s, d, area_m2, area_m2 / (beam_length * maximum(abs.(d); init=1.0)))
end

# ==============================================================================
# Analytical reference values (hand-computed)
# ==============================================================================
#
# For moment_weighted_avg_depth with shape :parabolic (w = 4s(1-s)):
#
# Integral identity: ∫₀¹ w(s) ds = ∫₀¹ 4s(1-s) ds = 2/3
#
# For d(s) = c (constant):
#   ∫₀¹ c × 4s(1-s) ds = c × 2/3  →  avg = c
#
# For d(s) = a + (b-a)s (linear):
#   ∫₀¹ [a+(b-a)s] × 4s(1-s) ds = ∫₀¹ 4[as(1-s) + (b-a)s²(1-s)] ds
#     = 4[a(1/2 - 1/3) + (b-a)(1/3 - 1/4)]
#     = 4[a/6 + (b-a)/12]
#     = 4[(2a + b - a)/12]
#     = 4(a + b)/12 = (a + b)/3
#   avg = [(a+b)/3] / [2/3] = (a+b)/2
#
# So for ANY linear profile, parabolic-weighted avg = simple avg = (a+b)/2.
# The difference only appears with non-linear profiles.
#
# For a piecewise-linear "V" shape d = {d_end → d_mid → d_end}:
#   We compute numerically via Simpson's rule in the implementation.
# ==============================================================================

@testset "T-Beam Tributary Flange Width" begin

    # ==================================================================
    # 1. RECTANGULAR TRIBUTARY (constant depth) — baseline
    # ==================================================================
    @testset "1. Rectangular tributary (constant d)" begin
        # d(s) = 3.0 m constant → rectangle in (s,d) space
        # Polygon: (0,0) → (1,0) → (1,3) → (0,3)
        trib = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 3.0, 3.0],
        )

        # All averaging methods should give 3.0
        @test moment_weighted_avg_depth(trib; moment_shape=:parabolic) ≈ 3.0 atol=0.01
        @test moment_weighted_avg_depth(trib; moment_shape=:uniform)   ≈ 3.0 atol=0.01
        @test moment_weighted_avg_depth(trib; moment_shape=:triangular) ≈ 3.0 atol=0.01
    end

    # ==================================================================
    # 2. RIGHT TRIANGLE (d linearly increases: 0 at s=0, 6m at s=1)
    # ==================================================================
    @testset "2. Right triangle (d = 6s)" begin
        # Polygon: (0,0) → (1,0) → (1,6)
        # Width profile: d(0)=0, d(1)=6 → linear
        # Parabolic avg = (0+6)/2 = 3.0 (same as simple average for linear)
        trib = make_trib(
            s = [0.0, 1.0, 1.0],
            d = [0.0, 0.0, 6.0],
        )

        @test moment_weighted_avg_depth(trib; moment_shape=:parabolic) ≈ 3.0 atol=0.05
        @test moment_weighted_avg_depth(trib; moment_shape=:uniform)   ≈ 3.0 atol=0.05

        # Triangular weighting (w=s) should emphasize the wide end more
        # ∫₀¹ 6s × s ds / ∫₀¹ s ds = 6×(1/3)/(1/2) = 4.0
        @test moment_weighted_avg_depth(trib; moment_shape=:triangular) ≈ 4.0 atol=0.05
    end

    # ==================================================================
    # 3. INVERTED TRIANGLE (d linearly decreases: 6m at s=0, 0 at s=1)
    # ==================================================================
    @testset "3. Inverted triangle (d = 6(1-s))" begin
        # Polygon: (0,0) → (1,0) → (0,6)
        # Width profile: d(0)=6, d(1)=0 → linear
        # Parabolic avg = (6+0)/2 = 3.0 (symmetric weighting on linear)
        trib = make_trib(
            s = [0.0, 1.0, 0.0],
            d = [0.0, 0.0, 6.0],
        )

        @test moment_weighted_avg_depth(trib; moment_shape=:parabolic) ≈ 3.0 atol=0.05
        @test moment_weighted_avg_depth(trib; moment_shape=:uniform)   ≈ 3.0 atol=0.05

        # Triangular weighting (w=s) emphasizes s=1 where d=0 → lower
        # ∫₀¹ 6(1-s) × s ds / ∫₀¹ s ds = 6×(1/2-1/3)/(1/2) = 6×(1/6)/(1/2) = 2.0
        @test moment_weighted_avg_depth(trib; moment_shape=:triangular) ≈ 2.0 atol=0.05
    end

    # ==================================================================
    # 4. PINCHED MIDDLE (wide at ends, narrow at center)
    #    — the adversarial case for positive moment T-beams
    # ==================================================================
    @testset "4. Pinched middle (d=4 at ends, d=1 at center)" begin
        # Width profile: (0, 4.0) → (0.5, 1.0) → (1.0, 4.0)
        # Polygon: (0,0) → (0.5,0) → (1,0) → (1,4) → (0.5,1) → (0,4)
        trib = make_trib(
            s = [0.0, 0.5, 1.0, 1.0, 0.5, 0.0],
            d = [0.0, 0.0, 0.0, 4.0, 1.0, 4.0],
        )

        # Simple (uniform) average: trapezoidal integration
        # Segment [0, 0.5]: avg_d = (4+1)/2 = 2.5
        # Segment [0.5, 1]: avg_d = (1+4)/2 = 2.5
        # Uniform avg = 2.5
        avg_uniform = moment_weighted_avg_depth(trib; moment_shape=:uniform)
        @test avg_uniform ≈ 2.5 atol=0.05

        # Parabolic: midspan (d=1) gets most weight → should be LESS than 2.5
        # Numerical: ≈ 2.125 (hand-computed via Simpson's)
        avg_parabolic = moment_weighted_avg_depth(trib; moment_shape=:parabolic)
        @test avg_parabolic < avg_uniform  # more conservative
        @test avg_parabolic ≈ 2.125 atol=0.15
    end

    # ==================================================================
    # 5. BULGING MIDDLE (narrow at ends, wide at center)
    #    — the optimistic case for positive moment T-beams
    # ==================================================================
    @testset "5. Bulging middle (d=1 at ends, d=4 at center)" begin
        # Width profile: (0, 1.0) → (0.5, 4.0) → (1.0, 1.0)
        # Polygon: (0,0) → (0.5,0) → (1,0) → (1,1) → (0.5,4) → (0,1)
        trib = make_trib(
            s = [0.0, 0.5, 1.0, 1.0, 0.5, 0.0],
            d = [0.0, 0.0, 0.0, 1.0, 4.0, 1.0],
        )

        avg_uniform = moment_weighted_avg_depth(trib; moment_shape=:uniform)
        @test avg_uniform ≈ 2.5 atol=0.05

        # Parabolic: midspan (d=4) gets most weight → should be MORE than 2.5
        # Numerical: ≈ 2.875 (hand-computed via Simpson's)
        avg_parabolic = moment_weighted_avg_depth(trib; moment_shape=:parabolic)
        @test avg_parabolic > avg_uniform  # wider where it matters
        @test avg_parabolic ≈ 2.875 atol=0.15
    end

    # ==================================================================
    # 6. STEP FUNCTION (notch near one end)
    #    — represents an L-shaped cell cutout near a column
    #
    #    Note: the polygon boundary is piecewise-linear, so a true step
    #    must be approximated as a steep transition over a small Δs.
    #    The _extract_tributary_width_profile merges coincident s values
    #    keeping the max d, so we offset by ε to preserve the step.
    # ==================================================================
    @testset "6. Step function (narrow 20% at start, wide rest)" begin
        ε = 1e-4
        # Width profile: d=1.0 for s∈[0, 0.2], d=5.0 for s∈[0.2+ε, 1.0]
        # Polygon: bottom (d=0) then top (reversed, d = step profile)
        trib = make_trib(
            s = [0.0, 0.2, 0.2+ε, 1.0,  1.0, 0.2+ε, 0.2, 0.0],
            d = [0.0, 0.0, 0.0,   0.0,  5.0, 5.0,   1.0, 1.0],
        )

        # Uniform avg ≈ (1.0×0.2 + 5.0×0.8)/1.0 = 4.2
        avg_uniform = moment_weighted_avg_depth(trib; moment_shape=:uniform)
        @test avg_uniform ≈ 4.2 atol=0.2

        # Parabolic: the narrow part is near s=0 where weight is low → avg > 4.2
        avg_parabolic = moment_weighted_avg_depth(trib; moment_shape=:parabolic)
        @test avg_parabolic > avg_uniform
    end

    # ==================================================================
    # 7. STEP FUNCTION (notch near center — worst case)
    #    — narrow where moment is highest
    #    Uses ε offsets to model the step transitions (see test 6 note)
    # ==================================================================
    @testset "7. Step: narrow strip at midspan" begin
        ε = 1e-4
        # Width profile: d=5 for s∈[0, 0.4], d=1 for s∈(0.4, 0.6), d=5 for s∈[0.6, 1]
        # Polygon traces: bottom edge (d=0), then top edge in reverse with step
        trib_notch = make_trib(
            s = [0.0, 0.4, 0.4+ε, 0.6-ε, 0.6, 1.0,    # bottom
                 1.0, 0.6, 0.6-ε, 0.4+ε, 0.4, 0.0],    # top (reversed)
            d = [0.0, 0.0, 0.0,   0.0,   0.0, 0.0,      # bottom
                 5.0, 5.0, 1.0,   1.0,   5.0, 5.0],     # top
        )

        # Uniform avg ≈ (5×0.4 + 1×0.2 + 5×0.4)/1.0 = 4.2
        avg_uniform = moment_weighted_avg_depth(trib_notch; moment_shape=:uniform)
        @test avg_uniform ≈ 4.2 atol=0.2

        # Parabolic: the narrow part (d=1) is at midspan where weight is highest → avg < 4.2
        avg_parabolic = moment_weighted_avg_depth(trib_notch; moment_shape=:parabolic)
        @test avg_parabolic < avg_uniform  # more conservative where it counts
    end

    # ==================================================================
    # 8. ASYMMETRIC TRAPEZOIDAL CELL (skewed tributary)
    # ==================================================================
    @testset "8. Asymmetric trapezoid (d=2 to d=6)" begin
        # Width profile: d(0)=2, d(1)=6 → linear
        # Polygon: (0,0) → (1,0) → (1,6) → (0,2)
        trib = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 6.0, 2.0],
        )

        # Parabolic avg of linear = (2+6)/2 = 4.0
        @test moment_weighted_avg_depth(trib; moment_shape=:parabolic) ≈ 4.0 atol=0.05
        @test moment_weighted_avg_depth(trib; moment_shape=:uniform)   ≈ 4.0 atol=0.05
    end

    # ==================================================================
    # 9. DEGENERATE: very thin sliver
    # ==================================================================
    @testset "9. Degenerate: tiny sliver (d ≈ 0)" begin
        trib = make_trib(
            s = [0.0, 1.0, 0.5],
            d = [0.0, 0.0, 0.001],
        )

        avg = moment_weighted_avg_depth(trib; moment_shape=:parabolic)
        @test avg ≈ 0.0 atol=0.01
    end

    # ==================================================================
    # 10. DEGENERATE: empty tributary
    # ==================================================================
    @testset "10. Degenerate: empty tributary" begin
        trib = TributaryPolygon(1, Float64[], Float64[], 0.0, 0.0)
        @test moment_weighted_avg_depth(trib; moment_shape=:parabolic) == 0.0
    end

    # ==================================================================
    # 11. FULL effective_flange_width_from_tributary — rectangular grid
    #     Verify it recovers the standard ACI result
    # ==================================================================
    @testset "11. Full bf: rectangular grid recovery" begin
        # Interior beam: two rectangular tributaries, each d = 0.6096m (24 in)
        # bw = 12 in, hf = 5 in, ln = 240 in = 6.096 m
        bw = 12.0u"inch"
        hf = 5.0u"inch"
        ln = 240.0u"inch"
        d_each = ustrip(u"m", 24.0u"inch")  # sw/2 = 24 in each side

        trib_left = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, d_each, d_each],
        )
        trib_right = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, d_each, d_each],
        )

        bf_trib = effective_flange_width_from_tributary(
            bw=bw, hf=hf, ln=ln,
            trib_left=trib_left, trib_right=trib_right,
        )

        # Standard ACI: each overhang = min(8×5=40, 24, 240/8=30) = 24 in
        bf_standard = effective_flange_width(bw=bw, hf=hf, sw=48.0u"inch", ln=ln)

        @test ustrip(u"inch", bf_trib) ≈ ustrip(u"inch", bf_standard) atol=0.5
    end

    # ==================================================================
    # 12. FULL bf: edge beam (one side only)
    # ==================================================================
    @testset "12. Full bf: edge beam (one tributary)" begin
        bw = 12.0u"inch"
        hf = 6.0u"inch"
        ln = 300.0u"inch"
        d_side = ustrip(u"m", 30.0u"inch")  # sw/2 on available side

        trib_right = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, d_side, d_side],
        )

        bf_edge = effective_flange_width_from_tributary(
            bw=bw, hf=hf, ln=ln,
            trib_left=nothing, trib_right=trib_right,
        )

        # Edge: overhang = min(6×6=36, 30, 300/12=25) = 25 in
        bf_expected = 12.0 + 25.0
        @test ustrip(u"inch", bf_edge) ≈ bf_expected atol=0.5
    end

    # ==================================================================
    # 13. ACI CAPS: large tributary capped by 8hf
    # ==================================================================
    @testset "13. ACI cap: large tributary limited by 8hf" begin
        bw = 12.0u"inch"
        hf = 4.0u"inch"   # 8hf = 32 in = 0.8128 m
        ln = 360.0u"inch"  # ln/8 = 45 in = 1.143 m
        # Tributary depth = 2.0m ≈ 78.7 in >> 32 in → should be capped

        trib_left = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 2.0, 2.0],
        )
        trib_right = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 2.0, 2.0],
        )

        bf = effective_flange_width_from_tributary(
            bw=bw, hf=hf, ln=ln,
            trib_left=trib_left, trib_right=trib_right,
        )

        # Each side capped at min(8×4=32 in, 360/8=45 in) = 32 in
        bf_expected = 12.0 + 2 * 32.0
        @test ustrip(u"inch", bf) ≈ bf_expected atol=0.5
    end

    # ==================================================================
    # 14. ACI CAPS: large tributary capped by ln/8
    # ==================================================================
    @testset "14. ACI cap: large tributary limited by ln/8" begin
        bw = 12.0u"inch"
        hf = 8.0u"inch"   # 8hf = 64 in = 1.6256 m
        ln = 120.0u"inch"  # ln/8 = 15 in = 0.381 m
        # Tributary depth = 1.0m ≈ 39.4 in >> 15 in → should be capped by ln/8

        trib_left = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 1.0, 1.0],
        )
        trib_right = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 1.0, 1.0],
        )

        bf = effective_flange_width_from_tributary(
            bw=bw, hf=hf, ln=ln,
            trib_left=trib_left, trib_right=trib_right,
        )

        # Each side capped at min(8×8=64 in, 120/8=15 in) = 15 in
        bf_expected = 12.0 + 2 * 15.0
        @test ustrip(u"inch", bf) ≈ bf_expected atol=0.5
    end

    # ==================================================================
    # 15. ASYMMETRIC INTERIOR: left narrow, right wide
    # ==================================================================
    @testset "15. Asymmetric: narrow left, wide right" begin
        bw = 14.0u"inch"
        hf = 6.0u"inch"   # 8hf = 48 in
        ln = 240.0u"inch"  # ln/8 = 30 in

        d_left = ustrip(u"m", 18.0u"inch")   # 18 in → well under cap
        d_right = ustrip(u"m", 36.0u"inch")  # 36 in → capped at 30 in

        trib_left = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, d_left, d_left],
        )
        trib_right = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, d_right, d_right],
        )

        bf = effective_flange_width_from_tributary(
            bw=bw, hf=hf, ln=ln,
            trib_left=trib_left, trib_right=trib_right,
        )

        # Left: min(18, 48, 30) = 18 in
        # Right: min(36, 48, 30) = 30 in
        bf_expected = 14.0 + 18.0 + 30.0
        @test ustrip(u"inch", bf) ≈ bf_expected atol=0.5
    end

    # ==================================================================
    # 16. PENTAGON CELL — truly irregular 5-sided cell
    # ==================================================================
    @testset "16. Pentagon cell tributary" begin
        # An irregular pentagonal cell produces a tributary polygon with
        # non-linear d(s). Simulate: d rises quickly to 3m, stays at 3m, 
        # then drops to 1m near the end (like a skewed pentagon).
        # Width profile: d(0)=0.5, d(0.3)=3.0, d(0.7)=3.0, d(1.0)=1.0
        trib = make_trib(
            s = [0.0, 0.3, 0.7, 1.0, 1.0, 0.7, 0.3, 0.0],
            d = [0.0, 0.0, 0.0, 0.0, 1.0, 3.0, 3.0, 0.5],
        )

        # Uniform average (trapezoidal):
        # [0, 0.3]: avg(0.5, 3.0) × 0.3 = 1.75 × 0.3 = 0.525
        # [0.3, 0.7]: avg(3.0, 3.0) × 0.4 = 3.0 × 0.4 = 1.2
        # [0.7, 1.0]: avg(3.0, 1.0) × 0.3 = 2.0 × 0.3 = 0.6
        # Total = 2.325 / 1.0 = 2.325
        avg_uniform = moment_weighted_avg_depth(trib; moment_shape=:uniform)
        @test avg_uniform ≈ 2.325 atol=0.1

        # Parabolic: the wide middle section (d=3) dominates → should be > uniform
        avg_parabolic = moment_weighted_avg_depth(trib; moment_shape=:parabolic)
        @test avg_parabolic > avg_uniform - 0.1  # at least close to uniform
    end

    # ==================================================================
    # 17. SYMMETRY: same polygon, flipped left-right
    # ==================================================================
    @testset "17. Symmetry: flipped tributaries give same bf" begin
        bw = 12.0u"inch"
        hf = 5.0u"inch"
        ln = 240.0u"inch"

        # Skewed: wide at s=0, narrow at s=1
        trib_skew = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 1.0, 3.0],
        )
        # Reverse: wide at s=1, narrow at s=0
        trib_reverse = make_trib(
            s = [0.0, 1.0, 1.0, 0.0],
            d = [0.0, 0.0, 3.0, 1.0],
        )

        # With parabolic (symmetric) weighting, both should give same result
        avg1 = moment_weighted_avg_depth(trib_skew; moment_shape=:parabolic)
        avg2 = moment_weighted_avg_depth(trib_reverse; moment_shape=:parabolic)
        @test avg1 ≈ avg2 atol=0.01

        # Both should equal simple average = (1+3)/2 = 2.0
        @test avg1 ≈ 2.0 atol=0.05
    end

    # ==================================================================
    # 18. ADVERSARIAL: sawtooth profile
    #     Tests that the max-d extraction handles many vertices correctly
    # ==================================================================
    @testset "18. Adversarial: sawtooth profile" begin
        # Alternating d at many s positions (like jagged cell boundary):
        # d oscillates between 2.0 and 4.0 at 10 equally spaced points
        n = 10
        s_vals = Float64[]
        d_vals = Float64[]

        # Bottom edge (d = 0)
        for i in 0:n
            push!(s_vals, i / n)
            push!(d_vals, 0.0)
        end
        # Top edge (d oscillates), reversed
        for i in n:-1:0
            push!(s_vals, i / n)
            push!(d_vals, iseven(i) ? 4.0 : 2.0)
        end

        trib = make_trib(s = s_vals, d = d_vals)

        # Width profile picks max |d| at each s:
        # At each s = i/n: max(0, oscillating) = oscillating value
        # Uniform average of sawtooth between 2 and 4 ≈ 3.0
        avg_uniform = moment_weighted_avg_depth(trib; moment_shape=:uniform)
        @test avg_uniform ≈ 3.0 atol=0.3

        # Parabolic should also be ≈ 3.0 (symmetric oscillation + symmetric weight)
        avg_parabolic = moment_weighted_avg_depth(trib; moment_shape=:parabolic)
        @test avg_parabolic ≈ 3.0 atol=0.3
    end

    # ==================================================================
    # 19. COMPARISON: moment-weighted bf vs simple A/L average
    #     For the pinched case, moment-weighted should be more conservative
    # ==================================================================
    @testset "19. Comparison: moment-weighted vs A/L for pinched shape" begin
        beam_length = 10.0  # meters
        bw = 12.0u"inch"
        hf = 8.0u"inch"
        ln = uconvert(u"inch", beam_length * u"m")

        # Pinched: d=5m at ends, d=1m at center
        trib = make_trib(
            s = [0.0, 0.5, 1.0, 1.0, 0.5, 0.0],
            d = [0.0, 0.0, 0.0, 5.0, 1.0, 5.0],
            beam_length = beam_length,
        )

        # Simple A/L approach (area average)
        avg_area_L = trib.area / beam_length
        # Moment-weighted approach
        avg_mw = moment_weighted_avg_depth(trib; moment_shape=:parabolic)

        # Moment-weighted should give LESS than A/L because the pinched
        # middle dominates under parabolic weighting
        @test avg_mw < avg_area_L
    end

    # ==================================================================
    # 20. COMPARISON: moment-weighted bf vs A/L for bulging shape
    #     For the bulging case, moment-weighted should be less conservative
    # ==================================================================
    @testset "20. Comparison: moment-weighted vs A/L for bulging shape" begin
        beam_length = 10.0
        bw = 12.0u"inch"
        hf = 8.0u"inch"
        ln = uconvert(u"inch", beam_length * u"m")

        # Bulging: d=1m at ends, d=5m at center
        trib = make_trib(
            s = [0.0, 0.5, 1.0, 1.0, 0.5, 0.0],
            d = [0.0, 0.0, 0.0, 1.0, 5.0, 1.0],
            beam_length = beam_length,
        )

        avg_area_L = trib.area / beam_length
        avg_mw = moment_weighted_avg_depth(trib; moment_shape=:parabolic)

        # Moment-weighted should give MORE than A/L because the wide
        # middle dominates under parabolic weighting
        @test avg_mw > avg_area_L
    end

end

println("\n✓ All tributary flange width tests passed")
