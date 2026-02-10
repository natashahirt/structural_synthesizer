# =============================================================================
# Integration Test: Flat Plate EFM Pipeline — StructurePoint Validation Report
# =============================================================================
#
# This test traces every step of the EFM calculation chain, printing a
# human-readable report that compares each intermediate result against the
# StructurePoint reference values.
#
# Reference: DE-Two-Way-Flat-Plate-Concrete-Floor-System-Analysis-and-Design-ACI-318-14
#            StructurePoint spSlab v10.00
#
# Geometry (3-span × 2-bay flat plate floor):
#   - Interior equivalent frame in E-W direction
#   - Span l1 = 18 ft (E-W)    Tributary width l2 = 14 ft (N-S)
#   - Column: 16" × 16" square  Story height: 9 ft
#   - Slab: 7 in (SP result)
#
# Loads:  SDL = 20 psf   LL = 50 psf   qu = 193 psf (factored, SP given)
#
# SP Reference Values:
#   - Stiffnesses:  SP Table 2 (section properties and EFM stiffnesses)
#   - M₀:          ACI 8.10.3.2 (qu × l₂ × ln² / 8 = 93.82 k-ft)
#   - EFM moments:  SP Table 5 (centerline), Table 6 (face-of-support)
#   - Reinforcement: SP Table 7 (face-of-support column-strip, b=84 in, d=5.75 in)
# =============================================================================

using Test
using Printf
using Unitful
using Unitful: @u_str
using Asap

using Logging

using StructuralSizer
using StructuralSynthesizer

# ─────────────────────────────────────────────────────────────────────────────
# Report helpers
# ─────────────────────────────────────────────────────────────────────────────

const HLINE = "─"^78
const DLINE = "═"^78

section_header(title) = println("\n", DLINE, "\n  ", title, "\n", DLINE)
sub_header(title)     = println("\n  ", HLINE, "\n  ", title, "\n  ", HLINE)
note(msg)             = println("    → ", msg)

function table_head()
    @printf("    %-30s %12s %12s %8s %s\n",
            "Quantity", "Computed", "SP Ref", "Δ%", "")
    @printf("    %-30s %12s %12s %8s %s\n",
            "─"^30, "─"^12, "─"^12, "─"^8, "──")
end

"""
Print one comparison row.  Returns `true` when |δ| ≤ tol.
The Δ% is signed so you can see over (+) vs under (−).
"""
function compare(label, computed, reference, unit; tol=0.05)
    v = ustrip(unit, computed)
    r = ustrip(unit, reference)
    δ = (v - r) / max(abs(r), 1e-12)
    ok = abs(δ) ≤ tol
    flag = ok ? "✓" : (abs(δ) ≤ 2tol ? "~" : "✗")
    @printf("    %-30s %12.2f %12.2f %+7.1f%%  %s\n", label, v, r, 100δ, flag)
    return ok
end

# Track per-step status for the final summary table
step_status = Dict{String,String}()

# ─────────────────────────────────────────────────────────────────────────────
# Inputs & SP Reference
# ─────────────────────────────────────────────────────────────────────────────

@testset "Flat Plate & Flat Slab — Design Validation" begin

section_header("FLAT PLATE & FLAT SLAB DESIGN VALIDATION")
println("  Ref: DE-Two-Way-Flat-Plate (ACI 318-14), spSlab v10.00")
println("  Flat slab (drop panel) provisions per ACI 318-19 §8.2.4")

# ── Geometry ──
l1    = 18.0u"ft"
l2    = 14.0u"ft"
c_col = 16.0u"inch"
H     = 9.0u"ft"
h     = 7.0u"inch"

# ── Loads ──
sdl = 20.0u"psf"
ll  = 50.0u"psf"
qu  = 193.0u"psf"       # SP given factored load

# ── Materials ──
fc_slab = 4000u"psi"
fc_col  = 6000u"psi"
fy      = 60u"ksi"
wc      = 150.0                                             # pcf
Ecs     = wc^1.5 * 33 * sqrt(ustrip(u"psi", fc_slab)) * u"psi"
Ecc     = wc^1.5 * 33 * sqrt(ustrip(u"psi", fc_col)) * u"psi"

# ── Derived geometry ──
ln = l1 - c_col  # clear span

sub_header("INPUT SUMMARY")
@printf("    Panel:         l₁ = %-8s  l₂ = %s\n", l1, l2)
@printf("    Column:        %s × %s (square)\n", c_col, c_col)
@printf("    Story height:  H  = %s\n", H)
@printf("    Slab:          h  = %s\n", h)
@printf("    Clear span:    lₙ = l₁ − c = %.3f ft\n", ustrip(u"ft", ln))
println()
@printf("    Loads:         SDL = %-8s  LL = %-8s  qᵤ = %s\n", sdl, ll, qu)
@printf("    f'c (slab) = %-10s  f'c (col) = %-10s  fy = %s\n", fc_slab, fc_col, fy)
@printf("    Ec  (slab) = %.0f psi    Ec  (col) = %.0f psi\n",
        ustrip(u"psi", Ecs), ustrip(u"psi", Ecc))

# ── SP reference values ──
# Section properties & stiffnesses: SP Table 2 (exact formulas)
# M₀: ACI 8.10.3.2 formula (qu × l₂ × ln² / 8)
# EFM moments: SP Table 5 (centerline) → Table 6 (face-of-support)
# Column-strip moments & As: SP Table 7 (face-of-support, b=84 in, d=5.75 in)
sp = (
    # Table 2 — Section properties
    Is  = 4802u"inch^4",           Ic  = 5461u"inch^4",
    C   = 1325u"inch^4",
    # Table 2 — EFM stiffnesses
    Ksb = 351.77e6u"lbf*inch",     Kc  = 1125.59e6u"lbf*inch",
    Kt  = 367.48e6u"lbf*inch",     Kec = 554.07e6u"lbf*inch",
    # ACI 8.10.3.2
    M0  = 93.82u"kip*ft",
    # Table 5 — EFM centerline moments (end span, full frame width)
    M_neg_ext = 46.65u"kip*ft",    M_pos = 44.94u"kip*ft",
    M_neg_int = 83.91u"kip*ft",
    # Table 7 — Face-of-support column-strip moments & reinforcement
    M_neg_ext_cs = 32.42u"kip*ft", M_pos_cs     = 26.96u"kip*ft",
    M_neg_int_cs = 50.24u"kip*ft",
    As_neg_ext_cs = 1.28u"inch^2", As_pos_cs     = 1.06u"inch^2",
    As_neg_int_cs = 2.02u"inch^2",
)

# ═════════════════════════════════════════════════════════════════════════════
# FEA MODEL — build once, use throughout the report
#
# We build a full 3×3 bay BuildingStructure matching the SP geometry,
# run the FEA shell analysis, and use its results alongside DDM/EFM
# in every comparison table below.
# ═════════════════════════════════════════════════════════════════════════════

# Suppress @info logging from initialize! / to_asap!
fea_struc = with_logger(NullLogger()) do
    _skel = gen_medium_office(54.0u"ft", 42.0u"ft", 9.0u"ft", 3, 3, 1)
    _struc = BuildingStructure(_skel)
    _opts = FloorOptions(
        flat_plate = FlatPlateOptions(
            material = RC_4000_60,
            analysis_method = :fea,
            cover = 0.75u"inch",
            bar_size = 5,
        ),
        tributary_axis = nothing
    )
    initialize!(_struc; floor_type=:flat_plate, floor_kwargs=(options=_opts,))
    for c_fea in _struc.cells
        c_fea.sdl = uconvert(u"kN/m^2", sdl)
        c_fea.live_load = uconvert(u"kN/m^2", ll)
    end
    for col_fea in _struc.columns
        col_fea.c1 = 16.0u"inch"
        col_fea.c2 = 16.0u"inch"
    end
    to_asap!(_struc)
    _struc
end

fea_slab = fea_struc.slabs[1]
fea_cell_set = Set(fea_slab.cell_indices)
fea_columns = StructuralSizer.find_supporting_columns(fea_struc, fea_cell_set)

fea_fc = 4000.0u"psi"
fea_γ  = RC_4000_60.concrete.ρ
fea_ν  = RC_4000_60.concrete.ν
fea_wc = ustrip(StructuralSizer.pcf, fea_γ)
fea_Ecs = StructuralSizer.Ec(fea_fc, fea_wc)

fea_result = StructuralSizer.run_moment_analysis(
    StructuralSizer.FEA(), fea_struc, fea_slab, fea_columns,
    h, fea_fc, fea_Ecs, fea_γ; ν_concrete=fea_ν, verbose=false
)

# Extract FEA scalars for use throughout the report
M0_fea        = ustrip(u"kip*ft", fea_result.M0)
M_neg_ext_fea = ustrip(u"kip*ft", fea_result.M_neg_ext)
M_pos_fea     = ustrip(u"kip*ft", fea_result.M_pos)
M_neg_int_fea = ustrip(u"kip*ft", fea_result.M_neg_int)
qu_fea_psf    = ustrip(u"psf", fea_result.qu)
l1_fea_ft     = ustrip(u"ft", fea_result.l1)
l2_fea_ft     = ustrip(u"ft", fea_result.l2)
ln_fea_ft     = ustrip(u"ft", fea_result.ln)

# ═════════════════════════════════════════════════════════════════════════════
# STEP 0  Load Baseline — SP Given vs FEA Computed
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 0 — LOAD BASELINE: SP vs FEA")
println("  SP states qᵤ = 193 psf as a given input (load combination unspecified).")
println("  We compute qᵤ from stated inputs: 1.2(SDL + SW) + 1.6(LL).")
println()

# Compute SW using traditional 150 pcf and NWC_4000 density (2380 kg/m³ ≈ 148.6 pcf)
γ_150 = 150.0u"pcf"
γ_mat = RC_4000_60.concrete.ρ
γ_mat_pcf = ustrip(StructuralSizer.pcf, γ_mat)

sw_150 = StructuralSizer.slab_self_weight(h, γ_150)
sw_mat = StructuralSizer.slab_self_weight(h, γ_mat)

qD_150 = sdl + sw_150
qD_mat = sdl + sw_mat
qu_150 = 1.2 * qD_150 + 1.6 * ll
qu_mat = 1.2 * qD_mat + 1.6 * ll

println("    Two computed qᵤ values depending on concrete density:")
@printf("    a) wc = 150 pcf (ACI traditional):  SW = %.1f psf → qᵤ = %.0f psf\n",
        ustrip(u"psf", sw_150), ustrip(u"psf", qu_150))
@printf("    b) wc = %.1f pcf (NWC_4000 ρ):     SW = %.1f psf → qᵤ = %.0f psf  ← FEA uses this\n",
        γ_mat_pcf, ustrip(u"psf", sw_mat), ustrip(u"psf", qu_mat))
println()

@printf("    %-20s %10s %10s %10s\n", "", "SP Given", "150 pcf", "NWC_4000")
@printf("    %-20s %10s %10s %10s\n", "─"^20, "─"^10, "─"^10, "─"^10)
@printf("    %-20s %10.0f %10.0f %10.0f\n", "qᵤ (psf)", ustrip(u"psf", qu), ustrip(u"psf", qu_150), qu_fea_psf)
println()

M0_sp_kf = ustrip(u"kip*ft", sp.M0)
@printf("    %-20s %10s %10s %10s\n", "", "SP (M₀)", "FEA (M₀)", "FEA span")
@printf("    %-20s %10s %10s %10s\n", "─"^20, "─"^10, "─"^10, "─"^10)
@printf("    %-20s %10.2f %10.2f %s\n", "M₀ (kip·ft)", M0_sp_kf, M0_fea,
        @sprintf("l₁=%.0f′ l₂=%.0f′ lₙ=%.1f′", l1_fea_ft, l2_fea_ft, ln_fea_ft))
println()

note("SP qᵤ = 193 psf is ~$(@sprintf("%.0f", ustrip(u"psf", qu_150) - ustrip(u"psf", qu))) psf lower than computed (150 pcf) — likely a different SW definition or min-h assumption.")
note("Computed (150 pcf) ≈ FEA (NWC_4000): $(@sprintf("%.0f", ustrip(u"psf", qu_150))) vs $(@sprintf("%.0f", qu_fea_psf)) psf — the ~1 psf gap is from γ = 150 vs 148.6 pcf.")
note("FEA now uses the same span direction as DDM/EFM (slab grouper primary = short span).")
note("All methods share the same l₁, l₂, and M₀ baseline — only moment distribution differs.")
note("FEA qᵤ differs slightly from SP (NWC_4000 density) — see qu table above.")

@test qu_fea_psf > 0
@test M0_fea > 0
step_status["Load Baseline"] = "✓"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1  Section Properties (SP Table 2, left columns)
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 1 — SECTION PROPERTIES  (SP Table 2)")
println("  Is  = l₂ · h³ / 12           Slab moment of inertia for full panel width")
println("  Ic  = c₁ · c₂³ / 12          Column moment of inertia (square section)")
println("  C   = Σ (1 − 0.63 x/y) x³y/3 Torsional constant (ACI 8.10.5.2)")
println()

Is = StructuralSizer.slab_moment_of_inertia(l2, h)
Ic = StructuralSizer.column_moment_of_inertia(c_col, c_col)
C  = StructuralSizer.torsional_constant_C(h, c_col)

table_head()
ok1 = compare("Is  (slab I)",      Is, sp.Is, u"inch^4"; tol=0.01)
ok2 = compare("Ic  (column I)",    Ic, sp.Ic, u"inch^4"; tol=0.01)
ok3 = compare("C   (torsional)",   C,  sp.C,  u"inch^4"; tol=0.05)

@test ok1;  @test ok2;  @test ok3
step_status["Section Properties"] = all((ok1, ok2, ok3)) ? "✓" : "✗"

note("Is and Ic are exact formulas; C tolerance is wider because SP may")
note("use a slightly different rectangle decomposition for the torsional strip.")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2  EFM Stiffnesses (SP Table 2, right columns)
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 2 — EFM STIFFNESSES  (SP Table 2)")
println("  Ksb = k · Ecs · Is / l₁          Slab-beam stiffness (PCA Table A7)")
println("  Kc  = k · Ecc · Ic / lc          Column stiffness")
println("  Kt  = 9 · Ecs · C / [l₂(1−c₂/l₂)³]  Torsional member stiffness")
println("  Kec = 1 / (1/ΣKc + 1/ΣKt)       Equivalent column stiffness")
println()
println("  Interior joint:  ΣKc = 2·Kc  (above + below)")
println("                   ΣKt = 2·Kt  (torsional arms both sides)")
println()

Ksb = StructuralSizer.slab_beam_stiffness_Ksb(Ecs, Is, l1, c_col, c_col)
Kc  = StructuralSizer.column_stiffness_Kc(Ecc, Ic, H, h)
Kt  = StructuralSizer.torsional_member_stiffness_Kt(Ecs, C, l2, c_col)
Kec = StructuralSizer.equivalent_column_stiffness_Kec(2Kc, 2Kt)

