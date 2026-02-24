# Compute expected deflection values for test assertions
# Usage: julia --project=StructuralSizer scripts/runners/compute_deflection_expected.jl

using StructuralSizer
using Unitful
using Asap: CompoundSection, OffsetSection, depth_from_area

# Build thesis section
function _thesis_section(; fc′_MPa=57.0, dosage=20.0, A_s_mm2=157.0, f_pe_MPa=500.0, d_ps_mm=200.0, λ=:Y)
    fR1 = fc′_dosage2fR1(fc′_MPa, dosage)
    fR3 = fc′_dosage2fR3(fc′_MPa, dosage)
    conc = Concrete(Ec(fc′_MPa * u"MPa"), fc′_MPa * u"MPa", 2400.0u"kg/m^3", 0.2, 0.15;
                    εcu=0.003, λ=1.0, aggregate_type=StructuralSizer.siliceous)
    frc = FiberReinforcedConcrete(conc, dosage, fR1, fR3)
    PixelFrameSection(; λ=λ, L_px=125.0u"mm", t=30.0u"mm", L_c=30.0u"mm",
                      material=frc, A_s=A_s_mm2*u"mm^2", f_pe=f_pe_MPa*u"MPa", d_ps=d_ps_mm*u"mm")
end

s = _thesis_section()
cs = s.section

println("=== Section Properties ===")
println("Area (mm²): ", cs.area)
println("Centroid: ", cs.centroid)
println("Ig (mm⁴): ", cs.Ix)
println("ymax: ", cs.ymax, "  ymin: ", cs.ymin)
println("y_bot = centroid_y - ymin = ", cs.centroid[2] - cs.ymin)

# Cracking moment
println("\n=== Cracking Moment ===")
cr = pf_cracking_moment(s)
println("fr (MPa): ", ustrip(u"MPa", cr.fr))
println("σ_cp (MPa): ", ustrip(u"MPa", cr.σ_cp))
println("Mcr (N·mm): ", ustrip(u"N*mm", cr.Mcr))
println("Mcr (kN·m): ", ustrip(u"kN*m", cr.Mcr))
println("Mdec (N·mm): ", ustrip(u"N*mm", cr.Mdec))
println("Mdec (kN·m): ", ustrip(u"kN*m", cr.Mdec))

# Cracked moment of inertia
println("\n=== Cracked Moment of Inertia ===")
Icr = pf_cracked_moment_of_inertia(s)
println("Icr (mm⁴): ", Icr)
println("Ig (mm⁴): ", cs.Ix)
println("Icr/Ig ratio: ", Icr / cs.Ix)
println("Icr < Ig: ", Icr < cs.Ix)

# Effective Ie for various moments
println("\n=== Effective Ie ===")
for factor in [0.5, 1.0, 2.0, 5.0, 10.0]
    Ma = factor * cr.Mcr
    ie = pf_effective_Ie(s, Ma)
    Ie_val = ustrip(u"mm^4", ie.Ie)
    println("Ma = $(factor)×Mcr: Ie=$(round(Ie_val, digits=1)), regime=$(ie.regime), Ie/Ig=$(round(Ie_val/cs.Ix, digits=4))")
end

# Deflection for a simply supported beam
println("\n=== Deflection (6m span, 5 kN/m) ===")
L = 6.0u"m"
w = 5.0u"kN/m"
result = pf_deflection(s, L, w)
println("Δ (mm): ", ustrip(u"mm", result.Δ))
println("L/Δ: ", result.L_over_Δ)
println("Ma (kN·m): ", ustrip(u"kN*m", result.Ma))
println("Regime: ", result.regime)

# Full serviceability check
println("\n=== Full Serviceability Check ===")
w_dead = 3.0u"kN/m"
w_live = 2.0u"kN/m"
check = pf_check_deflection(s, L, w_dead, w_live)
println("Δ_D (mm): ", ustrip(u"mm", check.Δ_D))
println("Δ_DL (mm): ", ustrip(u"mm", check.Δ_DL))
println("Δ_LL (mm): ", ustrip(u"mm", check.Δ_LL))
println("Δ_LT (mm): ", ustrip(u"mm", check.Δ_LT))
println("Δ_total (mm): ", ustrip(u"mm", check.Δ_total))
println("Limit LL (mm): ", check.limit_ll_mm)
println("Limit total (mm): ", check.limit_total_mm)
println("Passes LL: ", check.passes_ll)
println("Passes total: ", check.passes_total)
println("Passes: ", check.passes)
println("Regime D: ", check.regime_D)
println("Regime DL: ", check.regime_DL)

# Deflection for different support conditions
println("\n=== Support Condition Comparison (2m span, 3+2 kN/m) ===")
L2 = 2.0u"m"
for support in [:simply_supported, :cantilever, :fixed_fixed]
    check2 = pf_check_deflection(s, L2, w_dead, w_live; support)
    println("$support: Δ_DL=$(round(ustrip(u"mm", check2.Δ_DL), digits=4)) mm")
end

# Verify Branson formula numerically
println("\n=== Branson Formula Verification ===")
Ma_test = 3.0 * cr.Mcr
ie_test = pf_effective_Ie(s, Ma_test)
Mcr_Nmm = ustrip(u"N*mm", cr.Mcr)
Mdec_Nmm = ustrip(u"N*mm", cr.Mdec)
Ma_Nmm = ustrip(u"N*mm", Ma_test)
k = (Mcr_Nmm - Mdec_Nmm) / (Ma_Nmm - Mdec_Nmm)
k3 = k^3
Ie_expected = k3 * cs.Ix + (1 - k3) * ie_test.Icr
println("k = ", k)
println("k³ = ", k3)
println("Ie expected = ", Ie_expected)
println("Ie actual = ", ustrip(u"mm^4", ie_test.Ie))
println("Match: ", isapprox(Ie_expected, ustrip(u"mm^4", ie_test.Ie); rtol=1e-6))

# Long-term deflection factor
println("\n=== Long-term Factor ===")
println("ξ = 2.0 (5+ years)")
println("Δ_LT = ξ × Δ_D = 2.0 × $(round(ustrip(u"mm", check.Δ_D), digits=4)) = $(round(ustrip(u"mm", check.Δ_LT), digits=4))")
println("Δ_total = Δ_LT + Δ_LL = $(round(ustrip(u"mm", check.Δ_LT), digits=4)) + $(round(ustrip(u"mm", check.Δ_LL), digits=4)) = $(round(ustrip(u"mm", check.Δ_total), digits=4))")
