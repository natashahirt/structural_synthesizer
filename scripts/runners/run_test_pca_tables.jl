#!/usr/bin/env julia
# Quick verification of PCA table digitization and interpolation.
# Run: julia --project=. scripts/runners/run_test_pca_tables.jl

using StructuralSizer
using Unitful

println("=" ^ 60)
println("PCA Table A1 — Spot Checks (Flat Plate Slab-Beam)")
println("=" ^ 60)

# Exact grid points from Table A1 (C_F1 = C_N1; C_F2 = C_N2)
test_cases_a1 = [
    # (c1/l1, c2/l2) => expected (k, COF, m)
    ((0.00, 0.00), (4.00, 0.50, 0.0833)),
    ((0.10, 0.10), (4.18, 0.51, 0.0847)),
    ((0.10, 0.40), (4.70, 0.55, 0.0882)),
    ((0.20, 0.20), (4.72, 0.54, 0.0880)),
    ((0.30, 0.30), (5.69, 0.59, 0.0923)),
    ((0.40, 0.40), (7.37, 0.64, 0.0971)),
    ((0.40, 0.00), (4.00, 0.50, 0.0833)),
    ((0.20, 0.40), (5.51, 0.58, 0.0921)),
]

all_pass = true
for ((c1l1, c2l2), (exp_k, exp_COF, exp_m)) in test_cases_a1
    global all_pass
    result = StructuralSizer._interp_table_a1(c1l1, c2l2)
    k_ok   = abs(result.k - exp_k) < 0.005
    COF_ok = abs(result.COF - exp_COF) < 0.005
    m_ok   = abs(result.m - exp_m) < 0.00005
    pass   = k_ok && COF_ok && m_ok
    all_pass &= pass
    status = pass ? "✓" : "✗"
    println("  $status  c1/l1=$c1l1, c2/l2=$c2l2 → k=$(round(result.k, digits=3)), COF=$(round(result.COF, digits=3)), m=$(round(result.m, digits=5))")
    if !pass
        println("       Expected: k=$exp_k, COF=$exp_COF, m=$exp_m")
    end
end

println()
println("=" ^ 60)
println("PCA Table A1 — Interpolation Check (between grid points)")
println("=" ^ 60)

# Test interpolation at c1/l1=0.15, c2/l2=0.15 (midpoint of 0.10 and 0.20)
result = StructuralSizer._interp_table_a1(0.15, 0.15)
# Should be average of (0.10,0.10)=(4.18,0.51,0.0847) and (0.20,0.20)=(4.72,0.54,0.0880)
# plus cross terms (0.10,0.20)=(4.36,0.52,0.0860) and (0.20,0.10)=(4.35,0.52,0.0857)
# Bilinear: avg of all four with t1=t2=0.5
expected_k = 0.25*(4.18 + 4.36 + 4.35 + 4.72)
expected_COF = 0.25*(0.51 + 0.52 + 0.52 + 0.54)
expected_m = 0.25*(0.0847 + 0.0860 + 0.0857 + 0.0880)
println("  c1/l1=0.15, c2/l2=0.15:")
println("    Got:      k=$(round(result.k, digits=3)), COF=$(round(result.COF, digits=3)), m=$(round(result.m, digits=5))")
println("    Expected: k=$(round(expected_k, digits=3)), COF=$(round(expected_COF, digits=3)), m=$(round(expected_m, digits=5))")
interp_ok = abs(result.k - expected_k) < 0.01 && abs(result.COF - expected_COF) < 0.01 && abs(result.m - expected_m) < 0.0001
global all_pass &= interp_ok
println("    $(interp_ok ? "✓" : "✗") Interpolation correct")

println()
println("=" ^ 60)
println("PCA Table A7 — Spot Checks (Column Stiffness)")
println("=" ^ 60)

test_cases_a7 = [
    # (ta/tb, H/Hc) => expected (k, COF)
    ((0.00, 1.05), (4.20, 0.57)),
    ((0.00, 1.10), (4.40, 0.65)),
    ((0.00, 1.50), (6.00, 1.25)),
    ((1.00, 1.05), (4.52, 0.54)),
    ((1.00, 1.20), (6.38, 0.62)),
    ((10.00, 1.50), (17.90, 0.44)),
    ((0.40, 1.30), (6.65, 0.79)),
    ((2.00, 1.25), (7.92, 0.58)),
]

for ((ta_tb, H_Hc), (exp_k, exp_COF)) in test_cases_a7
    global all_pass
    result = StructuralSizer._interp_table_a7(ta_tb, H_Hc)
    k_ok   = abs(result.k - exp_k) < 0.005
    COF_ok = abs(result.COF - exp_COF) < 0.005
    pass   = k_ok && COF_ok
    all_pass &= pass
    status = pass ? "✓" : "✗"
    println("  $status  ta/tb=$ta_tb, H/Hc=$H_Hc → k=$(round(result.k, digits=2)), COF=$(round(result.COF, digits=2))")
    if !pass
        println("       Expected: k=$exp_k, COF=$exp_COF")
    end
end

println()
println("=" ^ 60)
println("Public API — pca_slab_beam_factors / pca_column_factors")
println("=" ^ 60)

# Test with Unitful quantities
# 20" column, 20ft span → c1/l1 = 20/(20*12) = 0.0833
# 20" column, 25ft transverse → c2/l2 = 20/(25*12) = 0.0667
result = pca_slab_beam_factors(20.0u"inch", 20.0u"ft", 20.0u"inch", 25.0u"ft")
println("  Slab-beam: 20\" col, 20' span, 25' transverse")
println("    c1/l1 = $(round(20/(20*12), digits=4)), c2/l2 = $(round(20/(25*12), digits=4))")
println("    k=$(round(result.k, digits=3)), COF=$(round(result.COF, digits=3)), m=$(round(result.m, digits=5))")
println("    (vs old hardcoded: k=4.127, COF=0.507, m=0.08429)")

# Column factors: 12ft story height, 8" slab → H/Hc = 144/(144-8) = 1.059
result_col = pca_column_factors(12.0u"ft", 8.0u"inch")
println()
println("  Column: 12' story, 8\" slab (flat plate, no capitals)")
println("    H/Hc = $(round(144/(144-8), digits=3))")
println("    k=$(round(result_col.k, digits=3)), COF=$(round(result_col.COF, digits=3))")
println("    (vs old hardcoded: k=4.74)")

println()
println("=" ^ 60)
if all_pass
    println("ALL SPOT CHECKS PASSED ✓")
else
    println("SOME CHECKS FAILED ✗")
end
println("=" ^ 60)