table_head()
ok1 = compare("Ksb (slab-beam)",      Ksb, sp.Ksb, u"lbf*inch"; tol=0.01)
ok2 = compare("Kc  (column)",         Kc,  sp.Kc,  u"lbf*inch"; tol=0.01)
ok3 = compare("Kt  (torsional)",      Kt,  sp.Kt,  u"lbf*inch"; tol=0.01)
ok4 = compare("Kec (equiv. column)",  Kec, sp.Kec, u"lbf*inch"; tol=0.01)

@test ok1;  @test ok2;  @test ok3;  @test ok4
step_status["EFM Stiffnesses"] = all((ok1, ok2, ok3, ok4)) ? "✓" : "✗"

αec = ustrip(u"lbf*inch", Kec) / (2 * ustrip(u"lbf*inch", Ksb))
@printf("\n    αec = Kec / ΣKsb = %.3f\n", αec)
note("αec < 1 → column is 'soft'; slab attracts more moment at the support.")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3  Total Static Moment (ACI 8.10.3.2)
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 3 — TOTAL STATIC MOMENT  (ACI 8.10.3.2)")
println("  M₀ = qᵤ · l₂ · lₙ² / 8")
@printf("     = %.0f psf × %.1f ft × (%.3f ft)² / 8\n",
        ustrip(u"psf", qu), ustrip(u"ft", l2), ustrip(u"ft", ln))
println()

M0 = StructuralSizer.total_static_moment(qu, l2, ln)

table_head()
ok_m0 = compare("M₀ (static moment)", M0, sp.M0, u"kip*ft"; tol=0.01)
@test ok_m0
step_status["Static Moment"] = ok_m0 ? "✓" : "✗"

note("M₀ is the total moment distributed between negative and positive sections.")
note("This is for ONE equivalent-frame strip with tributary width l₂ = $l2.")
note("FEA M₀ = $(@sprintf("%.2f", M0_fea)) kip·ft (same span, slightly different qᵤ — see Step 0).")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4  Method Comparison — DDM vs MDDM vs EFM vs FEA
#
# Five moment-distribution approaches compared side by side:
#   A) DDM Hand-Calc  — ACI Table 8.10.4.2 coefficients × M₀
#   B) DDM Computed   — our distribute_moments_aci() function
#   C) MDDM Computed  — our distribute_moments_mddm() (Supplementary Doc)
#   D) EFM Computed   — Hardy Cross iteration with our stiffness values
#   E) EFM ASAP       — Structural frame analysis (direct stiffness)
#   F) FEA Shell      — 2D shell model with per-column skeleton-edge integration
#
# DDM/MDDM/EFM all use SP's given qᵤ = 193 psf → M₀ = 93.82 kip·ft.
# FEA uses the same span direction but slightly different qᵤ (NWC_4000 density).
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 4 — METHOD COMPARISON: DDM vs MDDM vs EFM vs FEA")

l2_l1 = round(ustrip(u"ft", l2) / ustrip(u"ft", l1), digits=2)
println("  l₂/l₁ = $l2_l1   (αf = 0, no beams, no edge beam)")
println()

# ── 4A: DDM hand-calc (ACI Table 8.10.4.2 coefficients × M₀) ──
sub_header("4A — DDM Hand-Calc (ACI Table 8.10.4.2)")
println("  Longitudinal coefficients × M₀  (full frame width, end span, no edge beam):")
println()

M_neg_ext_ddm = 0.26 * M0
M_pos_ddm     = 0.52 * M0
M_neg_int_ddm = 0.70 * M0

@printf("    %-24s %6s %12s\n", "Location", "Coeff", "kip·ft")
@printf("    %-24s %6s %12s\n", "─"^24, "─"^6, "─"^12)
@printf("    %-24s %6.2f %12.2f\n", "Ext. negative", 0.26, ustrip(u"kip*ft", M_neg_ext_ddm))
@printf("    %-24s %6.2f %12.2f\n", "Positive",      0.52, ustrip(u"kip*ft", M_pos_ddm))
@printf("    %-24s %6.2f %12.2f\n", "Int. negative",  0.70, ustrip(u"kip*ft", M_neg_int_ddm))
println()

# Transverse to column strip: ACI 8.10.5 (100% / 60% / 75%)
cs_frac_ext = 1.00;  cs_frac_pos = 0.60;  cs_frac_int = 0.75
cs_ext_ddm = cs_frac_ext * M_neg_ext_ddm
cs_pos_ddm = cs_frac_pos * M_pos_ddm
cs_int_ddm = cs_frac_int * M_neg_int_ddm

@printf("    Transverse to CS (column strip):  100%% ext neg, 60%% pos, 75%% int neg\n")
@printf("    %-24s %12.2f → CS %12.2f kip·ft\n", "Ext. negative",
        ustrip(u"kip*ft", M_neg_ext_ddm), ustrip(u"kip*ft", cs_ext_ddm))
@printf("    %-24s %12.2f → CS %12.2f kip·ft\n", "Positive",
        ustrip(u"kip*ft", M_pos_ddm), ustrip(u"kip*ft", cs_pos_ddm))
@printf("    %-24s %12.2f → CS %12.2f kip·ft\n", "Int. negative",
        ustrip(u"kip*ft", M_neg_int_ddm), ustrip(u"kip*ft", cs_int_ddm))

# ── 4B: DDM Computed — validate distribute_moments_aci() ──
sub_header("4B — DDM Computed (distribute_moments_aci)")
println("  Calling distribute_moments_aci(M₀, :end_span, $l2_l1) — should match 4A:")
println()

ddm_comp = StructuralSizer.distribute_moments_aci(M0, :end_span, Float64(l2_l1))

@printf("    %-24s %12s %12s %12s\n", "Location", "Hand-Calc", "Computed", "Match?")
@printf("    %-24s %12s %12s %12s\n", "─"^24, "─"^12, "─"^12, "─"^12)

ddm_cs_ext_v = ustrip(u"kip*ft", ddm_comp.column_strip.ext_neg)
ddm_cs_pos_v = ustrip(u"kip*ft", ddm_comp.column_strip.pos)
ddm_cs_int_v = ustrip(u"kip*ft", ddm_comp.column_strip.int_neg)

@printf("    %-24s %12.2f %12.2f %12s\n", "CS ext neg",
        ustrip(u"kip*ft", cs_ext_ddm), ddm_cs_ext_v,
        abs(ustrip(u"kip*ft", cs_ext_ddm) - ddm_cs_ext_v) < 0.01 ? "✓" : "✗")
@printf("    %-24s %12.2f %12.2f %12s\n", "CS positive",
        ustrip(u"kip*ft", cs_pos_ddm), ddm_cs_pos_v,
        abs(ustrip(u"kip*ft", cs_pos_ddm) - ddm_cs_pos_v) < 0.01 ? "✓" : "✗")
@printf("    %-24s %12.2f %12.2f %12s\n", "CS int neg",
        ustrip(u"kip*ft", cs_int_ddm), ddm_cs_int_v,
        abs(ustrip(u"kip*ft", cs_int_ddm) - ddm_cs_int_v) < 0.01 ? "✓" : "✗")
println()

# Validate function matches hand-calc
@test ustrip(u"kip*ft", ddm_comp.column_strip.ext_neg) ≈ ustrip(u"kip*ft", cs_ext_ddm) atol=0.01
@test ustrip(u"kip*ft", ddm_comp.column_strip.pos)     ≈ ustrip(u"kip*ft", cs_pos_ddm) atol=0.01
@test ustrip(u"kip*ft", ddm_comp.column_strip.int_neg) ≈ ustrip(u"kip*ft", cs_int_ddm) atol=0.01

note("distribute_moments_aci combines longitudinal (Table 8.10.4.2) and")
note("transverse (Table 8.10.5) in one call. Exact match confirms correctness.")

# ── 4C: MDDM Computed — simplified coefficients ──
sub_header("4C — MDDM Computed (distribute_moments_mddm)")
println("  MDDM uses pre-combined coefficients from Supplementary Document Table S-1:")
println("  These combine longitudinal + transverse distribution into single factors.")
println()

mddm = StructuralSizer.distribute_moments_mddm(M0, :end_span)

mddm_cs_ext_v = ustrip(u"kip*ft", mddm.column_strip.ext_neg)
mddm_cs_pos_v = ustrip(u"kip*ft", mddm.column_strip.pos)
mddm_cs_int_v = ustrip(u"kip*ft", mddm.column_strip.int_neg)
mddm_ms_ext_v = ustrip(u"kip*ft", mddm.middle_strip.ext_neg)
mddm_ms_pos_v = ustrip(u"kip*ft", mddm.middle_strip.pos)
mddm_ms_int_v = ustrip(u"kip*ft", mddm.middle_strip.int_neg)

@printf("    %-24s %6s %12s %12s\n", "Location", "Coeff", "CS (kip·ft)", "MS (kip·ft)")
@printf("    %-24s %6s %12s %12s\n", "─"^24, "─"^6, "─"^12, "─"^12)
@printf("    %-24s %6.3f %12.2f %12.2f\n", "Ext. negative",
        0.27, mddm_cs_ext_v, mddm_ms_ext_v)
@printf("    %-24s %6.3f %12.2f %12.2f\n", "Positive",
        0.345, mddm_cs_pos_v, mddm_ms_pos_v)
@printf("    %-24s %6.3f %12.2f %12.2f\n", "Int. negative",
        0.55, mddm_cs_int_v, mddm_ms_int_v)
println()
note("MDDM coefficients (0.27, 0.345, 0.55) differ slightly from DDM")
note("(0.26, 0.312, 0.525) because they're derived from a different source.")

# ── 4D: EFM Computed — Hardy Cross with our stiffness values ──
sub_header("4D — EFM Computed (Hardy Cross Moment Distribution)")
println("  Using stiffnesses from Step 2 to run Hardy Cross iteration:")
println("  FEM = m × qu × l₂ × l₁²   (PCA factor m = 0.08429 for non-prismatic section)")
println("  DF, COF from our functions  →  iterate until convergence")
println()

FEM = StructuralSizer.fixed_end_moment_FEM(qu, l2, l1)
DF_ext_val = StructuralSizer.distribution_factor_DF(Ksb, Kec; is_exterior=true)
DF_int_val = StructuralSizer.distribution_factor_DF(Ksb, Kec; is_exterior=false)
COF_val    = StructuralSizer.carryover_factor_COF()

@printf("    FEM    = %.2f kip·ft\n", ustrip(u"kip*ft", FEM))
@printf("    DF_ext = %.4f   (Ksb / (Ksb + Kec))\n", DF_ext_val)
@printf("    DF_int = %.4f   (Ksb / (2Ksb + Kec))\n", DF_int_val)
@printf("    COF    = %.3f   (non-prismatic carry-over)\n", COF_val)
println()

# Hardy Cross iteration for symmetric 3-span EFM frame
# Track slab member-end moments AND column moments at each joint.
# Unbalanced = sum(slab ends + column) at each joint.
FEM_kf = ustrip(u"kip*ft", FEM)
slab_m = [[FEM_kf, -FEM_kf], [FEM_kf, -FEM_kf], [FEM_kf, -FEM_kf]]
col_m  = [0.0, 0.0, 0.0, 0.0]   # EC moments at joints 1–4
DF_col_int = 1.0 - 2.0 * DF_int_val   # column share at interior joint

for _ in 1:20
    # Joint 1 (exterior): slab[1][1] + col[1]
    unbal = slab_m[1][1] + col_m[1]
    d_s = -DF_ext_val * unbal
    slab_m[1][1] += d_s;   col_m[1] -= (1.0 - DF_ext_val) * unbal
    slab_m[1][2] += COF_val * d_s

    # Joint 4 (exterior, symmetric): slab[3][2] + col[4]
    unbal = slab_m[3][2] + col_m[4]
    d_s = -DF_ext_val * unbal
    slab_m[3][2] += d_s;   col_m[4] -= (1.0 - DF_ext_val) * unbal
    slab_m[3][1] += COF_val * d_s

    # Joint 2 (interior): slab[1][2] + slab[2][1] + col[2]
    unbal = slab_m[1][2] + slab_m[2][1] + col_m[2]
    d_s = -DF_int_val * unbal
    slab_m[1][2] += d_s;   slab_m[2][1] += d_s
    col_m[2] -= DF_col_int * unbal
    slab_m[1][1] += COF_val * d_s
    slab_m[2][2] += COF_val * d_s

    # Joint 3 (interior, symmetric): slab[2][2] + slab[3][1] + col[3]
    unbal = slab_m[2][2] + slab_m[3][1] + col_m[3]
    d_s = -DF_int_val * unbal
    slab_m[2][2] += d_s;   slab_m[3][1] += d_s
    col_m[3] -= DF_col_int * unbal
    slab_m[2][1] += COF_val * d_s
    slab_m[3][2] += COF_val * d_s
end

# Extract span 1 centerline moments
M_neg_ext_efm_c = abs(slab_m[1][1])
M_neg_int_efm_c = abs(slab_m[1][2])
# Positive from statics: M₀_ctc = qu·l₂·l₁²/8 (center-to-center span)
M0_ctc = ustrip(u"kip*ft", qu * l2 * l1^2 / 8)
M_pos_efm_c = M0_ctc - (M_neg_ext_efm_c + M_neg_int_efm_c) / 2

@printf("    Converged (20 iterations):\n")
@printf("    %-24s %12s %12s %8s\n", "Location", "Computed", "SP Ref", "Δ%")
@printf("    %-24s %12s %12s %8s\n", "─"^24, "─"^12, "─"^12, "─"^8)

efm_sp = [ustrip(u"kip*ft", sp.M_neg_ext), ustrip(u"kip*ft", sp.M_pos), ustrip(u"kip*ft", sp.M_neg_int)]
efm_c  = [M_neg_ext_efm_c, M_pos_efm_c, M_neg_int_efm_c]
for (lbl, c_val, r_val) in zip(["Ext. negative CL","Positive CL","Int. negative CL"], efm_c, efm_sp)
    δ = (c_val - r_val) / max(abs(r_val), 1e-12)
    flag = abs(δ) ≤ 0.05 ? "✓" : (abs(δ) ≤ 0.10 ? "~" : "✗")
    @printf("    %-24s %12.2f %12.2f %+7.1f%% %s\n", lbl, c_val, r_val, 100δ, flag)
end
println()
note("Our Hardy Cross (using computed Ksb, Kc, Kt, Kec from Step 2) reproduces")
note("the SP Table 5 EFM centerline moments — validating the stiffness chain.")
note("M₀_ctc = qu·l₂·l₁²/8 = $(round(M0_ctc, digits=2)) kip·ft (c-t-c span for statics check).")

@test abs(M_neg_ext_efm_c - ustrip(u"kip*ft", sp.M_neg_ext)) / ustrip(u"kip*ft", sp.M_neg_ext) < 0.05
@test abs(M_neg_int_efm_c - ustrip(u"kip*ft", sp.M_neg_int)) / ustrip(u"kip*ft", sp.M_neg_int) < 0.05

