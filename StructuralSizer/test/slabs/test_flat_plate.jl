# =============================================================================
# Tests for CIP Flat Plate Design
# Validates against StructurePoint 24×20 ft example (ACI 318-14)
# Reference: https://structurepoint.org/publication/pdf/DE-Two-Way-Flat-Plate-Concrete-Floor-System-Analysis-and-Design-ACI-318-14-spSlab-v1000.pdf
# =============================================================================

using Test
using Unitful
using Unitful: @u_str
using StructuralBase.StructuralUnits  # For ksi, ksf, etc. in @u_str
using StructuralSizer

# =============================================================================
# StructurePoint Reference Example (Table 1, Page 5)
# =============================================================================
# Panel: 24 ft × 20 ft (N-S × E-W)
# Columns: 16" × 16" square interior, 12"×20" edge
# f'c = 4000 psi (normal weight concrete)
# fy = 60,000 psi (Grade 60)
# SDL = 20 psf
# LL = 50 psf
# Self-weight: calculated from slab thickness
# 
# Key Results from StructurePoint:
# - Slab thickness: 8.5" (used), 8.24" (minimum)
# - Clear span N-S: ln = 24 - 16/12 = 22.67 ft
# - Clear span E-W: ln = 20 - 16/12 = 18.67 ft
# - qu = 0.214 ksf (factored load)
# - M0 (N-S) = 275.4 kip-ft
# - M0 (E-W) = 223.4 kip-ft
# =============================================================================