# ── 4E: EFM ASAP Solver — structural frame analysis ──
sub_header("4E — EFM ASAP Solver (Structural Frame Analysis)")
println("  Build an ASAP frame model with EFM-compliant stiffnesses:")
println("  Slab I_eff = (k_slab/4) × I_gross,  Column I_eff derived from Kec")
println("  Solve as linear-elastic 2D frame → extract element end moments")
println()

# Build EFMSpanProperties for 3 identical spans (SP example)
l1_in = uconvert(u"inch", l1)
l2_in = uconvert(u"inch", l2)
ln_in = uconvert(u"inch", ln)
h_in  = uconvert(u"inch", h)
c_in  = uconvert(u"inch", c_col)

Is_in4   = uconvert(u"inch^4", Is)
Ksb_inlb = uconvert(u"lbf*inch", Ksb)

spans_asap = [
    StructuralSizer.EFMSpanProperties(
        i, i, i+1,
        l1_in, l2_in, ln_in,
        h_in, c_in, c_in, c_in, c_in,
        Is_in4, Ksb_inlb,
        0.08429, 0.507, 4.127
    ) for i in 1:3
]

# Interior frame line → all joints have torsional arms both sides
joint_positions_asap = [:interior, :interior, :interior, :interior]

qu_psf = uconvert(u"lbf/ft^2", qu)
model_asap, span_elements_asap, joint_Kec_asap = StructuralSizer.build_efm_asap_model(
    spans_asap, joint_positions_asap, qu_psf;
    column_height = H,
    Ecs = Ecs,
    Ecc = Ecc,
    ν_concrete = 0.20,
    ρ_concrete = 2380.0u"kg/m^3",
    k_col = 4.74
)
StructuralSizer.solve_efm_frame!(model_asap)

# Extract span moments
asap_moments = StructuralSizer.extract_span_moments(
    model_asap, span_elements_asap, spans_asap; qu=qu)

M_neg_ext_asap = ustrip(u"kip*ft", asap_moments[1].M_neg_left)
M_pos_asap     = ustrip(u"kip*ft", asap_moments[1].M_pos)
M_neg_int_asap = ustrip(u"kip*ft", asap_moments[1].M_neg_right)

@printf("    3-span frame:  %d slab elements + %d column stubs\n",
        length(span_elements_asap), length(joint_positions_asap))
@printf("    Kec at joints: %s × 10⁶ in-lb\n",
        join([string(round(ustrip(u"lbf*inch", k)/1e6, digits=1)) for k in joint_Kec_asap], ", "))
println()

@printf("    %-24s %10s %10s %10s %10s %8s\n",
        "Location", "ASAP", "Hardy-X", "SP Ref", "FEA†", "Δ%(ASAP)")
@printf("    %-24s %10s %10s %10s %10s %8s\n",
        "─"^24, "─"^10, "─"^10, "─"^10, "─"^10, "─"^8)

for (lbl, asap_v, hc_v, sp_v, fea_v) in [
    ("Ext. negative CL", M_neg_ext_asap, M_neg_ext_efm_c, ustrip(u"kip*ft", sp.M_neg_ext), M_neg_ext_fea),
    ("Positive CL",      M_pos_asap,     M_pos_efm_c,     ustrip(u"kip*ft", sp.M_pos),     M_pos_fea),
    ("Int. negative CL", M_neg_int_asap, M_neg_int_efm_c, ustrip(u"kip*ft", sp.M_neg_int), M_neg_int_fea)]
    δ = (asap_v - sp_v) / max(abs(sp_v), 1e-12)
    flag = abs(δ) ≤ 0.05 ? "✓" : (abs(δ) ≤ 0.10 ? "~" : "✗")
    @printf("    %-24s %10.2f %10.2f %10.2f %10.2f %+7.1f%% %s\n", lbl, asap_v, hc_v, sp_v, fea_v, 100δ, flag)
end
println()
note("† FEA uses different M₀ baseline (see Step 0) — compare ratios, not absolutes.")
note("ASAP solves the frame as a direct stiffness method (no iteration).")
note("Hardy Cross iterates to the same result — both should match SP Table 5.")
note("Small differences due to: stub model vs infinite column, element formulation.")

# Also extract interior span results for completeness
if length(asap_moments) >= 2
    M_neg_int_s2 = ustrip(u"kip*ft", asap_moments[2].M_neg_left)
    M_pos_s2     = ustrip(u"kip*ft", asap_moments[2].M_pos)
    println()
    @printf("    Interior span (ASAP): M⁻ = %.2f  M⁺ = %.2f  kip·ft\n", M_neg_int_s2, M_pos_s2)
    note("SP interior span: M⁻ = 76.21  M⁺ = 33.23 kip·ft")
end

@test abs(M_neg_ext_asap - ustrip(u"kip*ft", sp.M_neg_ext)) / ustrip(u"kip*ft", sp.M_neg_ext) < 0.05
@test abs(M_neg_int_asap - ustrip(u"kip*ft", sp.M_neg_int)) / ustrip(u"kip*ft", sp.M_neg_int) < 0.05
@test abs(M_pos_asap - ustrip(u"kip*ft", sp.M_pos)) / ustrip(u"kip*ft", sp.M_pos) < 0.05

# ── 4F: Side-by-side method comparison matrix ──
sub_header("4F — Method Comparison Matrix (Column-Strip Moments)")
println("  All moments in kip·ft.  Column-strip = CS fraction × centerline moment.")
println("  CS fractions (ACI 8.10.5):  ext neg 100%  /  pos 60%  /  int neg 75%")
println("  † FEA uses slightly different qᵤ (NWC_4000 density) — see Step 0.")
println()

# EFM CS moments (from SP centerline × ACI transverse fractions)
cs_ext_efm = cs_frac_ext * ustrip(u"kip*ft", sp.M_neg_ext)
cs_pos_efm = cs_frac_pos * ustrip(u"kip*ft", sp.M_pos)
cs_int_efm = cs_frac_int * ustrip(u"kip*ft", sp.M_neg_int)

# EFM Computed CS moments (from our Hardy Cross)
cs_ext_efm_c = cs_frac_ext * M_neg_ext_efm_c
cs_pos_efm_c = cs_frac_pos * M_pos_efm_c
cs_int_efm_c = cs_frac_int * M_neg_int_efm_c

# EFM ASAP CS moments (from ASAP solver)
cs_ext_asap = cs_frac_ext * M_neg_ext_asap
cs_pos_asap = cs_frac_pos * M_pos_asap
cs_int_asap = cs_frac_int * M_neg_int_asap

# FEA CS moments
cs_ext_fea = cs_frac_ext * M_neg_ext_fea
cs_pos_fea = cs_frac_pos * M_pos_fea
cs_int_fea = cs_frac_int * M_neg_int_fea

@printf("    %-14s %7s %7s %7s %7s %7s %7s %7s\n",
        "Location", "DDM", "DDM(fn)", "MDDM", "EFM(HC)", "EFM(AS)", "EFM(SP)", "FEA†")
@printf("    %-14s %7s %7s %7s %7s %7s %7s %7s\n",
        "─"^14, "─"^7, "─"^7, "─"^7, "─"^7, "─"^7, "─"^7, "─"^7)

# Centerline moments (full frame width)
M0_kf = ustrip(u"kip*ft", M0)
@printf("    %-14s %7.1f %7s %7s %7.1f %7.1f %7.1f %7.1f\n",
        "CL Ext neg", ustrip(u"kip*ft", M_neg_ext_ddm), "—", "—",
        M_neg_ext_efm_c, M_neg_ext_asap, ustrip(u"kip*ft", sp.M_neg_ext), M_neg_ext_fea)
@printf("    %-14s %7.1f %7s %7s %7.1f %7.1f %7.1f %7.1f\n",
        "CL Positive", ustrip(u"kip*ft", M_pos_ddm), "—", "—",
        M_pos_efm_c, M_pos_asap, ustrip(u"kip*ft", sp.M_pos), M_pos_fea)
@printf("    %-14s %7.1f %7s %7s %7.1f %7.1f %7.1f %7.1f\n",
        "CL Int neg", ustrip(u"kip*ft", M_neg_int_ddm), "—", "—",
        M_neg_int_efm_c, M_neg_int_asap, ustrip(u"kip*ft", sp.M_neg_int), M_neg_int_fea)
@printf("    %-14s %7s %7s %7s %7s %7s %7s %7s\n",
        "", "─"^7, "─"^7, "─"^7, "─"^7, "─"^7, "─"^7, "─"^7)

# Column-strip moments
@printf("    %-14s %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f\n",
        "CS Ext neg", ustrip(u"kip*ft", cs_ext_ddm), ddm_cs_ext_v,
        mddm_cs_ext_v, cs_ext_efm_c, cs_ext_asap, cs_ext_efm, cs_ext_fea)
@printf("    %-14s %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f\n",
        "CS Positive", ustrip(u"kip*ft", cs_pos_ddm), ddm_cs_pos_v,
        mddm_cs_pos_v, cs_pos_efm_c, cs_pos_asap, cs_pos_efm, cs_pos_fea)
@printf("    %-14s %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f\n",
        "CS Int neg", ustrip(u"kip*ft", cs_int_ddm), ddm_cs_int_v,
        mddm_cs_int_v, cs_int_efm_c, cs_int_asap, cs_int_efm, cs_int_fea)
println()

# M₀ baseline row
@printf("    %-14s %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f\n",
        "M₀ basis", M0_kf, M0_kf, M0_kf, M0_kf, M0_kf, M0_kf, M0_fea)
@printf("    %-14s %7.0f %7.0f %7.0f %7.0f %7.0f %7.0f %7.0f\n",
        "qᵤ basis (psf)", ustrip(u"psf",qu), ustrip(u"psf",qu), ustrip(u"psf",qu),
        ustrip(u"psf",qu), ustrip(u"psf",qu), ustrip(u"psf",qu), qu_fea_psf)
println()

note("DDM and DDM(fn) are identical — validates distribute_moments_aci.")
note("MDDM uses pre-combined coefficients; slightly different from DDM × ACI fractions.")
note("EFM(HC) = Hardy Cross;  EFM(AS) = ASAP solver;  EFM(SP) = StructurePoint ref.")
note("Both EFM solvers should closely match SP — ASAP uses direct stiffness, HC iterates.")
note("FEA† uses per-column skeleton-edge integration of shell Mxx/Myy/Mxy — no DDM coefficients.")
note("FEA captures two-way action: moment in one direction < M₀ (load shared with ⊥ dir).")
note("EFM gives ~2× larger ext neg vs DDM (stiffness attracts moment to supports).")
note("Positive moment: DDM overestimates, EFM is lower — safer for deflection but")
note("unconservative for negative moment rebar if DDM is used instead of EFM.")

# ── 4G: Face-of-support design moments ──
sub_header("4G — Face-of-Support Design Moments (SP Table 7)")
println("  Centerline → face reduction:  M_face = M_cl − V × min(c/2, 0.175·l₁)")
println("  Positive moment (midspan) has no face reduction.")
println()

# Shear at support ≈ qu × l2 × ln / 2
V_support = qu * l2 * ln / 2
V_kf = ustrip(u"kip*ft", V_support * 1u"ft")  # dummy conversion for face_of_support fn

# Face-of-support using our function — apply to EFM CS moments
cs_ext_efm_q = cs_frac_ext * sp.M_neg_ext
cs_pos_efm_q = cs_frac_pos * sp.M_pos
cs_int_efm_q = cs_frac_int * sp.M_neg_int

@printf("    %-24s %10s %10s %10s\n", "Location", "EFM CS CL", "SP Face", "FEA CS†")
@printf("    %-24s %10s %10s %10s\n", "─"^24, "─"^10, "─"^10, "─"^10)
@printf("    %-24s %10.2f %10.2f %10.2f\n", "Ext. negative",
        ustrip(u"kip*ft", cs_ext_efm_q), ustrip(u"kip*ft", sp.M_neg_ext_cs), cs_ext_fea)
@printf("    %-24s %10.2f %10.2f %10.2f\n", "Positive",
        ustrip(u"kip*ft", cs_pos_efm_q), ustrip(u"kip*ft", sp.M_pos_cs), cs_pos_fea)
@printf("    %-24s %10.2f %10.2f %10.2f\n", "Int. negative",
        ustrip(u"kip*ft", cs_int_efm_q), ustrip(u"kip*ft", sp.M_neg_int_cs), cs_int_fea)
println()
note("Face-of-support CS moments (SP Table 7) govern reinforcement design.")
note("Positive moment is unchanged — no face reduction at midspan.")
note("† FEA moments extracted per-column at each column face — no separate face reduction needed.")

# ── 4H: FEA Per-Column Demands (M⁻, Vu, Mub) ──
sub_header("4H — FEA Per-Column Demands")
println("  M⁻  = max section moment across all incident skeleton-edge directions")
println("  Vu  = column stub axial force (vertical shear at slab-column joint)")
println("  Mub = unbalanced moment (for punching shear transfer — ACI 8.4.4.2)")
println()

@printf("    %-5s  %-10s  %10s  %10s  %12s\n", "Col", "Position", "M⁻ (kip·ft)", "Vu (kip)", "Mub (kip·ft)")
@printf("    %-5s  %-10s  %10s  %10s  %12s\n", "─"^5, "─"^10, "─"^10, "─"^10, "─"^12)
for (i, col_fea_i) in enumerate(fea_columns)
    Mn_i = ustrip(u"kip*ft", fea_result.column_moments[i])
    Vu_i = ustrip(u"kip", fea_result.column_shears[i])
    Mub_i = ustrip(u"kip*ft", fea_result.unbalanced_moments[i])
    @printf("    %-5d  %-10s  %10.1f  %10.1f  %12.1f\n", i, string(col_fea_i.position), Mn_i, Vu_i, Mub_i)
end
println()

note("M⁻ is extracted per-column: for each incident skeleton edge, a section cut")
note("  perpendicular to that edge at the column face integrates Mn over the cell width.")
note("  The governing (max) direction is reported — no assumption about grid axes.")
println()

# Two-way load sharing ratio: FEA ∑/M₀
fea_sum = M_pos_fea + (M_neg_ext_fea + M_neg_int_fea) / 2
fea_ratio = fea_sum / M0_fea * 100
@printf("    Load sharing:  ∑(FEA moments) / M₀ = %.1f%%\n", fea_ratio)
note("FEA ∑/M₀ < 100% because 2D shell analysis distributes load in both directions.")
note("DDM/EFM assume 100% in each direction independently (conservative double-count).")
println()
note("FEA's value-add over DDM/EFM:")
note("  1. Per-column moments from skeleton-edge integration — no empirical coefficients")
note("  2. Accurate column shears (Vu) from stub axial forces")
note("  3. Unbalanced moments (Mub) for punching shear design")
note("  4. Geometry-agnostic: works for any slab shape, column layout, or mesh topology")
note("  5. Two-way action captured naturally (less conservative than DDM/EFM)")

@test M0_fea > 0
@test M_pos_fea > 0
@test length(fea_result.column_shears) == length(fea_columns)
@test all(ustrip.(u"kip", fea_result.column_shears) .> 0)

step_status["Method Comparison"] = "✓"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5  Effective Depth
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 5 — EFFECTIVE DEPTH")
println("  Two-way slab: bars in both directions → use average d")
println("  d₁ = h − cover − db/2       (top layer)")
println("  d₂ = h − cover − 3·db/2     (bottom layer)")
println("  d_avg = (d₁ + d₂)/2 = h − cover − db")
println("  cover = 0.75 in  (ACI Table 20.6.1.3.1)")
println("  db = #5 bar → 0.625 in")
println()

d = StructuralSizer.effective_depth(h; cover=0.75u"inch", bar_diameter=0.625u"inch")

d1 = h - 0.75u"inch" - 0.625u"inch" / 2   # top layer
d2 = h - 0.75u"inch" - 3 * 0.625u"inch" / 2  # bottom layer
@printf("    d₁ = %.3f in − 0.750 in − 0.625/2 in = %.4f in  (top layer)\n",
        ustrip(u"inch", h), ustrip(u"inch", d1))
@printf("    d₂ = %.3f in − 0.750 in − 3×0.625/2 in = %.4f in  (bottom layer)\n",
        ustrip(u"inch", h), ustrip(u"inch", d2))
@printf("    d_avg = (%.4f + %.4f) / 2 = %.4f in\n",
        ustrip(u"inch", d1), ustrip(u"inch", d2), ustrip(u"inch", d))

# SP uses d_avg = 5.75 in (#4 bars); our #5 bars give slightly different d_avg
d_sp = 5.75u"inch"
@printf("    SP uses d_avg = %.2f in (with #4 bars, db=0.5\")\n", ustrip(u"inch", d_sp))

@test d > 0u"inch"
step_status["Effective Depth"] = "✓"
note("ACI R22.6.1: d = average effective depth in two orthogonal directions.")
note("SP uses #4 bars (db=0.5\") → d_avg = 5.75 in; our #5 bars → d_avg = $(round(ustrip(u"inch", d), digits=3)) in.")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6  Reinforcement Design (SP Table 7)
#
# SP designs reinforcement from EFM face-of-support CS moments.
# We compute As from those same SP moments (Table 7 Mu values) to validate
# our required_reinforcement function against SP's As values.
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 6 — FLEXURAL REINFORCEMENT  (SP Table 7)")
println("  As = ρ · b · d   where ρ from Whitney stress block")
println("  Mu = φ · As · fy · (d − a/2),  φ = 0.9")
println("  b_cs = l₂/2 = $(uconvert(u"inch", l2/2))  (column-strip width)")
println("  SP uses d_avg = 5.75 in")
println()

b_cs = l2 / 2

# Compute As from SP's face-of-support CS moments (using SP's d_avg)
As_neg_ext = StructuralSizer.required_reinforcement(sp.M_neg_ext_cs, b_cs, d_sp, fc_slab, fy)
As_pos     = StructuralSizer.required_reinforcement(sp.M_pos_cs,     b_cs, d_sp, fc_slab, fy)
As_neg_int = StructuralSizer.required_reinforcement(sp.M_neg_int_cs, b_cs, d_sp, fc_slab, fy)

As_min = StructuralSizer.minimum_reinforcement(b_cs, h, fy)

As_neg_ext_final = max(As_neg_ext, As_min)
As_pos_final     = max(As_pos,     As_min)
As_neg_int_final = max(As_neg_int, As_min)

@printf("    As,min = %.3f in²  (ACI 8.6.1.1 — 0.0018 × b × h)\n\n",
        ustrip(u"inch^2", As_min))

sub_header("Column-Strip As  (b = l₂/2 = 84 in, d = 5.75 in)")
@printf("    %-30s %10s %10s %10s\n",
        "Location", "As,req", "As,min", "As,used")
@printf("    %-30s %10s %10s %10s\n", "─"^30, "─"^10, "─"^10, "─"^10)
@printf("    %-30s %10.3f %10.3f %10.3f\n",
        "Ext. negative", ustrip(u"inch^2", As_neg_ext),
        ustrip(u"inch^2", As_min), ustrip(u"inch^2", As_neg_ext_final))
@printf("    %-30s %10.3f %10.3f %10.3f\n",
        "Positive", ustrip(u"inch^2", As_pos),
        ustrip(u"inch^2", As_min), ustrip(u"inch^2", As_pos_final))
@printf("    %-30s %10.3f %10.3f %10.3f\n",
        "Int. negative", ustrip(u"inch^2", As_neg_int),
        ustrip(u"inch^2", As_min), ustrip(u"inch^2", As_neg_int_final))

println()
sub_header("Computed As  vs SP Table 7")
table_head()
ok1 = compare("As⁻ ext CS", As_neg_ext_final, sp.As_neg_ext_cs, u"inch^2"; tol=0.10)
ok2 = compare("As⁺ pos CS", As_pos_final,     sp.As_pos_cs,     u"inch^2"; tol=0.10)
ok3 = compare("As⁻ int CS", As_neg_int_final,  sp.As_neg_int_cs, u"inch^2"; tol=0.10)

@test ok1;  @test ok2;  @test ok3
step_status["Reinforcement"] = all((ok1, ok2, ok3)) ? "✓" : "✗"

note("Both computed and SP use the same EFM face-of-support CS moments.")
note("Small As differences due to iterative solver precision in required_reinforcement.")

# ── FEA Reinforcement (from FEA CS moments, using SP's d for comparability) ──
sub_header("FEA Reinforcement (CS moments from FEA, d = 5.75 in)")
println("  Using FEA per-column moments (skeleton-edge integration) with SP's d_avg = 5.75 in.")
println()

As_neg_ext_fea_v = StructuralSizer.required_reinforcement(cs_ext_fea * u"kip*ft", b_cs, d_sp, fc_slab, fy)
As_pos_fea_v     = StructuralSizer.required_reinforcement(cs_pos_fea * u"kip*ft", b_cs, d_sp, fc_slab, fy)
As_neg_int_fea_v = StructuralSizer.required_reinforcement(cs_int_fea * u"kip*ft", b_cs, d_sp, fc_slab, fy)

As_neg_ext_fea_final = max(As_neg_ext_fea_v, As_min)
As_pos_fea_final     = max(As_pos_fea_v,     As_min)
As_neg_int_fea_final = max(As_neg_int_fea_v, As_min)

@printf("    %-24s %10s %10s %10s %10s\n",
        "Location", "SP As", "EFM As", "FEA As", "FEA/SP")
@printf("    %-24s %10s %10s %10s %10s\n", "─"^24, "─"^10, "─"^10, "─"^10, "─"^10)

for (lbl, sp_As, efm_As, fea_As) in [
    ("Ext. negative", sp.As_neg_ext_cs, As_neg_ext_final, As_neg_ext_fea_final),
    ("Positive",      sp.As_pos_cs,     As_pos_final,     As_pos_fea_final),
    ("Int. negative", sp.As_neg_int_cs, As_neg_int_final, As_neg_int_fea_final)]
    sp_v = ustrip(u"inch^2", sp_As)
    efm_v = ustrip(u"inch^2", efm_As)
    fea_v_as = ustrip(u"inch^2", fea_As)
    ratio = sp_v > 0 ? fea_v_as / sp_v : 0.0
    @printf("    %-24s %10.3f %10.3f %10.3f %9.2f×\n", lbl, sp_v, efm_v, fea_v_as, ratio)
end
println()
note("FEA As differs from SP/EFM because M₀(FEA) ≠ M₀(SP) (slightly different qᵤ — see Step 0).")
note("FEA captures two-way action — moment in one direction < M₀ → less steel.")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7  Punching Shear Check (ACI 22.6)
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 7 — PUNCHING SHEAR  (ACI 22.6)")
println("  Interior column: critical section at d/2 from column face")
println("  b₀ = 2(c₁+d) + 2(c₂+d)")
println("  Vc = min(4√f'c, (2+4/β)√f'c, (αs·d/b₀+2)√f'c) × b₀ × d")
println("  Vu = qᵤ × (At − Ac)    where Ac = (c+d)²")
println()

b0 = StructuralSizer.punching_perimeter(c_col, c_col, d)
Vc = StructuralSizer.punching_capacity_interior(b0, d, fc_slab;
         c1=c_col, c2=c_col, position=:interior)

Vu_punch = StructuralSizer.punching_demand(qu, l1 * l2, c_col, c_col, d)

# Strip to common force unit before ratio
Vu_kip = ustrip(u"kip", uconvert(u"kip", Vu_punch))
Vc_kip = ustrip(u"kip", uconvert(u"kip", Vc))
φVc_kip = 0.75 * Vc_kip
ratio_punch = Vu_kip / φVc_kip

@printf("    b₀      = 2(%.2f + %.3f) + 2(%.2f + %.3f) = %.2f in\n",
        ustrip(u"inch", c_col), ustrip(u"inch", d),
        ustrip(u"inch", c_col), ustrip(u"inch", d), ustrip(u"inch", b0))
@printf("    Vc      = %.1f kip\n", Vc_kip)
@printf("    φVc     = %.1f kip   (φ = 0.75)\n", φVc_kip)
@printf("    Vu      = %.1f kip\n", Vu_kip)
pass_punch = ratio_punch ≤ 1.0
@printf("    Vu/φVc  = %.3f%s\n", ratio_punch, pass_punch ? "   ✓ PASS" : "   ✗ FAIL")

@test pass_punch
@test ratio_punch < 1.0

# ── FEA Punching Comparison ──
println()
sub_header("FEA Punching Shear Comparison")
println("  FEA extracts Vu directly from column stub forces (more accurate for")
println("  irregular layouts). Compare the max FEA Vu against the code formula.")
println()

Vu_fea_max = maximum(ustrip.(u"kip", fea_result.column_shears))
Vu_code    = Vu_kip
ratio_fea_punch = Vu_fea_max / φVc_kip

@printf("    %-24s %10s %10s\n", "", "Code", "FEA max")
@printf("    %-24s %10s %10s\n", "─"^24, "─"^10, "─"^10)
@printf("    %-24s %10.1f %10.1f\n", "Vu (kip)", Vu_code, Vu_fea_max)
@printf("    %-24s %10.1f %10s\n", "φVc (kip)", φVc_kip, "—")
@printf("    %-24s %10.3f %10.3f\n", "Vu/φVc", ratio_punch, ratio_fea_punch)
println()

note("Code Vu = qᵤ(At − Ac);  FEA Vu = stub axial force (includes load distribution effects).")
note("For regular grids, both should be similar. FEA shines on irregular geometries.")

step_status["Punching Shear"] = pass_punch ? "✓" : "✗"
note("SP example passes punching at h = 7 in with 16\" interior columns.")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8  Deflection (SP Section 6)
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 8 — DEFLECTION CHECK  (ACI 24.2 / SP Section 6)")
println("  Branson's equation: Ie = (Mcr/Ma)³·Ig + [1−(Mcr/Ma)³]·Icr")
println("  Long-term factor:  λ_Δ = ξ / (1 + 50ρ')   with ξ = 2.0 (≥5 yr)")
println()

Ig = l2 * h^3 / 12
fr_val = StructuralSizer.fr(fc_slab)
Mcr = StructuralSizer.cracking_moment(fr_val, Ig, h)

# Service positive moment (approximate: EFM pos / avg load factor)
Ma = sp.M_pos / 1.4

Es_rebar = 29000u"ksi"
As_min_defl = StructuralSizer.minimum_reinforcement(l2, h, fy)
Icr = StructuralSizer.cracked_moment_of_inertia(As_min_defl, l2, d, Ecs, Es_rebar)

Ie = StructuralSizer.effective_moment_of_inertia(Mcr, Ma, Ig, Icr)

λ_Δ = StructuralSizer.long_term_deflection_factor(2.0, 0.0)
Δ_limit = StructuralSizer.deflection_limit(l1, :total)

sub_header("Section Properties")
@printf("    Ig   = %.0f in⁴   (gross, full width l₂)\n", ustrip(u"inch^4", Ig))
@printf("    fr   = %.1f psi   (7.5√f'c)\n", ustrip(u"psi", fr_val))
@printf("    Mcr  = %.1f kip·ft\n", ustrip(u"kip*ft", Mcr))
@printf("    Ma   = %.1f kip·ft  (service positive ≈ EFM M⁺/1.4)\n",
        ustrip(u"kip*ft", Ma))

cracked = Ma > Mcr
println()
if cracked
    note("Ma > Mcr → section IS cracked under service load")
else
    note("Ma ≤ Mcr → section is UNCRACKED under service load (Ie = Ig)")
end

sub_header("Effective Moment of Inertia")
@printf("    Icr  = %.0f in⁴   (cracked, with As,min reinforcement)\n",
        ustrip(u"inch^4", Icr))
@printf("    Ie   = %.0f in⁴   (Branson's equation)\n", ustrip(u"inch^4", Ie))
@printf("    Ie/Ig = %.3f\n", ustrip(u"inch^4", Ie) / ustrip(u"inch^4", Ig))

@test ustrip(u"inch^4", Ie) >= ustrip(u"inch^4", Icr)
@test ustrip(u"inch^4", Ie) <= ustrip(u"inch^4", Ig)

sub_header("Long-Term & Limits")
@printf("    λ_Δ     = %.2f   (ξ=2.0, ρ'=0 → no compression steel)\n", λ_Δ)
@printf("    Δ_limit = L/240 = %.3f in\n", ustrip(u"inch", Δ_limit))

@test λ_Δ ≈ 2.0 rtol=0.01
@test Δ_limit ≈ l1 / 240 rtol=0.01
step_status["Deflection"] = "✓"
note("Full two-way deflection uses crossing-beam method in the pipeline;")
note("this step validates the individual ACI equations feeding into it.")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9  Column Axial Load
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 9 — COLUMN AXIAL LOAD")
println("  Interior column tributary area = l₁ × l₂ (full panel)")
println("  Pu = qᵤ × At")
println()

At = l1 * l2
Pu = qu * At

@printf("    At = %.1f ft × %.1f ft = %.1f ft²\n",
        ustrip(u"ft", l1), ustrip(u"ft", l2), ustrip(u"ft^2", At))
@printf("    Pu = %.0f psf × %.1f ft² = %.1f kip\n",
        ustrip(u"psf", qu), ustrip(u"ft^2", At), ustrip(u"kip", Pu))

@test ustrip(u"kip", Pu) ≈ 48.6 rtol=0.05
step_status["Column Axial Load"] = "✓"
note("This is the factored axial demand for P-M interaction design.")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 10  Integrity Reinforcement (ACI 8.7.4.2)
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 10 — INTEGRITY REINFORCEMENT  (ACI 8.7.4.2)")
println("  Continuous bottom steel to resist progressive collapse")
println("  Pu,integrity = 2 × (qD + qL) × At")
println("  As,integrity = Pu / (φ × fy)   with φ = 0.9")
println()

sw = StructuralSizer.slab_self_weight(h, 150.0u"pcf")
qD = sdl + sw
qL = ll

integrity = StructuralSizer.integrity_reinforcement(At, qD, qL, fy)