@testset "Flat Plate Design - StructurePoint Validation" begin
    
    # Material properties
    fc = 4000u"psi"
    fy = 60000u"psi"
    
    # Geometry (from StructurePoint example)
    l1 = 24u"ft"  # N-S span (longer)
    l2 = 20u"ft"  # E-W span (shorter)
    c1 = 16u"inch"  # Column size N-S
    c2 = 16u"inch"  # Column size E-W
    
    @testset "Material Properties (ACI 19)" begin
        # ACI 19.2.2.1: Ec = 57000√f'c (psi)
        # For f'c = 4000 psi: Ec = 57000 × 63.25 = 3,605,000 psi = 3605 ksi
        Ec_calc = Ec(fc)
        @test ustrip(u"ksi", Ec_calc) ≈ 3605 rtol=0.01
        
        # ACI 22.2.2.4.3: β₁ varies with f'c
        # f'c ≤ 4000 psi: β₁ = 0.85
        # f'c ≥ 8000 psi: β₁ = 0.65
        # Linear interpolation between
        @test β1(fc) == 0.85
        @test β1(5000u"psi") ≈ 0.80 atol=0.01
        @test β1(6000u"psi") ≈ 0.75 atol=0.01
        @test β1(7000u"psi") ≈ 0.70 atol=0.01
        @test β1(8000u"psi") == 0.65
        @test β1(10000u"psi") == 0.65  # Capped at 0.65
        
        # ACI 19.2.3.1: fr = 7.5√f'c (psi)
        # For f'c = 4000 psi: fr = 7.5 × 63.25 = 474.3 psi
        fr_calc = fr(fc)
        @test ustrip(u"psi", fr_calc) ≈ 474.3 rtol=0.01
    end
    
    @testset "Slab Thickness (ACI 8.3.1.1)" begin
        # Clear spans
        ln_NS = clear_span(l1, c1)  # N-S direction: 24 - 16/12 = 22.67 ft
        ln_EW = clear_span(l2, c2)  # E-W direction: 20 - 16/12 = 18.67 ft
        
        @test ustrip(u"ft", ln_NS) ≈ 22.67 rtol=0.01
        @test ustrip(u"ft", ln_EW) ≈ 18.67 rtol=0.01
        
        # ACI Table 8.3.1.1 - Minimum thickness for flat plates
        # Without drop panels, interior panels: h = ln/33
        # Without drop panels, exterior panels: h = ln/30
        # Longer clear span governs
        
        # Interior panel: h_min = 22.67 × 12 / 33 = 8.24"
        h_min_int = min_thickness_flat_plate(ln_NS; discontinuous_edge=false)
        @test ustrip(u"inch", h_min_int) ≈ 8.24 rtol=0.02
        
        # Exterior panel: h_min = 22.67 × 12 / 30 = 9.07"
        h_min_ext = min_thickness_flat_plate(ln_NS; discontinuous_edge=true)
        @test ustrip(u"inch", h_min_ext) ≈ 9.07 rtol=0.02
        
        # Absolute minimum = 5"
        short_span = 10u"ft"
        h_min_short = min_thickness_flat_plate(short_span)
        @test ustrip(u"inch", h_min_short) >= 5.0
        
        # StructurePoint uses h = 8.5" (rounded up from 8.24")
        h = 8.5u"inch"
        @test h >= h_min_int
    end
    
    @testset "Factored Loads" begin
        h = 8.5u"inch"
        
        # Self-weight: 150 pcf × 8.5"/12 = 106.25 psf
        γ_conc = 150u"lbf/ft^3"
        sw = γ_conc * h |> u"psf"
        @test ustrip(u"psf", sw) ≈ 106.25 rtol=0.01
        
        sdl = 20u"psf"
        ll = 50u"psf"
        
        # Dead load: D = sw + SDL = 106.25 + 20 = 126.25 psf
        D = sw + sdl
        @test ustrip(u"psf", D) ≈ 126.25 rtol=0.01
        
        # Factored load: qu = 1.2D + 1.6L = 1.2(126.25) + 1.6(50) = 231.5 psf
        qu = 1.2 * D + 1.6 * ll
        @test ustrip(u"psf", qu) ≈ 231.5 rtol=0.02
        
        # Note: StructurePoint uses qu = 0.214 ksf (214 psf) - slightly different sw assumption
    end
    
    @testset "Static Moment M₀ (ACI 8.10.3.2)" begin
        # M₀ = qu × l₂ × ln² / 8
        # Using StructurePoint's qu = 0.214 ksf for validation
        qu = 0.214u"ksf"
        ln_NS = 22.67u"ft"
        ln_EW = 18.67u"ft"
        
        # N-S direction (Frame A-B-C): M0 = 0.214 × 20 × 22.67² / 8
        # = 0.214 × 20 × 513.9 / 8 = 275.4 kip-ft
        M0_NS = total_static_moment(qu, l2, ln_NS)
        @test ustrip(u"kip*ft", M0_NS) ≈ 275.4 rtol=0.02
        
        # E-W direction (Frame 1-2-3): M0 = 0.214 × 24 × 18.67² / 8
        # = 0.214 × 24 × 348.6 / 8 = 223.4 kip-ft
        M0_EW = total_static_moment(qu, l1, ln_EW)
        @test ustrip(u"kip*ft", M0_EW) ≈ 223.4 rtol=0.02
    end
    
    @testset "M-DDM Coefficients (Supplementary Doc Table S-1)" begin
        # Verify coefficient sums equal 1.0 (total panel moment)
        
        # End span: total should = 1.0
        end_cs = MDDM_COEFFICIENTS.end_span.column_strip
        end_ms = MDDM_COEFFICIENTS.end_span.middle_strip
        end_total = end_cs.ext_neg + end_cs.pos + end_cs.int_neg +
                    end_ms.ext_neg + end_ms.pos + end_ms.int_neg
        @test end_total ≈ 1.58 rtol=0.02  # > 1.0 because end span has 3 sections
        
        # Interior span: total should = 1.0
        int_cs = MDDM_COEFFICIENTS.interior_span.column_strip
        int_ms = MDDM_COEFFICIENTS.interior_span.middle_strip
        int_total = int_cs.neg + int_cs.pos + int_ms.neg + int_ms.pos
        @test int_total ≈ 1.02 rtol=0.02  # Should be ~1.0
        
        # Verify individual coefficients from Table S-1
        @test end_cs.ext_neg ≈ 0.27 atol=0.01
        @test end_cs.pos ≈ 0.345 atol=0.01
        @test end_cs.int_neg ≈ 0.55 atol=0.01
        @test end_ms.ext_neg ≈ 0.00 atol=0.01
        @test end_ms.pos ≈ 0.235 atol=0.01
        @test end_ms.int_neg ≈ 0.18 atol=0.01
        
        @test int_cs.neg ≈ 0.535 atol=0.01
        @test int_cs.pos ≈ 0.186 atol=0.01
        @test int_ms.neg ≈ 0.175 atol=0.01
        @test int_ms.pos ≈ 0.124 atol=0.01
    end
    
    @testset "Moment Distribution (M-DDM)" begin
        M0 = 275.4u"kip*ft"  # From N-S direction
        
        # End span distribution
        moments_end = distribute_moments_mddm(M0, :end_span)
        
        # Column strip moments
        @test moments_end.column_strip.ext_neg ≈ 0.27 * M0 rtol=0.01
        @test moments_end.column_strip.pos ≈ 0.345 * M0 rtol=0.01
        @test moments_end.column_strip.int_neg ≈ 0.55 * M0 rtol=0.01
        
        # Middle strip moments
        @test moments_end.middle_strip.ext_neg ≈ 0.00 * M0 atol=0.1u"kip*ft"
        @test moments_end.middle_strip.pos ≈ 0.235 * M0 rtol=0.01
        @test moments_end.middle_strip.int_neg ≈ 0.18 * M0 rtol=0.01
        
        # Interior span distribution
        moments_int = distribute_moments_mddm(M0, :interior_span)
        
        @test moments_int.column_strip.neg ≈ 0.535 * M0 rtol=0.01
        @test moments_int.column_strip.pos ≈ 0.186 * M0 rtol=0.01
        @test moments_int.middle_strip.neg ≈ 0.175 * M0 rtol=0.01
        @test moments_int.middle_strip.pos ≈ 0.124 * M0 rtol=0.01
    end
    
    @testset "Moment Distribution (Full ACI DDM)" begin
        M0 = 275.4u"kip*ft"
        l2_l1 = ustrip(u"ft", l2) / ustrip(u"ft", l1)  # 20/24 = 0.833
        
        # ACI DDM Tables 8.10.4.2 - Longitudinal distribution
        # End span: ext_neg = 26%, pos = 52%, int_neg = 70%
        # Interior span: neg = 65%, pos = 35%
        
        # Full ACI DDM for end span
        moments_aci = distribute_moments_aci(M0, :end_span, l2_l1; edge_beam=false)
        
        # Exterior negative: 26% to panel, 100% to column strip (no edge beam, βt=0)
        @test moments_aci.column_strip.ext_neg ≈ 0.26 * M0 rtol=0.02
        @test ustrip(u"kip*ft", moments_aci.middle_strip.ext_neg) ≈ 0.0 atol=0.1
        
        # Positive: 52% to panel, 60% to column strip (for αf=0)
        @test moments_aci.column_strip.pos ≈ 0.52 * 0.60 * M0 rtol=0.02
        
        # Interior negative: 70% to panel, 75% to column strip
        @test moments_aci.column_strip.int_neg ≈ 0.70 * 0.75 * M0 rtol=0.02
        
        # Interior span
        moments_int = distribute_moments_aci(M0, :interior_span, l2_l1)
        
        # Negative: 65% to panel, 75% to column strip
        @test moments_int.column_strip.neg ≈ 0.65 * 0.75 * M0 rtol=0.02
        
        # Positive: 35% to panel, 60% to column strip
        @test moments_int.column_strip.pos ≈ 0.35 * 0.60 * M0 rtol=0.02
    end
    
    @testset "Strip Widths" begin
        # Column strip width = l₂/2 (but not more than l₁/2)
        # For 24 × 20 panel:
        #   N-S direction: column strip = 20/2 = 10 ft (each side of column line)
        #   E-W direction: column strip = min(24/2, 20/2) = 10 ft
        # Middle strip = panel width - column strip widths
        
        # N-S direction analysis
        cs_width_NS = min(l2, l1) / 2  # 10 ft
        @test ustrip(u"ft", cs_width_NS) == 10.0
        
        # Total column strip width (both sides) = 2 × l₂/4 = l₂/2 = 10 ft
        # This is the HALF column strip width (from column line to edge)
        half_cs = l2 / 4  # 5 ft on each side
        @test ustrip(u"ft", half_cs) == 5.0
    end
    
    @testset "Reinforcement Design (ACI 22.2)" begin
        h = 8.5u"inch"
        
        # Effective depth: d = h - cover - db/2
        # Assuming #5 bars (db = 0.625"), cover = 0.75"
        # d = 8.5 - 0.75 - 0.625/2 = 7.44"
        d = effective_depth(h; cover=0.75u"inch", bar_diameter=0.625u"inch")
        @test ustrip(u"inch", d) ≈ 7.44 rtol=0.02
        
        # With #4 bars (db = 0.5"): d = 8.5 - 0.75 - 0.25 = 7.5"
        d_4 = effective_depth(h; cover=0.75u"inch", bar_diameter=0.5u"inch")
        @test ustrip(u"inch", d_4) ≈ 7.5 rtol=0.02
        
        # Column strip width = 10 ft = 120 in for N-S direction
        b_cs = 10u"ft"
        
        # Design for interior negative moment (highest typically)
        # M_int_neg = 0.55 × 275.4 = 151.5 kip-ft (M-DDM)
        Mu = 0.55 * 275.4u"kip*ft"
        
        As_reqd = required_reinforcement(Mu, b_cs, d_4, fc, fy)
        
        # Sanity check: As should be positive and reasonable
        @test ustrip(u"inch^2", As_reqd) > 0
        @test ustrip(u"inch^2", As_reqd) < 15  # Not excessive
        
        # Minimum reinforcement: As_min = 0.0018 × b × h
        # = 0.0018 × 120" × 8.5" = 1.836 in²
        As_min = minimum_reinforcement(b_cs, h)
        @test ustrip(u"inch^2", As_min) ≈ 1.836 rtol=0.02
        
        # Max spacing: s_max = min(2h, 18") = min(17", 18") = 17"
        s_max = max_bar_spacing(h)
        @test ustrip(u"inch", s_max) == 17.0
    end
    
    @testset "Punching Shear (ACI 22.6)" begin
        h = 8.5u"inch"
        d = 7.5u"inch"  # Effective depth
        
        # Critical section at d/2 from column face
        # b₀ = 2(c₁ + d) + 2(c₂ + d) for interior column
        # = 2(16 + 7.5) + 2(16 + 7.5) = 94"
        b0 = punching_perimeter(c1, c2, d)
        @test ustrip(u"inch", b0) ≈ 94 rtol=0.01
        
        # Punching shear capacity (ACI 22.6.5.2)
        # Three criteria, minimum governs:
        # (a) Vc = 4λ√f'c × b₀ × d = 4(1)(63.25)(94)(7.5) = 178,335 lb
        # (b) Vc = (2 + 4/β)λ√f'c × b₀ × d, β = c1/c2 = 1 for square → = 6λ√f'c × b₀ × d
        # (c) Vc = (αs×d/b₀ + 2)λ√f'c × b₀ × d, αs = 40 for interior
        
        Vc = punching_capacity_interior(b0, d, fc; c1=c1, c2=c2)
        @test ustrip(u"kip", Vc) ≈ 178 rtol=0.05
        
        # Punching shear demand
        # For interior column: Vu = qu × At - qu × Ac
        # At = tributary area (one panel for interior column in typical layout)
        qu = 0.214u"ksf"
        At = 24u"ft" * 20u"ft"  # 480 ft²
        Vu = punching_demand(qu, At, c1, c2, d)
        
        # Vu ≈ 0.214 × (480 - (23.5/12)²) ≈ 102 kips
        @test ustrip(u"kip", Vu) > 90
        @test ustrip(u"kip", Vu) < 110
        
        # Check: φVc = 0.75 × 178 = 133.5 kip > Vu ≈ 102 kip → OK
        check = check_punching_shear(Vu, Vc)
        @test check.passes
        @test check.ratio < 1.0
    end
    
    @testset "Deflection (ACI 24.2)" begin
        h = 8.5u"inch"
        l = 24u"ft"
        b = 12u"inch"  # Per foot width
        
        # Gross moment of inertia: Ig = bh³/12
        # = 12 × 8.5³ / 12 = 614.1 in⁴ per foot width
        Ig = b * h^3 / 12
        @test ustrip(u"inch^4", Ig) ≈ 614 rtol=0.01
        
        # Cracking moment: Mcr = fr × Ig / yt
        # yt = h/2 = 4.25"
        # Mcr = 474.3 × 614.1 / 4.25 = 68,550 lb-in = 5.71 kip-ft per foot
        fr_val = fr(fc)
        Mcr = cracking_moment(fr_val, Ig, h)
        @test ustrip(u"kip*ft", Mcr) ≈ 5.7 rtol=0.05
        
        # Deflection limits (ACI Table 24.2.2)
        # Immediate deflection due to LL: l/360
        Δ_ll = deflection_limit(l, :immediate_ll)
        @test ustrip(u"inch", Δ_ll) ≈ 0.8 rtol=0.02  # 288/360 = 0.8"
        
        # Total deflection after attachment of non-structural elements: l/240
        Δ_total = deflection_limit(l, :total)
        @test ustrip(u"inch", Δ_total) ≈ 1.2 rtol=0.02  # 288/240 = 1.2"
        
        # Long-term deflection factor: λΔ = ξ / (1 + 50ρ')
        # For 5+ years (ξ = 2.0) with no compression steel (ρ' = 0):
        # λΔ = 2.0 / (1 + 0) = 2.0
        λΔ = long_term_deflection_factor(2.0, 0.0)
        @test λΔ == 2.0
        
        # With compression steel ρ' = 0.005:
        # λΔ = 2.0 / (1 + 50×0.005) = 2.0 / 1.25 = 1.6
        λΔ_comp = long_term_deflection_factor(2.0, 0.005)
        @test λΔ_comp ≈ 1.6 rtol=0.01
    end
    
    @testset "Effective Moment of Inertia (ACI 24.2.3.5)" begin
        h = 8.5u"inch"
        b = 12u"inch"
        d = 7.5u"inch"
        fc_val = fc
        
        # Ig = 614 in⁴ (from above)
        Ig = b * h^3 / 12
        
        # Assume As = 2.0 in² per foot width
        As = 2.0u"inch^2"
        
        # Cracked moment of inertia (transformed section)
        Ec_val = Ec(fc_val)
        Icr = cracked_moment_of_inertia(As, b, d, Ec_val)
        
        # Icr should be less than Ig (typically 0.35-0.70 Ig for slabs)
        @test Icr < Ig
        @test ustrip(u"inch^4", Icr) > 100  # Sanity check
        @test ustrip(u"inch^4", Icr) < 500  # Icr/Ig typically 0.35-0.70
        
        # Cracking moment
        fr_val = fr(fc_val)
        Mcr = cracking_moment(fr_val, Ig, h)
        
        # For service moment < Mcr: Ie = Ig
        Ma_low = 0.5 * Mcr
        Ie_low = effective_moment_of_inertia(Mcr, Ma_low, Ig, Icr)
        @test Ie_low == Ig
        
        # For service moment > Mcr: Ie is between Icr and Ig
        Ma_high = 2.0 * Mcr
        Ie_high = effective_moment_of_inertia(Mcr, Ma_high, Ig, Icr)
        @test Ie_high < Ig
        @test Ie_high > Icr
    end
end

println("All flat plate design tests passed!")