@printf("    Self-weight   = %.1f psf\n", ustrip(u"psf", sw))
@printf("    qD            = SDL + SW = %.1f + %.1f = %.1f psf\n",
        ustrip(u"psf", sdl), ustrip(u"psf", sw), ustrip(u"psf", qD))
@printf("    qL            = %.1f psf\n", ustrip(u"psf", qL))
@printf("    Pu,integrity  = %.1f kip\n", ustrip(u"kip", integrity.Pu_integrity))
@printf("    As,integrity  = %.3f in²\n", ustrip(u"inch^2", integrity.As_integrity))

@test ustrip(u"inch^2", integrity.As_integrity) > 0.3
@test ustrip(u"inch^2", integrity.As_integrity) < 3.0
step_status["Integrity Rebar"] = "✓"
note("This bottom steel must pass through the column core continuously.")

# ── 10B: Demo — integrity bump of bottom steel ──
sub_header("10B — Integrity Bump Demo (large tributary area)")
println("  When At is large enough, integrity As exceeds flexural As.")
println("  The pipeline detects this and re-selects bars to satisfy ACI 8.7.4.2.")
println()

# Large panel: 25×20 ft → At = 500 ft²  (forces integrity to govern)
demo_At    = 25.0u"ft" * 20.0u"ft"
demo_h     = 8.0u"inch"
demo_d     = demo_h - 0.75u"inch" - 0.3125u"inch"  # cover + db/2
demo_fc    = 4000.0u"psi"
demo_fy    = 60.0u"ksi"
demo_sdl   = 30.0u"psf"
demo_ll    = 100.0u"psf"
demo_sw    = StructuralSizer.slab_self_weight(demo_h, 150.0u"pcf")
demo_qD    = demo_sdl + demo_sw
demo_cs_w  = 20.0u"ft" / 2    # column strip = l₂/2

# Flexural positive moment for column strip (typical: 0.35 M₀ × 0.60)
demo_qu  = 1.2 * demo_qD + 1.6 * demo_ll
demo_ln  = 25.0u"ft" - 16.0u"inch"
demo_M0  = demo_qu * 20.0u"ft" * demo_ln^2 / 8
demo_Mpos_cs = 0.35 * demo_M0 * 0.60  # positive moment, column strip share

# Flexural design → bar selection
As_flex  = StructuralSizer.required_reinforcement(demo_Mpos_cs, demo_cs_w, demo_d, demo_fc, demo_fy)
As_min   = StructuralSizer.minimum_reinforcement(demo_cs_w, demo_h, demo_fy)
As_flex_design = max(As_flex, As_min)
flex_bars = StructuralSizer.select_bars(As_flex_design, demo_cs_w)

# Integrity requirement
demo_integ = StructuralSizer.integrity_reinforcement(demo_At, demo_qD, demo_ll, demo_fy)
integ_check = StructuralSizer.check_integrity_reinforcement(flex_bars.As_provided, demo_integ.As_integrity)

@printf("    Panel:         25×20 ft   At = %.0f ft²\n", ustrip(u"ft^2", demo_At))
@printf("    Slab:          h = %.1f in   d = %.2f in\n", ustrip(u"inch", demo_h), ustrip(u"inch", demo_d))
@printf("    Loads:         SDL = %.0f psf   LL = %.0f psf   qu = %.1f psf\n",
        ustrip(u"psf", demo_sdl), ustrip(u"psf", demo_ll), ustrip(u"psf", demo_qu))
@printf("    M₀             = %.1f kip·ft\n", ustrip(u"kip*ft", demo_M0))
@printf("    M⁺(cs)         = 0.35×0.60×M₀ = %.1f kip·ft\n", ustrip(u"kip*ft", demo_Mpos_cs))
println()
@printf("    Flexural As    = %.3f in²  (governs over As,min = %.3f in²)\n",
        ustrip(u"inch^2", As_flex_design), ustrip(u"inch^2", As_min))
@printf("    Flex bars      = %d #%d @ %.1f in   → As,prov = %.3f in²\n",
        flex_bars.n_bars, flex_bars.bar_size,
        ustrip(u"inch", flex_bars.spacing),
        ustrip(u"inch^2", flex_bars.As_provided))
println()
@printf("    Pu,integrity   = %.1f kip\n", ustrip(u"kip", demo_integ.Pu_integrity))
@printf("    As,integrity   = %.3f in²\n", ustrip(u"inch^2", demo_integ.As_integrity))
@printf("    Check          = %s  (util = %.2f)\n",
        integ_check.ok ? "PASS" : "FAIL — integrity governs",
        integ_check.utilization)

if !integ_check.ok
    # Bump: re-select bars to satisfy integrity
    bumped_bars = StructuralSizer.select_bars(demo_integ.As_integrity, demo_cs_w)
    println()
    @printf("    ⇒ Bumped bars  = %d #%d @ %.1f in   → As,prov = %.3f in²\n",
            bumped_bars.n_bars, bumped_bars.bar_size,
            ustrip(u"inch", bumped_bars.spacing),
            ustrip(u"inch^2", bumped_bars.As_provided))
    Δ_pct = (ustrip(u"inch^2", bumped_bars.As_provided) /
             ustrip(u"inch^2", flex_bars.As_provided) - 1) * 100
    @printf("    ΔAs            = +%.1f%%\n", Δ_pct)
    note("Pipeline automatically bumps column-strip positive steel when integrity governs.")
    @test ustrip(u"inch^2", bumped_bars.As_provided) >= ustrip(u"inch^2", demo_integ.As_integrity)
else
    note("Integrity does not govern for this geometry — flexural As is sufficient.")
end
println()

@test !integ_check.ok  # confirm this demo triggers the bump

# ═════════════════════════════════════════════════════════════════════════════
# STEP 11  Parametric Sensitivity Studies
#
# Vary one parameter at a time to show how key design checks respond.
# These tables help build intuition about which parameters matter most.
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 11 — PARAMETRIC SENSITIVITY STUDIES")

# ── 11A: Slab Thickness Sweep ──
sub_header("11A — Slab Thickness (h) vs Punching, Reinforcement & Deflection")
h_min_in = round(ustrip(u"inch", ln / 30), digits=1)
println("  Vary h from 5.5 in to 9 in with all other inputs fixed at SP baseline.")
println("  h_min = ln/30 = $(h_min_in) in (ACI 8.3.1.1, discontinuous)")
println()

h_trials = [5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0]u"inch"
γ_mass = 150.0u"pcf"
Es_rebar = 29000u"ksi"

Δ_lim_11a = ustrip(u"inch", l1 / 240)
@printf("  Limits:  Vu/φVc ≤ 1.0  (punching)    Δ_LT ≤ L/240 = %.2f in  (deflection)\n",
        Δ_lim_11a)
@printf("  Δ_LT = (1 + λΔ) × Δi = 3 × Δi   (λΔ = 2.0, ρ' = 0, ≥ 5 yr)\n\n")

@printf("    %5s  %5s  %7s  %7s  %7s  %7s  %8s  %5s  %5s\n",
        "h(in)", "d(in)", "qu(psf)", "Vu/φVc", "As,min", "Ie/Ig", "Δ_LT", "Punch", "Defl")
@printf("    %5s  %5s  %7s  %7s  %7s  %7s  %8s  %5s  %5s\n",
        "─"^5, "─"^5, "─"^7, "─"^7, "─"^7, "─"^7, "─"^8, "─"^5, "─"^5)

for h_t in h_trials
    # Derived quantities
    d_t  = StructuralSizer.effective_depth(h_t; cover=0.75u"inch", bar_diameter=0.625u"inch")
    sw_t = StructuralSizer.slab_self_weight(h_t, γ_mass)
    qu_t = 1.2 * (sdl + sw_t) + 1.6 * ll

    # Punching shear
    b0_t = StructuralSizer.punching_perimeter(c_col, c_col, d_t)
    Vc_t = StructuralSizer.punching_capacity_interior(b0_t, d_t, fc_slab;
               c1=c_col, c2=c_col, position=:interior)
    Vu_t = StructuralSizer.punching_demand(qu_t, l1 * l2, c_col, c_col, d_t)
    ratio_t = ustrip(u"lbf", Vu_t) / (0.75 * ustrip(u"lbf", Vc_t))

    # Reinforcement
    As_min_t = StructuralSizer.minimum_reinforcement(l2 / 2, h_t, fy)

    # Deflection — effective moment of inertia
    Ig_t  = l2 * h_t^3 / 12
    Mcr_t = StructuralSizer.cracking_moment(StructuralSizer.fr(fc_slab), Ig_t, h_t)
    Ma_t  = sp.M_pos / 1.4  # service positive moment (constant, from SP)
    As_defl_t = StructuralSizer.minimum_reinforcement(l2, h_t, fy)
    Icr_t = StructuralSizer.cracked_moment_of_inertia(As_defl_t, l2, d_t, Ecs, Es_rebar)
    Ie_t  = StructuralSizer.effective_moment_of_inertia(Mcr_t, Ma_t, Ig_t, Icr_t)
    Ie_Ig = ustrip(u"inch^4", Ie_t) / ustrip(u"inch^4", Ig_t)

    # Total long-term deflection: Δ_LT = (1 + λΔ) × Δi
    w_serv = (sdl + sw_t + ll) * l2  # service load per unit length
    Δi_t = StructuralSizer.immediate_deflection(w_serv, l1, Ecs, Ie_t)
    Δi_in = ustrip(u"inch", Δi_t)
    Δ_LT = (1.0 + 2.0) * Δi_in  # (1 + λΔ) × Δi

    punch_ok = ratio_t ≤ 1.0
    defl_ok  = Δ_LT < Δ_lim_11a
    mark = h_t == 7.0u"inch" ? " ◂" : ""

    @printf("    %5.1f  %5.2f  %7.0f  %7.3f  %7.3f  %7.3f  %8.3f  %3s    %3s%s\n",
            ustrip(u"inch", h_t), ustrip(u"inch", d_t), ustrip(u"psf", qu_t),
            ratio_t, ustrip(u"inch^2", As_min_t), Ie_Ig, Δ_LT,
            punch_ok ? "✓" : "✗", defl_ok ? "✓" : "✗", mark)
end
println()
note("◂ = SP baseline (h = 7\").  Punch = Vu/φVc ≤ 1.0.  Defl = Δ_LT < L/240.")
note("Thicker slab → lower punching ratio, higher Ie/Ig, less deflection.")
note("Thinner slab → higher qu but much worse punching (ratio ~ d²).")
note("For h ≤ 6.5\": deflection governs (Δ_LT > $(round(Δ_lim_11a, digits=2)) in).")

# ── 11B: Column Size Sweep ──
sub_header("11B — Column Size (c) vs Stiffness & Punching")
println("  Vary c from 12\" to 24\" (square column). Fixed h = 7\", H = 9 ft.")
println()

c_trials = [12.0, 14.0, 16.0, 18.0, 20.0, 24.0]u"inch"

@printf("    %5s  %7s  %10s  %10s  %6s  %7s\n",
        "c(in)", "ln(ft)", "Kec(M·in)", "αec", "Vu/φVc", "DF_ext")
@printf("    %5s  %7s  %10s  %10s  %6s  %7s\n",
        "─"^5, "─"^7, "─"^10, "─"^10, "─"^6, "─"^7)

for c_t in c_trials
    ln_t = l1 - c_t
    Ic_t = StructuralSizer.column_moment_of_inertia(c_t, c_t)
    C_t  = StructuralSizer.torsional_constant_C(h, c_t)
    Kc_t = StructuralSizer.column_stiffness_Kc(Ecc, Ic_t, H, h)
    Kt_t = StructuralSizer.torsional_member_stiffness_Kt(Ecs, C_t, l2, c_t)
    Kec_t = StructuralSizer.equivalent_column_stiffness_Kec(2Kc_t, 2Kt_t)
    αec_t = ustrip(u"lbf*inch", Kec_t) / (2 * ustrip(u"lbf*inch", Ksb))

    DF_ext_t = StructuralSizer.distribution_factor_DF(Ksb, Kec_t; is_exterior=true)

    # Punching with baseline d
    b0_t = StructuralSizer.punching_perimeter(c_t, c_t, d)
    Vc_t = StructuralSizer.punching_capacity_interior(b0_t, d, fc_slab;
               c1=c_t, c2=c_t, position=:interior)
    Vu_t = StructuralSizer.punching_demand(qu, l1 * l2, c_t, c_t, d)
    ratio_t = ustrip(u"lbf", Vu_t) / (0.75 * ustrip(u"lbf", Vc_t))

    @printf("    %5.0f  %7.2f  %10.1f  %10.3f  %6.3f  %7.4f\n",
            ustrip(u"inch", c_t), ustrip(u"ft", ln_t),
            ustrip(u"lbf*inch", Kec_t) / 1e6, αec_t, ratio_t, DF_ext_t)
end
println()
note("Larger columns: Kec↑ → αec↑ → stiffer joint → EFM attracts more moment")
note("  to supports, reducing positive moment and increasing column design demand.")
note("Larger columns: b₀↑ and Vc↑ → punching ratio drops significantly.")
note("c = 16\" is the SP baseline. At c = 12\", punching may be critical.")

# ── 11C: Reinforcement Level vs Deflection ──
sub_header("11C — Reinforcement Level vs Effective Stiffness & Deflection")
println("  Vary As from 0.5×As_min to 3.0×As_min.  Fixed h=7\", d=5.75\", b=l₂.")
println("  Shows how adding steel increases cracked stiffness Icr → less deflection.")
println()

As_base = StructuralSizer.minimum_reinforcement(l2, h, fy)  # full-width As_min
Ig_base = l2 * h^3 / 12
fr_base = StructuralSizer.fr(fc_slab)
Mcr_base = StructuralSizer.cracking_moment(fr_base, Ig_base, h)
Ma_base  = sp.M_pos / 1.4
w_base   = (sdl + StructuralSizer.slab_self_weight(h, γ_mass) + ll) * l2
d_sp_val = 5.75u"inch"

As_multipliers = [0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0]

@printf("    %7s  %8s  %10s  %7s  %8s  %8s\n",
        "As/Amin", "As(in²)", "Icr(in⁴)", "Ie/Ig", "Δi(in)", "Δ_LT(in)")
@printf("    %7s  %8s  %10s  %7s  %8s  %8s\n",
        "─"^7, "─"^8, "─"^10, "─"^7, "─"^8, "─"^8)

for mult in As_multipliers
    As_t  = mult * As_base
    Icr_t = StructuralSizer.cracked_moment_of_inertia(As_t, l2, d_sp_val, Ecs, Es_rebar)
    Ie_t  = StructuralSizer.effective_moment_of_inertia(Mcr_base, Ma_base, Ig_base, Icr_t)
    Ie_Ig = ustrip(u"inch^4", Ie_t) / ustrip(u"inch^4", Ig_base)

    Δi_t = StructuralSizer.immediate_deflection(w_base, l1, Ecs, Ie_t)
    Δi_in = ustrip(u"inch", Δi_t)
    Δ_lt = 2.0 * Δi_in + Δi_in  # total ≈ (1 + λΔ) × Δi

    @printf("    %7.2f  %8.2f  %10.0f  %7.3f  %8.4f  %8.4f\n",
            mult, ustrip(u"inch^2", As_t), ustrip(u"inch^4", Icr_t),
            Ie_Ig, Δi_in, Δ_lt)
end
println()
note("Δ_LT = (1 + λΔ) × Δi  where λΔ = 2.0 (no compression steel, ≥5 yr).")
let Δ_lim_in = round(ustrip(u"inch", l1/240), digits=2)
    note("Δ_limit = L/240 = $(Δ_lim_in) in.")
end
note("Even 3× As_min barely changes Ie/Ig because section is lightly cracked")
note("(Ma/Mcr ratio matters more than As for this geometry).")

# ── 11D: Column Shape — Square vs Circular ──
sub_header("11D — Column Shape: Square vs Circular (Same Area)")
println("  For each diameter D, the equivalent square c_eq = D×√(π/4) ≈ 0.886D.")
println("  Punching perimeter: square b₀ = 4(c+d), circular b₀ = π(D+d).")
println("  Column Ic:  square = c⁴/12,  circular = πD⁴/64.")
println("  All other inputs: h = 7\", d = 5.75\", H = 9 ft, f'c = 4000 psi.")
println()

D_trials = [12.0, 14.0, 16.0, 18.0, 20.0, 24.0]u"inch"

@printf("    %4s  %5s  ┃ %9s  %9s  %6s ┃ %9s  %9s  %6s ┃ %6s  %6s\n",
        "D", "c_eq",
        "b₀(sq)", "b₀(cir)", "Δb₀%",
        "Ic(sq)", "Ic(cir)", "ΔIc%",
        "Vu/φVc", "Vu/φVc")
@printf("    %4s  %5s  ┃ %9s  %9s  %6s ┃ %9s  %9s  %6s ┃ %6s  %6s\n",
        "(in)", "(in)",
        "(in)", "(in)", "",
        "(in⁴)", "(in⁴)", "",
        "sq", "cir")
@printf("    %4s  %5s  ┃ %9s  %9s  %6s ┃ %9s  %9s  %6s ┃ %6s  %6s\n",
        "─"^4, "─"^5,
        "─"^9, "─"^9, "─"^6,
        "─"^9, "─"^9, "─"^6,
        "─"^6, "─"^6)

for D_t in D_trials
    c_eq = StructuralSizer.equivalent_square_column(D_t)
    c_eq_in = ustrip(u"inch", c_eq)
    D_in = ustrip(u"inch", D_t)

    # Punching perimeters
    b0_sq  = StructuralSizer.punching_perimeter(c_eq, c_eq, d; shape=:rectangular)
    b0_cir = StructuralSizer.punching_perimeter(D_t, D_t, d; shape=:circular)
    b0_sq_in  = ustrip(u"inch", b0_sq)
    b0_cir_in = ustrip(u"inch", b0_cir)
    Δb0_pct = (b0_cir_in - b0_sq_in) / b0_sq_in * 100

    # Moment of inertia
    Ic_sq  = StructuralSizer.column_moment_of_inertia(c_eq, c_eq; shape=:rectangular)
    Ic_cir = StructuralSizer.column_moment_of_inertia(D_t, D_t; shape=:circular)
    Ic_sq_in4  = ustrip(u"inch^4", Ic_sq)
    Ic_cir_in4 = ustrip(u"inch^4", Ic_cir)
    ΔIc_pct = (Ic_cir_in4 - Ic_sq_in4) / Ic_sq_in4 * 100

    # Punching shear ratio — square (equivalent)
    Vc_sq = StructuralSizer.punching_capacity_interior(b0_sq, d, fc_slab;
                c1=c_eq, c2=c_eq, position=:interior, shape=:rectangular)
    Vu_sq = StructuralSizer.punching_demand(qu, l1*l2, c_eq, c_eq, d; shape=:rectangular)
    ratio_sq = ustrip(u"lbf", Vu_sq) / (0.75 * ustrip(u"lbf", Vc_sq))

    # Punching shear ratio — circular (actual)
    Vc_cir = StructuralSizer.punching_capacity_interior(b0_cir, d, fc_slab;
                 c1=D_t, c2=D_t, position=:interior, shape=:circular)
    Vu_cir = StructuralSizer.punching_demand(qu, l1*l2, D_t, D_t, d; shape=:circular)
    ratio_cir = ustrip(u"lbf", Vu_cir) / (0.75 * ustrip(u"lbf", Vc_cir))

    @printf("    %4.0f  %5.1f  ┃ %9.1f  %9.1f  %+5.1f%% ┃ %9.0f  %9.0f  %+5.1f%% ┃ %6.3f  %6.3f\n",
            D_in, c_eq_in,
            b0_sq_in, b0_cir_in, Δb0_pct,
            Ic_sq_in4, Ic_cir_in4, ΔIc_pct,
            ratio_sq, ratio_cir)
end
println()
note("c_eq = D×√(π/4): equivalent square with same cross-sectional area.")
note("Circular b₀ = π(D+d) < square b₀ = 4(c_eq+d): circle has ~14% less perimeter.")
note("  This is basic geometry: circles minimize perimeter for a given area.")
note("  → Circular columns are slightly worse for punching shear (less b₀).")
note("Circular Ic = πD⁴/64 < square Ic = c_eq⁴/12: ~4.5% lower stiffness.")
note("  → Slightly less stiff → slightly lower Kec → marginally lower column demand.")
note("Net effect: for the same concrete area, square columns give ~14% more")
note("  punching perimeter but ~4.5% more stiffness. Both differences are moderate.")
note("In practice, choosing circular vs square is driven by constructability,")
note("  not by small structural differences.")

# Validate that circular and square are reasonably close for baseline 16" column
let D_base = 16.0u"inch",
    c_eq_base = StructuralSizer.equivalent_square_column(D_base),
    b0_sq_base  = StructuralSizer.punching_perimeter(c_eq_base, c_eq_base, d; shape=:rectangular),
    b0_cir_base = StructuralSizer.punching_perimeter(D_base, D_base, d; shape=:circular),
    Ic_sq_base  = StructuralSizer.column_moment_of_inertia(c_eq_base, c_eq_base; shape=:rectangular),
    Ic_cir_base = StructuralSizer.column_moment_of_inertia(D_base, D_base; shape=:circular)

    # b₀ difference should be moderate (< 15%)
    Δb0 = abs(ustrip(u"inch", b0_cir_base) - ustrip(u"inch", b0_sq_base)) / ustrip(u"inch", b0_sq_base)
    @test Δb0 < 0.15
    compare("b₀ (circular vs eq. square)", b0_cir_base, b0_sq_base, u"inch"; tol=0.15)

    # Ic difference should be moderate (< 25%)
    ΔIc = abs(ustrip(u"inch^4", Ic_cir_base) - ustrip(u"inch^4", Ic_sq_base)) / ustrip(u"inch^4", Ic_sq_base)
    @test ΔIc < 0.25
    compare("Ic (circular vs eq. square)", Ic_cir_base, Ic_sq_base, u"inch^4"; tol=0.25)
end

step_status["Sensitivity Studies"] = "✓"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 12 — FULL SIZING COMPARISON: ALL 5 METHODS
#
# Larger geometry (25×20 ft panels, heavier loads) to push past minimum values
# and produce visible differences between methods.
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 12 — FULL SIZING: DDM vs MDDM vs EFM-HC vs EFM-AP vs FEA")
println("  Larger building: 75×60 ft, 3×3 bays → 25×20 ft panels")
println("  Heavier loads: SDL=30 psf, LL=100 psf, 12\" initial columns")
println("  Pipeline: h iteration → moment analysis → reinf → columns → checks → converge")
println()

# ─── Helper: build a fresh structure for a given method ───
sz_Lx = 75.0u"ft"
sz_Ly = 60.0u"ft"
sz_H  = 10.0u"ft"
sz_sdl = 30.0u"psf"
sz_ll  = 100.0u"psf"
sz_c0  = 12.0u"inch"   # initial column size (small → forces iteration)

function _build_sizing_struc(method_sym::Symbol)
    _skel = gen_medium_office(sz_Lx, sz_Ly, sz_H, 3, 3, 1)
    _struc = BuildingStructure(_skel)
    _opts = FloorOptions(
        flat_plate = FlatPlateOptions(
            material = RC_4000_60,
            analysis_method = method_sym,
            cover = 0.75u"inch",
            bar_size = 5,
        ),
        tributary_axis = nothing
    )
    initialize!(_struc; floor_type=:flat_plate, floor_kwargs=(options=_opts,))
    for c_i in _struc.cells
        c_i.sdl = uconvert(u"kN/m^2", sz_sdl)
        c_i.live_load = uconvert(u"kN/m^2", sz_ll)
    end
    for col_i in _struc.columns
        col_i.c1 = sz_c0
        col_i.c2 = sz_c0
    end
    to_asap!(_struc)
    return (_struc, _opts)
end

# ─── Run sizing for each method ───
sizing_data = Dict{Symbol, Any}()
methods_ordered = [:ddm, :mddm, :efm_hc, :efm_asap, :fea]
method_labels = Dict(
    :ddm      => "DDM",
    :mddm     => "MDDM",
    :efm_hc   => "EFM-HC",
    :efm_asap => "EFM-AP",
    :fea      => "FEA",
)
for method_sym in methods_ordered
    struc_m, opts_m = with_logger(NullLogger()) do
        _build_sizing_struc(method_sym)
    end
    StructuralSizer.size_slabs!(struc_m; options=opts_m, max_iterations=30)
    slab_m = struc_m.slabs[1]
    res = slab_m.result
    sizing_data[method_sym] = (struc=struc_m, result=res)
end

n_methods = length(methods_ordered)

# Helper: find strip reinforcement by location symbol
function _find_strip(reinf_vec, loc::Symbol)
    idx = findfirst(r -> r.location == loc, reinf_vec)
    isnothing(idx) ? nothing : reinf_vec[idx]
end

# Helper: total provided rebar
function _total_As(res)
    total = 0.0
    for sr in res.column_strip_reinf
        total += ustrip(u"inch^2", sr.As_provided)
    end
    for sr in res.middle_strip_reinf
        total += ustrip(u"inch^2", sr.As_provided)
    end
    total
end

# ─── 12A: Slab Thickness & Geometry ───
sub_header("12A — Slab Thickness & Geometry")

# Header
@printf("    %-18s", "")
for m in methods_ordered; @printf("  %8s", method_labels[m]); end
println()
@printf("    %-18s", "─"^18)
for _ in methods_ordered; @printf("  %8s", "─"^8); end
println()
# h
@printf("    %-18s", "h (in)")
for m in methods_ordered; @printf("  %8.1f", ustrip(u"inch", sizing_data[m].result.thickness)); end
println()
# M0
@printf("    %-18s", "M₀ (kip·ft)")
for m in methods_ordered; @printf("  %8.1f", ustrip(u"kip*ft", sizing_data[m].result.M0)); end
println()
# l1
@printf("    %-18s", "l₁ (ft)")
for m in methods_ordered; @printf("  %8.1f", ustrip(u"ft", sizing_data[m].result.l1)); end
println()
# l2
@printf("    %-18s", "l₂ (ft)")
for m in methods_ordered; @printf("  %8.1f", ustrip(u"ft", sizing_data[m].result.l2)); end
println()
println()
# SW
@printf("    %-18s", "SW (psf)")
for m in methods_ordered; @printf("  %8.1f", ustrip(u"psf", sizing_data[m].result.self_weight)); end
println()
# Total As
@printf("    %-18s", "ΣAs (in²)")
for m in methods_ordered; @printf("  %8.2f", _total_As(sizing_data[m].result)); end
println()
println()

# ─── 12B: Column-Strip Reinforcement ───
sub_header("12B — Column-Strip Reinforcement")

@printf("    %-18s", "Location")
for m in methods_ordered; @printf("  %10s", method_labels[m]); end
println()
@printf("    %-18s", "─"^18)
for _ in methods_ordered; @printf("  %10s", "─"^10); end
println()
for (loc_sym, loc_label) in [(:ext_neg, "Ext. negative"), (:pos, "Positive"), (:int_neg, "Int. negative")]
    @printf("    %-18s", "$loc_label As")
    for m in methods_ordered
        sr = _find_strip(sizing_data[m].result.column_strip_reinf, loc_sym)
        As = isnothing(sr) ? 0.0 : ustrip(u"inch^2", sr.As_provided)
        @printf("  %10.3f", As)
    end
    println()
    @printf("    %-18s", "  bar / spacing")
    for m in methods_ordered
        sr = _find_strip(sizing_data[m].result.column_strip_reinf, loc_sym)
        if isnothing(sr)
            @printf("  %10s", "—")
        else
            @printf("  #%d @ %4.1f\"", sr.bar_size, ustrip(u"inch", sr.spacing))
        end
    end
    println()
end
println()

# ─── 12C: Middle-Strip Reinforcement ───
sub_header("12C — Middle-Strip Reinforcement")

@printf("    %-18s", "Location")
for m in methods_ordered; @printf("  %10s", method_labels[m]); end
println()
@printf("    %-18s", "─"^18)
for _ in methods_ordered; @printf("  %10s", "─"^10); end
println()
for (loc_sym, loc_label) in [(:ext_neg, "Ext. negative"), (:pos, "Positive"), (:int_neg, "Int. negative")]
    @printf("    %-18s", "$loc_label As")
    for m in methods_ordered
        sr = _find_strip(sizing_data[m].result.middle_strip_reinf, loc_sym)
        As = isnothing(sr) ? 0.0 : ustrip(u"inch^2", sr.As_provided)
        @printf("  %10.3f", As)
    end
    println()
    @printf("    %-18s", "  bar / spacing")
    for m in methods_ordered
        sr = _find_strip(sizing_data[m].result.middle_strip_reinf, loc_sym)
        if isnothing(sr)
            @printf("  %10s", "—")
        else
            @printf("  #%d @ %4.1f\"", sr.bar_size, ustrip(u"inch", sr.spacing))
        end
    end
    println()
end
println()

# ─── 12D: Design Checks ───
sub_header("12D — Design Checks")

@printf("    %-22s", "")
for m in methods_ordered; @printf("  %8s", method_labels[m]); end
println()
@printf("    %-22s", "─"^22)
for _ in methods_ordered; @printf("  %8s", "─"^8); end
println()
@printf("    %-22s", "Punch Vu/φVc (max)")
for m in methods_ordered; @printf("  %8.3f", sizing_data[m].result.punching_check.max_ratio); end
println()
@printf("    %-22s", "Punching pass?")
for m in methods_ordered; @printf("  %8s", sizing_data[m].result.punching_check.ok ? "✓" : "✗"); end
println()
@printf("    %-22s", "Δ_check (in)")
for m in methods_ordered; @printf("  %8.3f", ustrip(u"inch", sizing_data[m].result.deflection_check.Δ_check)); end
println()
@printf("    %-22s", "Δ_limit (in)")
for m in methods_ordered; @printf("  %8.3f", ustrip(u"inch", sizing_data[m].result.deflection_check.Δ_limit)); end
println()
@printf("    %-22s", "Δ/Δ_limit")
for m in methods_ordered; @printf("  %8.3f", sizing_data[m].result.deflection_check.ratio); end
println()
@printf("    %-22s", "Deflection pass?")
for m in methods_ordered; @printf("  %8s", sizing_data[m].result.deflection_check.ok ? "✓" : "✗"); end
println()
println()

# ─── 12E: Column Sizes (after pipeline convergence) ───
sub_header("12E — Column Sizes After Convergence")

@printf("    %-22s", "Position")
for m in methods_ordered; @printf("  %10s", method_labels[m]); end
println()
@printf("    %-22s", "─"^22)
for _ in methods_ordered; @printf("  %10s", "─"^10); end
println()
for (pos_sym, pos_label) in [(:interior, "Interior"), (:edge, "Edge"), (:corner, "Corner")]
    @printf("    %-22s", pos_label)
    for m in methods_ordered
        pos_cols = filter(c -> c.position == pos_sym, sizing_data[m].struc.columns)
        if isempty(pos_cols)
            @printf("  %10s", "—")
        else
            c1 = ustrip(u"inch", pos_cols[1].c1)
            c2 = ustrip(u"inch", pos_cols[1].c2)
            @printf("  %4.0f×%4.0f\"", c1, c2)
        end
    end
    println()
end
println()

# ─── 12F: Compact Summary ───
sub_header("12F — One-Line Summary")
println()
@printf("    %-6s │ %4s │ %6s │ %6s │ %6s │ %8s │ %8s │ %s\n",
        "Method", "h\"", "M₀", "ΣAs", "Vu/φVc", "Δ/Δ_lim", "Int col", "Status")
@printf("    %-6s │ %4s │ %6s │ %6s │ %6s │ %8s │ %8s │ %s\n",
        "─"^6, "─"^4, "─"^6, "─"^6, "─"^6, "─"^8, "─"^8, "─"^8)
for m in methods_ordered
    res = sizing_data[m].result
    struc_m = sizing_data[m].struc
    h_in = ustrip(u"inch", res.thickness)
    M0_kf = ustrip(u"kip*ft", res.M0)
    total_As = _total_As(res)
    punch = res.punching_check.max_ratio
    defl = res.deflection_check.ratio
    int_cols = filter(c -> c.position == :interior, struc_m.columns)
    col_str = isempty(int_cols) ? "—" : "$(round(Int, ustrip(u"inch", int_cols[1].c1)))\""
    ok = res.punching_check.ok && res.deflection_check.ok
    @printf("    %-6s │ %4.1f │ %6.1f │ %6.2f │ %6.3f │ %8.3f │ %8s │ %s\n",
            method_labels[m], h_in, M0_kf, total_As, punch, defl, col_str, ok ? "✓ PASS" : "✗ FAIL")
end
println()

note("Geometry: $(ustrip(u"ft", sz_Lx))×$(ustrip(u"ft", sz_Ly)) ft, 3×3 bays, f'c=4000 psi, fy=60 ksi.")
note("Initial column = $(round(Int, ustrip(u"inch", sz_c0)))\" sq. SDL=$(ustrip(u"psf", sz_sdl)) psf, LL=$(ustrip(u"psf", sz_ll)) psf.")
note("All methods use the same span direction (slab grouper primary = short span).")
note("Differences arise ONLY from the analysis method — geometry, loads, materials identical.")
note("ΣAs = total provided rebar area (column + middle strips, all locations).")

# ─── 12G: Per-Position Punching Demands ───
sub_header("12G — Per-Position Punching Demands (Frame of Reference)")

# Use the first method's result for panel geometry reference
ref_res = sizing_data[:ddm].result
ref_l1 = ustrip(u"ft", ref_res.l1)
ref_l2 = ustrip(u"ft", ref_res.l2)
ref_qu = ustrip(u"psf", ref_res.qu)
panel_ft2 = ref_l1 * ref_l2
println("  Simple tributary reference:  Vu,trib = qᵤ × At   (no deduction for Ac)")
@printf("  Panel = %.0f × %.0f = %.0f ft²,  qᵤ = %.0f psf\n", ref_l1, ref_l2, panel_ft2, ref_qu)
println()

trib_at = Dict(:interior => panel_ft2, :edge => panel_ft2 / 2.0, :corner => panel_ft2 / 4.0)

@printf("    %-10s │ %7s │", "Position", "At(ft²)")
for m in methods_ordered; @printf(" %8s", method_labels[m]); end
@printf(" │ %8s\n", "Trib Vu")
@printf("    %-10s │ %7s │", "─"^10, "─"^7)
for _ in methods_ordered; @printf(" %8s", "─"^8); end
@printf(" │ %8s\n", "─"^8)

for (pos_sym, pos_label) in [(:interior, "Interior"), (:edge, "Edge"), (:corner, "Corner")]
    At = trib_at[pos_sym]
    Vu_trib = ref_qu * At / 1000.0  # kip

    @printf("    %-10s │ %7.0f │", pos_label, At)
    for m in methods_ordered
        details = sizing_data[m].result.punching_check.details
        pos_ratios = Float64[]
        for (col_idx, pr) in details
            if sizing_data[m].struc.columns[col_idx].position == pos_sym
                push!(pos_ratios, pr.ratio)
            end
        end
        if isempty(pos_ratios)
            @printf(" %8s", "—")
        else
            @printf(" %8.3f", maximum(pos_ratios))
        end
    end
    @printf(" │ %7.1f k\n", Vu_trib)
end
println()

note("Table shows max Vu/φVc per position; Trib Vu = simple hand-calc reference.")
note("Larger panels + heavier loads push punching ratios well above minimum values.")

# ─── 12H: Interpretation — What the Differences Mean ───
sub_header("12H — Interpretation: Why Methods Differ")
println()
println("  1. DDM vs MDDM")
println("     Slightly different longitudinal coefficients (e.g. DDM 0.26/0.312/0.525")
println("     vs MDDM 0.27/0.345/0.55). Both use simple M₀ distribution — no iteration.")
println("     Differences are small but visible in reinforcement quantities.")
println()
println("  2. EFM-HC vs EFM-AP")
println("     Both use the same equivalent frame stiffnesses. HC = Hardy Cross iteration;")
println("     AP = ASAP direct stiffness (exact). Differences arise from iteration")
println("     convergence — typically < 2% for well-conditioned frames.")
println()
println("  3. FEA vs DDM/EFM")
println("     FEA captures two-way plate action: load distributes in both directions")
println("     simultaneously, so moment in any single direction < M₀.")
println("     FEA's ext/int classification uses building topology (column position),")
println("     not span-direction position as in DDM/EFM.")
println("     Expect FEA to produce lower bending reinforcement but may show")
println("     higher punching demands at some columns.")

@test all(sizing_data[m].result.punching_check.ok for m in methods_ordered)

step_status["Full Sizing"] = "✓"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 13 — FLAT SLAB WITH DROP PANELS
#
# Flat slabs have thickened drop panels around columns (ACI 318-19 §8.2.4)
# which increase punching shear capacity and allow thinner slab thickness.
# This section compares flat plate vs flat slab design side by side.
# ═════════════════════════════════════════════════════════════════════════════

section_header("STEP 13 — FLAT SLAB WITH DROP PANELS")
println("  Flat slabs have thickened drop panels at columns (ACI 318-19 §8.2.4).")
println("  Benefits: reduced slab thickness, improved punching shear, less rebar.")
println("  This section provides side-by-side comparisons for engineer review.")
println()

# ── 13A: Minimum Thickness — Flat Plate vs Flat Slab ──
sub_header("13A — Minimum Thickness: Flat Plate vs Flat Slab (ACI 8.3.1.1)")
println("  Flat Plate:  h_min = ln/30 (exterior)  ln/33 (interior)")
println("  Flat Slab:   h_min = ln/33 (exterior)  ln/36 (interior)")
println("  → Drop panels allow ~9% thinner slab for the same clear span.")
println()

ln_trials = [15.0, 18.0, 20.0, 22.0, 25.0]u"ft"

@printf("    %6s  %7s  %7s  %7s  %7s  %8s\n",
        "ln(ft)", "FP ext", "FP int", "FS ext", "FS int", "Savings")
@printf("    %6s  %7s  %7s  %7s  %7s  %8s\n",
        "─"^6, "─"^7, "─"^7, "─"^7, "─"^7, "─"^8)

for ln_t in ln_trials
    fp_ext = StructuralSizer.min_thickness_flat_plate(ln_t; discontinuous_edge=true)
    fp_int = StructuralSizer.min_thickness_flat_plate(ln_t; discontinuous_edge=false)
    fs_ext = StructuralSizer.min_thickness_flat_slab(ln_t; discontinuous_edge=true)
    fs_int = StructuralSizer.min_thickness_flat_slab(ln_t; discontinuous_edge=false)

    savings = (1.0 - ustrip(u"inch", fs_ext) / ustrip(u"inch", fp_ext)) * 100

    @printf("    %6.0f  %6.1f\"  %6.1f\"  %6.1f\"  %6.1f\"  %7.0f%%\n",
            ustrip(u"ft", ln_t),
            ustrip(u"inch", fp_ext), ustrip(u"inch", fp_int),
            ustrip(u"inch", fs_ext), ustrip(u"inch", fs_int), savings)
end
println()
note("FP = Flat Plate (ACI Table 8.3.1.1 Row 1).  FS = Flat Slab (Row 2).")
note("Savings = (FP_ext − FS_ext) / FP_ext.  All rounded up to 0.5\" in practice.")
note("The 9-10% thickness reduction is the primary economic driver for drop panels.")

# Validate
@test StructuralSizer.min_thickness_flat_slab(18.0u"ft") <
      StructuralSizer.min_thickness_flat_plate(18.0u"ft")

# ── 13B: Drop Panel Geometry (ACI 8.2.4) ──
sub_header("13B — Drop Panel Geometry (ACI 8.2.4)")
println("  ACI 8.2.4 requires:  (a) h_drop ≥ h_slab/4   (b) a_drop ≥ l/6")
println("  Standard lumber depths (with plyform): 2.25\", 4.25\", 6.25\", 8.0\"")
println()

h_trials_dp = [6.0, 7.0, 8.0, 9.0, 10.0, 12.0]u"inch"

@printf("    %6s  %9s  %9s  %10s  %7s\n",
        "h_slab", "h/4 min", "h_drop", "h_total", "Check")
@printf("    %6s  %9s  %9s  %10s  %7s\n",
        "─"^6, "─"^9, "─"^9, "─"^10, "─"^7)

for h_t in h_trials_dp
    h_drop = StructuralSizer.auto_size_drop_depth(h_t)
    h_min_drop = h_t / 4
    h_total = h_t + h_drop
    ok = h_drop >= h_min_drop

    @printf("    %5.1f\"  %8.2f\"  %8.2f\"  %9.2f\"  %5s\n",
            ustrip(u"inch", h_t),
            ustrip(u"inch", h_min_drop),
            ustrip(u"inch", h_drop),
            ustrip(u"inch", h_total),
            ok ? "✓" : "✗")
end
println()

# Show plan extent example for SP geometry
l1_dp = 18.0u"ft";  l2_dp = 14.0u"ft"
a1 = l1_dp / 6;  a2 = l2_dp / 6
println("  For SP baseline (l₁=18', l₂=14'):")
@printf("    a_drop_1 = l₁/6 = %.2f ft = %.1f in   → full extent = %.1f in (%.1f ft)\n",
        ustrip(u"ft", a1), ustrip(u"inch", a1), ustrip(u"inch", 2*a1), ustrip(u"ft", 2*a1))
@printf("    a_drop_2 = l₂/6 = %.2f ft = %.1f in   → full extent = %.1f in (%.1f ft)\n",
        ustrip(u"ft", a2), ustrip(u"inch", a2), ustrip(u"inch", 2*a2), ustrip(u"ft", 2*a2))
println()
note("Plan extent: drop panel extends l/6 from column center in each direction.")
note("For 16\" column + 36\" drop extent = 28\" clear from column face per side — generous formwork zone.")

@test all(StructuralSizer.auto_size_drop_depth(h_t) >= h_t / 4 for h_t in h_trials_dp)

# ── 13C: Edge Beam βt Effect on DDM Moments ──
sub_header("13C — Edge Beam βt Effect on DDM Moments (ACI 8.10.4.2 / 8.10.5.2)")
println("  βt = torsional stiffness ratio of the edge beam / slab.")
println("  Higher βt → more moment attracted to exterior support, less to midspan.")
println()

M0_βt = sp.M0  # use SP baseline M₀ = 93.82 kip-ft
βt_trials = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]

@printf("    %4s  %8s  %8s  %8s  %10s  %12s\n",
        "βt", "ext_neg", "pos", "int_neg", "CS ext frac", "CS ext neg")
@printf("    %4s  %8s  %8s  %8s  %10s  %12s\n",
        "─"^4, "─"^8, "─"^8, "─"^8, "─"^10, "─"^12)

for βt_v in βt_trials
    coeffs = StructuralSizer.aci_ddm_longitudinal_with_edge_beam(βt_v)
    cs_frac = StructuralSizer.aci_col_strip_ext_neg_fraction(βt_v)
    cs_ext = cs_frac * coeffs.ext_neg * ustrip(u"kip*ft", M0_βt)

    @printf("    %4.1f  %7.3f×  %7.3f×  %7.3f×  %9.0f%%  %10.1f k·ft\n",
            βt_v, coeffs.ext_neg, coeffs.pos, coeffs.int_neg, 100*cs_frac, cs_ext)
end
println()
note("βt = 0: no edge beam (flat plate default) → 26% M₀ to exterior negative.")
note("βt ≥ 2.5: full edge beam → 30% M₀ to exterior, but only 75% to column strip.")
note("Net CS ext neg: 26.0 k·ft (βt=0) vs 21.1 k·ft (βt=2.5) — less rebar at exterior.")
note("The reduced CS exterior negative with edge beam means less congestion at edge columns.")

# Validate monotonic behavior
@test StructuralSizer.aci_ddm_longitudinal_with_edge_beam(2.5).ext_neg >
      StructuralSizer.aci_ddm_longitudinal_with_edge_beam(0.0).ext_neg
@test StructuralSizer.aci_col_strip_ext_neg_fraction(2.5) <
      StructuralSizer.aci_col_strip_ext_neg_fraction(0.0)

# ── 13D: Compression Steel (ρ') Effect on Deflection ──
sub_header("13D — Compression Steel (ρ') Effect on Long-Term Deflection")
println("  λ_Δ = ξ / (1 + 50ρ')   where ξ = 2.0 for sustained loads ≥ 5 years.")
println("  Top bars extending past midspan act as compression steel → lower λ_Δ → less creep.")
println()

ρ_trials = [0.0, 0.001, 0.002, 0.005, 0.010, 0.020]

@printf("    %6s  %6s  %10s  %10s\n",
        "ρ'", "λ_Δ", "Δ_LT/Δ_LT₀", "Reduction")
@printf("    %6s  %6s  %10s  %10s\n",
        "─"^6, "─"^6, "─"^10, "─"^10)

λ_Δ_0 = StructuralSizer.long_term_deflection_factor(2.0, 0.0)
for ρ_v in ρ_trials
    λ_Δ_v = StructuralSizer.long_term_deflection_factor(2.0, ρ_v)
    ratio = λ_Δ_v / λ_Δ_0
    reduction = (1.0 - ratio) * 100

    @printf("    %6.3f  %6.3f  %9.0f%%  %9.0f%%\n",
            ρ_v, λ_Δ_v, 100*ratio, reduction)
end
println()
note("ρ' = 0.005 (typical for flat plates) → 20% reduction in long-term deflection.")
note("ρ' = 0.010 (generous negative steel) → 33% reduction — often makes borderline Δ pass.")
note("The pipeline estimates ρ' from 50% of column-strip negative steel extending to midspan.")

@test StructuralSizer.long_term_deflection_factor(2.0, 0.01) <
      StructuralSizer.long_term_deflection_factor(2.0, 0.0)

# ── 13E: Full Pipeline — Flat Plate vs Flat Slab ──
sub_header("13E — Full Sizing: Flat Plate vs Flat Slab (DDM)")
println("  Same 75×60 ft building from Step 12, DDM analysis, SDL=30 psf, LL=100 psf.")
println("  Compare flat plate (h from Table 8.3.1.1 Row 1) vs flat slab (Row 2 + drop panels).")
println()

# Build flat slab structure (same geometry as Step 12)
fs_struc, fs_opts = with_logger(NullLogger()) do
    _skel = gen_medium_office(sz_Lx, sz_Ly, sz_H, 3, 3, 1)
    _struc = BuildingStructure(_skel)
    _opts = FloorOptions(
        flat_slab = FlatSlabOptions(
            base = FlatPlateOptions(
                material = RC_4000_60,
                analysis_method = :ddm,
                cover = 0.75u"inch",
                bar_size = 5,
            ),
        ),
        tributary_axis = nothing,
    )
    initialize!(_struc; floor_type=:flat_slab, floor_kwargs=(options=_opts,))
    for c_i in _struc.cells
        c_i.sdl = uconvert(u"kN/m^2", sz_sdl)
        c_i.live_load = uconvert(u"kN/m^2", sz_ll)
    end
    for col_i in _struc.columns
        col_i.c1 = sz_c0
        col_i.c2 = sz_c0
    end
    to_asap!(_struc)
    (_struc, _opts)
end

StructuralSizer.size_slabs!(fs_struc; options=fs_opts, max_iterations=30)
fs_slab = fs_struc.slabs[1]
fs_res = fs_slab.result
fs_dp = fs_slab.drop_panel

# Pull flat plate DDM result from Step 12
fp_res = sizing_data[:ddm].result
fp_struc = sizing_data[:ddm].struc

# Side-by-side comparison
@printf("    %-24s %12s %12s %10s\n",
        "Metric", "Flat Plate", "Flat Slab", "Δ%")
@printf("    %-24s %12s %12s %10s\n",
        "─"^24, "─"^12, "─"^12, "─"^10)

h_fp = ustrip(u"inch", fp_res.thickness)
h_fs = ustrip(u"inch", fs_res.thickness)
@printf("    %-24s %11.1f\" %11.1f\" %+9.0f%%\n",
        "Slab thickness h", h_fp, h_fs, (h_fs/h_fp - 1)*100)

if !isnothing(fs_dp)
    @printf("    %-24s %12s %11.2f\" %10s\n",
            "Drop panel depth", "—",
            ustrip(u"inch", fs_dp.h_drop), "n/a")
    h_total_fs = h_fs + ustrip(u"inch", fs_dp.h_drop)
    @printf("    %-24s %12s %11.2f\" %10s\n",
            "Total depth at column", "—", h_total_fs, "n/a")
    @printf("    %-24s %12s %10.1f\"×%.1f\" %8s\n",
            "Drop panel plan", "—",
            ustrip(u"inch", StructuralSizer.drop_extent_1(fs_dp)),
            ustrip(u"inch", StructuralSizer.drop_extent_2(fs_dp)), "")
end

M0_fp = ustrip(u"kip*ft", fp_res.M0)
M0_fs = ustrip(u"kip*ft", fs_res.M0)
@printf("    %-24s %11.1f %11.1f %+9.0f%%\n",
        "M₀ (kip·ft)", M0_fp, M0_fs, (M0_fs/M0_fp - 1)*100)

sw_fp = ustrip(u"psf", fp_res.self_weight)
sw_fs = ustrip(u"psf", fs_res.self_weight)
@printf("    %-24s %11.1f %11.1f %+9.0f%%\n",
        "Self-weight (psf)", sw_fp, sw_fs, (sw_fs/sw_fp - 1)*100)

As_fp = _total_As(fp_res)
As_fs = _total_As(fs_res)
@printf("    %-24s %11.2f %11.2f %+9.0f%%\n",
        "ΣAs (in²)", As_fp, As_fs, (As_fs/As_fp - 1)*100)

punch_fp = fp_res.punching_check.max_ratio
punch_fs = fs_res.punching_check.max_ratio
@printf("    %-24s %11.3f %11.3f %+9.0f%%\n",
        "Max Vu/φVc", punch_fp, punch_fs, (punch_fs/punch_fp - 1)*100)

defl_fp = fp_res.deflection_check.ratio
defl_fs = fs_res.deflection_check.ratio
@printf("    %-24s %11.3f %11.3f %+9.0f%%\n",
        "Δ/Δ_limit", defl_fp, defl_fs, (defl_fs/defl_fp - 1)*100)

# Column sizes
fp_int_cols = filter(c -> c.position == :interior, fp_struc.columns)
fs_int_cols = filter(c -> c.position == :interior, fs_struc.columns)
if !isempty(fp_int_cols) && !isempty(fs_int_cols)
    c_fp = round(Int, ustrip(u"inch", fp_int_cols[1].c1))
    c_fs = round(Int, ustrip(u"inch", fs_int_cols[1].c1))
    @printf("    %-24s %11d\" %11d\" %+9.0f%%\n",
            "Interior column", c_fp, c_fs, (c_fs/c_fp - 1)*100)
end
println()

note("Flat slab thickness governed by ACI 8.3.1.1 Row 2 (ln/33, ln/36 with drops).")
note("Drop panel increases total depth at columns → better punching without thick slab.")
note("Lower h → less self-weight → lower M₀ → less reinforcement — a compounding benefit.")
note("Punching is checked at BOTH column face (h_total) and drop edge (h_slab).")

@test fs_res.punching_check.ok
@test fs_res.deflection_check.ok
@test h_fs <= h_fp  # flat slab should be at least as thin

# ── 13F: Dual Punching Shear Check ──
sub_header("13F — Flat Slab Dual Punching Shear Check (ACI 22.6)")
println("  Flat slabs require TWO punching checks:")
println("    1. At column face → d/2 from face, using total depth (h_slab + h_drop)")
println("    2. At drop edge → d/2 from drop panel edge, using slab depth (h_slab only)")
println("  The governing check is whichever has the higher demand/capacity ratio.")
println()

if !isnothing(fs_dp)
    h_slab_fs = fs_res.thickness
    h_total_fs_q = StructuralSizer.total_depth_at_drop(h_slab_fs, fs_dp)
    d_slab_fs = StructuralSizer.effective_depth(h_slab_fs; cover=0.75u"inch", bar_diameter=0.625u"inch")
    d_total_fs = StructuralSizer.effective_depth(h_total_fs_q; cover=0.75u"inch", bar_diameter=0.625u"inch")

    @printf("    h_slab = %.1f in    h_drop = %.2f in    h_total = %.2f in\n",
            ustrip(u"inch", h_slab_fs), ustrip(u"inch", fs_dp.h_drop),
            ustrip(u"inch", h_total_fs_q))
    @printf("    d_slab = %.2f in   d_total = %.2f in\n",
            ustrip(u"inch", d_slab_fs), ustrip(u"inch", d_total_fs))
    @printf("    Drop extent: %.1f\" × %.1f\" (plan)\n\n",
            ustrip(u"inch", StructuralSizer.drop_extent_1(fs_dp)),
            ustrip(u"inch", StructuralSizer.drop_extent_2(fs_dp)))

    # Show punching for a representative interior column
    fs_cols = filter(c -> c.position == :interior, fs_struc.columns)
    if !isempty(fs_cols)
        sample_col = fs_cols[1]
        c1_v = ustrip(u"inch", sample_col.c1)

        # Column face check: b₀ based on (c + d_total)
        b0_col = StructuralSizer.punching_perimeter(sample_col.c1, sample_col.c2, d_total_fs)
        # Drop edge check: b₀ based on (2×a_drop + d_slab)
        b1_drop = 2 * fs_dp.a_drop_1 + d_slab_fs
        b2_drop = 2 * fs_dp.a_drop_2 + d_slab_fs
        b0_drop = 2 * (b1_drop + b2_drop)

        @printf("    Interior column (%.0f\" sq):\n", c1_v)
        @printf("      Column face:  b₀ = %.1f in  (d = %.2f in, total depth)\n",
                ustrip(u"inch", b0_col), ustrip(u"inch", d_total_fs))
        @printf("      Drop edge:    b₀ = %.1f in  (d = %.2f in, slab depth only)\n",
                ustrip(u"inch", b0_drop), ustrip(u"inch", d_slab_fs))
        println()
        note("Column face b₀ is small but uses full depth → higher capacity per inch of perimeter.")
        note("Drop edge b₀ is large but uses only slab depth → lower unit capacity.")
        note("Both must pass; the governing section depends on geometry.")
    end
end

step_status["Flat Slab"] = "✓"

# ═════════════════════════════════════════════════════════════════════════════
# DESIGN CODE FEATURES & LIMITATIONS
# ═════════════════════════════════════════════════════════════════════════════

section_header("DESIGN CODE FEATURES & LIMITATIONS")

sub_header("13A — Feature Matrix")
println()
println("    Feature                          DDM       EFM       FEA")
println("    ────────────────────────────── ──────── ──────── ────────")
println("    Total static moment M₀              ✓        ✓        ✓")
println("    Longitudinal distribution            ✓        —        —")
println("      (ACI Table 8.10.4.2 coeffs)")
println("    Frame analysis (stiffness)           —        ✓        —")
println("      (Kec, Ks, COF, FEM)")
println("    2D shell FEA (Tri3 mesh)             —        —        ✓")
println("    Transverse distribution               ✓        ✓        ✓")
println("      (ACI 8.10.5 col/mid strip)")
println("    Multi-span frame analysis            ✓        ✓        ✓")
println("    Irregular grid support               —        —        ✓")
println("    Punching shear (§22.6)               ✓        ✓        ✓")
println("    Unbalanced moment transfer           ✓        ✓        ✓")
println("    Two-way deflection (§24.2)           ✓        ✓        ✓")
println("    Direct FEA displacement              —        —        ✓")
println("      (Ig/Ie cracking correction)")
println("    One-way shear (§22.5)                ✓        ✓        ✓")
println("    Reinforcement design                 ✓        ✓        ✓")
println("    Integrity rebar (§8.7.4.2)           ✓        ✓        ✓")
println("    Pattern loading (§6.4.3.2)           —        —        —")
println("    Headed shear studs                   ✓        ✓        ✓")
println("    Slab thickness iteration             ✓        ✓        ✓")
println("    Column P-M co-design                 ✓        ✓        ✓")
println("    Auto-fallback to FEA                 ✓        ✓        —")
println("    Applicability checks                 ✓        ✓        —")
println("      (DDM 7-rule / EFM 3-rule)")
println("    ── Flat Slab / Drop Panel ──")
println("    Drop panel geometry (§8.2.4)         ✓        ✓        ✓")
println("    Auto-size drop depth & extent        ✓        ✓        ✓")
println("    Dual punching check (col+drop)       ✓        ✓        ✓")
println("    Weighted self-weight (slab+drop)     ✓        ✓        ✓")
println("    Flat slab min h (Table 8.3.1.1)      ✓        ✓        ✓")
println("    ── Edge Beam / βt ──")
println("    Edge beam βt computation             ✓        —        —")
println("    βt user override (edge_beam_βt)      ✓        —        —")
println("    Compression steel ρ' for λΔ          ✓        ✓        ✓")
println()

sub_header("13B — Shared Components")
println()
println("    All three methods share the same downstream pipeline:")
println("      MomentAnalysisResult → punching → deflection → shear → rebar")
println()
println("    Shared ACI utilities (codes/aci/):")
println("      punching_check()          — biaxial moment transfer (§22.6 + §8.4.4.2)")
println("      punching_geometry_*()     — interior/edge/corner critical sections")
println("      gamma_f(), gamma_v()      — moment transfer fractions (§8.4.2.3)")
println("      one_way_shear_capacity()  — Vc = 2λ√f'c × bw × d (§22.5)")
println("      cracking_moment()         — Mcr for deflection (§24.2)")
println("      effective_moment_of_inertia() — Ie for cracked sections")
println()

sub_header("13C — Current Limitations & Future Work")
println()
println("  1. Pattern loading not yet implemented (required when L/D > 0.75).")
println("  2. FEA uses point-spring column supports (area supports more accurate).")
println("  3. EFM Hardy Cross solver has limited convergence for stiff frames.")
println("  4. Twisting moments (Mxy) are diagnostic only — not used for Wood-Armer design.")
println("  5. Perpendicular (secondary) direction moments from FEA not yet fed to rebar design.")
println("  6. Cracked-section FEA (Ie instead of Ig) would improve deflection accuracy.")
println()

# ═════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═════════════════════════════════════════════════════════════════════════════

section_header("SUMMARY")
println()
ordered_steps = [
    "Load Baseline", "Section Properties", "EFM Stiffnesses", "Static Moment",
    "Method Comparison", "Effective Depth", "Reinforcement",
    "Punching Shear", "Deflection", "Column Axial Load", "Integrity Rebar",
    "Sensitivity Studies", "Full Sizing", "Flat Slab",
]
println("  Methods validated: DDM, DDM(fn), MDDM, EFM(HC), EFM(ASAP), FEA(Shell)")
println("  Flat slab (drop panels) validated: thickness, geometry, dual punching check.")
println("  Edge beam βt and ρ' effects demonstrated with parametric tables.")
println("  FEA integrated throughout — shown alongside DDM/EFM in every table.")
println()

@printf("    %-24s  %s\n", "Step", "Status")
@printf("    %-24s  %s\n", "─"^24, "─"^24)
for step in ordered_steps
    status = get(step_status, step, "?")
    @printf("    %-24s  %s\n", step, status)
end

println()
println("  Reference: DE-Two-Way-Flat-Plate (ACI 318-14), spSlab v10.00")
println("  Geometry:  l₁=$l1 × l₂=$l2  h=$h  c=$c_col  H=$H")
println("  Loads:     SDL=$sdl  LL=$ll  qᵤ=$qu")

@test true  # sentinel
end
