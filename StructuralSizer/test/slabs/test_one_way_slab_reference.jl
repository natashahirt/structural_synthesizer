# =============================================================================
# Reference Tests for One-Way Slab Design
# NOT INCLUDED IN runtests.jl - Standalone verification against StructurePoint
#
# IMPORTANT: These tests validate against published reference values.
# DO NOT MODIFY without verifying against source document.
#
# Source: DE-One-Way-Slab-ACI-14-spBeam-v1000.pdf
# Version: October-07-2025
# =============================================================================
#
# REFERENCE PROBLEM STATEMENT
# ===========================
# A continuous one-way slab spanning 15 ft (c/c) with:
# - Exterior support width: 16 in
# - Interior support width: 14 in  
# - f'c = 4,000 psi (normal weight, wc = 150 pcf)
# - fy = 60,000 psi
# - SDL = 20 psf (floor covering, ceiling, MEP)
# - LL = 80 psf (including partitions)
# - Clear cover = 0.75 in (ACI Table 20.6.1.3.1)
# - #4 bars for reinforcement
#
# KEY RESULTS FROM SOURCE (pg. 6-11):
# - Slab thickness: h = 7 in
# - End bay h_min = ln/24 = 7.17 in (ACI Table 7.3.1.1)
# - Interior bay h_min = ln/28 = 6.43 in
# - Effective depth: d = 6.00 in
# - wu = 257.00 psf
# - First interior negative Mu = 4.65 k-ft/ft
# - As,req = 0.176 in²/ft, As,min = 0.151 in²/ft
# =============================================================================

using Test
using Unitful
using Unitful: @u_str

# =============================================================================
# VERIFIED REFERENCE DATA
# Extracted directly from StructurePoint DE-One-Way-Slab-ACI-14-spBeam-v1000.pdf
# =============================================================================

"""
Reference data from StructurePoint One-Way Slab Design Example.
All values verified against source document.
"""
const ONE_WAY_SLAB_STRUCTUREPOINT = (
    # ===== GEOMETRY =====
    geometry = (
        span_cc = 15.0,           # ft - center-to-center span
        support_exterior = 16.0,  # in - exterior support width  
        support_interior = 14.0,  # in - interior support width
        h = 7.0,                  # in - slab thickness (selected)
        d = 6.00,                 # in - effective depth
        cover = 0.75,             # in - clear cover
        bar_diam = 0.50,          # in - #4 bar diameter
    ),

    # ===== CLEAR SPANS (from pg. 8) =====
    clear_spans = (
        # ln = span - support1/2 - support2/2
        # Exterior: ln = 15.0 - 16/(2×12) - 14/(2×12) = 13.08 ft
        ln_exterior = 13.08,      # ft - clear span for end spans
        # Interior: ln = 15.0 - 14/(2×12) - 14/(2×12) = 13.83 ft
        ln_interior = 13.83,      # ft - clear span for interior spans
        # Average: (13.08 + 13.83) / 2 = 13.46 ft (used for first interior support)
        ln_average = 13.46,       # ft - average clear span
    ),

    # ===== MATERIALS =====
    materials = (
        fc = 4000.0,              # psi - concrete compressive strength
        fy = 60000.0,             # psi - steel yield strength
        wc = 150.0,               # pcf - concrete unit weight
        β1 = 0.85,                # stress block factor for f'c ≤ 4000 psi
    ),

    # ===== LOADS (from pg. 7) =====
    loads = (
        self_weight = 87.50,      # psf - 7/12 × 150
        sdl = 20.0,               # psf - superimposed dead load
        ll = 80.0,                # psf - live load
        D = 107.50,               # psf - total dead load (sw + sdl)
        # wu = 1.2D + 1.6L = 1.2(107.50) + 1.6(80) = 257.00 psf
        wu = 257.00,              # psf - factored load (governs)
        # Alternative: 1.4D = 1.4(107.50) = 150.50 psf (does not govern)
        wu_alt = 150.50,          # psf - alternative load case
    ),

    # ===== MINIMUM THICKNESS (from pg. 6) =====
    # ACI 318-14 Table 7.3.1.1 for solid one-way slabs
    thickness_limits = (
        # End bay (one end continuous): h_min = ln/24
        # h_min = (15×12 - 16/2)/24 = 172/24 = 7.17 in
        h_min_end_bay = 7.17,     # in
        # Interior bay (both ends continuous): h_min = ln/28
        # h_min = 180/28 = 6.43 in
        h_min_interior_bay = 6.43, # in
    ),

    # ===== DESIGN MOMENTS (from pg. 8, Table 1) =====
    # All moments in kip-ft per foot of width
    # Using ACI 318-14 moment coefficients (Table 6.5.2)
    design_moments = (
        # End Spans (ln = 13.08 ft):
        # Exterior support negative: wu×ln²/24
        M_ext_neg = 1.83,         # k-ft/ft = 0.257 × 13.08² / 24
        # Mid-span positive: wu×ln²/14
        M_end_pos = 3.14,         # k-ft/ft = 0.257 × 13.08² / 14
        # Interior support negative: wu×ln_avg²/10
        M_first_int_neg = 4.65,   # k-ft/ft = 0.257 × 13.46² / 10
        
        # Interior Spans (ln = 13.83 ft):
        # Mid-span positive: wu×ln²/16
        M_int_pos = 3.07,         # k-ft/ft = 0.257 × 13.83² / 16
        # Support negative: wu×ln²/11
        M_int_neg = 4.47,         # k-ft/ft = 0.257 × 13.83² / 11
    ),

    # ===== ACI MOMENT COEFFICIENTS (Table 6.5.2) =====
    moment_coefficients = (
        ext_neg = 1/24,           # Exterior support negative (end span)
        end_pos = 1/14,           # Positive moment (end span)
        first_int_neg = 1/10,     # First interior support negative
        int_pos = 1/16,           # Positive moment (interior span)
        int_neg = 1/11,           # Interior support negative
    ),

    # ===== DESIGN SHEAR (from pg. 8, Table 2) =====
    # All shear values in kips per foot of width
    # Using ACI 318-14 shear coefficients (Table 6.5.3)
    design_shear = (
        # End span at first interior: 1.15 × wu × ln / 2
        Vu_first_interior = 1.93, # k/ft = 1.15 × 0.257 × 13.08 / 2
        # Exterior span at other supports: wu × ln / 2
        Vu_exterior = 1.68,       # k/ft = 0.257 × 13.08 / 2
        # Interior span: wu × ln / 2
        Vu_interior = 1.78,       # k/ft = 0.257 × 13.83 / 2
    ),

    # ===== REINFORCEMENT DESIGN (from pg. 10-11) =====
    # For first interior support negative (Mu = 4.65 k-ft/ft)
    reinforcement = (
        # As = Mu / (fy × jd × φ) = 4.65×12000 / (60000 × 5.87 × 0.9)
        jd_assumed = 5.87,        # in - assumed lever arm (0.978d)
        As_calc = 0.176,          # in²/ft - calculated steel area
        
        # Recalculated with actual a:
        a_calc = 0.259,           # in - stress block depth
        c_calc = 0.305,           # in - neutral axis depth (a/β1)
        εt_calc = 0.056,          # in/in - tensile strain (≥ 0.005 → tension-controlled)
        
        # Minimum reinforcement (ACI Table 7.6.1.1)
        # As,min = 0.0018 × Ag = 0.0018 × 12 × 7 = 0.151 in²/ft
        # (using 0.0018 for fy = 60 ksi)
        As_min = 0.151,           # in²/ft
        
        # Provided: #4 @ 12"
        As_provided = 0.20,       # in²/ft
        bar_spacing = 12.0,       # in
        
        # Maximum spacing: min(3h, 18") = min(21, 18) = 18"
        s_max = 18.0,             # in (ACI 7.7.2.3)
    ),

    # ===== INTERMEDIATE CALCULATIONS =====
    intermediate = (
        # For exterior span positive (Mu = 3.14 k-ft/ft)
        ext_pos = (
            jd = 5.91,            # in
            As_calc = 0.118,      # in²/ft
            a = 0.174,            # in
            c = 0.204,            # in
            εt = 0.085,           # in/in
        ),
    ),
)

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

@testset "One-Way Slab Reference Tests (StructurePoint)" begin
    data = ONE_WAY_SLAB_STRUCTUREPOINT
    
    @testset "Geometry Verification" begin
        # Effective depth: d = h - cover - db/2
        d_calc = data.geometry.h - data.geometry.cover - data.geometry.bar_diam / 2
        @test d_calc ≈ data.geometry.d rtol=0.01
        
        # Clear span exterior: span - full_exterior_support - interior_support/2
        # Note: At exterior edge, slab extends only to support face (full deduction)
        # At interior edge, slab is continuous (half deduction)
        # ln = 15.0 - 16/12 - 14/(2×12) = 15.0 - 1.333 - 0.583 = 13.08 ft
        ln_ext = data.geometry.span_cc - 
                 data.geometry.support_exterior / 12 - 
                 data.geometry.support_interior / (2 * 12)
        @test ln_ext ≈ data.clear_spans.ln_exterior rtol=0.01
        
        # Clear span interior: span - interior_support/2 - interior_support/2
        # ln = 15.0 - 14/(2×12) - 14/(2×12) = 15.0 - 0.583 - 0.583 = 13.83 ft
        ln_int = data.geometry.span_cc - 
                 2 * data.geometry.support_interior / (2 * 12)
        @test ln_int ≈ data.clear_spans.ln_interior rtol=0.01
        
        # Average clear span
        ln_avg = (data.clear_spans.ln_exterior + data.clear_spans.ln_interior) / 2
        @test ln_avg ≈ data.clear_spans.ln_average rtol=0.01
    end
    
    @testset "Minimum Thickness (ACI Table 7.3.1.1)" begin
        # End bay: h_min = ln/24
        ln_end_in = data.geometry.span_cc * 12 - data.geometry.support_exterior / 2
        h_min_end = ln_end_in / 24
        @test h_min_end ≈ data.thickness_limits.h_min_end_bay rtol=0.01
        
        # Interior bay: h_min = ln/28
        ln_int_in = data.geometry.span_cc * 12
        h_min_int = ln_int_in / 28
        @test h_min_int ≈ data.thickness_limits.h_min_interior_bay rtol=0.02
        
        # Selected thickness satisfies minimum (barely)
        @test data.geometry.h < data.thickness_limits.h_min_end_bay
        # Note: Document states "slightly below 7.17 in." and requires deflection check
    end
    
    @testset "Factored Loads" begin
        # Self-weight: h/12 × wc
        sw = (data.geometry.h / 12) * data.materials.wc
        @test sw ≈ data.loads.self_weight rtol=0.01
        
        # Total dead: sw + sdl
        D = sw + data.loads.sdl
        @test D ≈ data.loads.D rtol=0.01
        
        # Factored load: 1.2D + 1.6L (governs)
        wu = 1.2 * D + 1.6 * data.loads.ll
        @test wu ≈ data.loads.wu rtol=0.01
        
        # Alternative: 1.4D
        wu_alt = 1.4 * D
        @test wu_alt ≈ data.loads.wu_alt rtol=0.01
        
        # Verify 1.2D + 1.6L governs
        @test data.loads.wu > data.loads.wu_alt
    end
    
    @testset "Design Moments (ACI Table 6.5.2)" begin
        wu_ksf = data.loads.wu / 1000  # Convert to ksf
        ln_ext = data.clear_spans.ln_exterior
        ln_int = data.clear_spans.ln_interior
        ln_avg = data.clear_spans.ln_average
        
        # Exterior support negative: wu × ln² / 24
        M_ext_neg = wu_ksf * ln_ext^2 / 24
        @test M_ext_neg ≈ data.design_moments.M_ext_neg rtol=0.02
        
        # End span positive: wu × ln² / 14
        M_end_pos = wu_ksf * ln_ext^2 / 14
        @test M_end_pos ≈ data.design_moments.M_end_pos rtol=0.02
        
        # First interior support negative: wu × ln_avg² / 10
        M_first_int_neg = wu_ksf * ln_avg^2 / 10
        @test M_first_int_neg ≈ data.design_moments.M_first_int_neg rtol=0.02
        
        # Interior span positive: wu × ln² / 16
        M_int_pos = wu_ksf * ln_int^2 / 16
        @test M_int_pos ≈ data.design_moments.M_int_pos rtol=0.02
        
        # Interior support negative: wu × ln² / 11
        M_int_neg = wu_ksf * ln_int^2 / 11
        @test M_int_neg ≈ data.design_moments.M_int_neg rtol=0.02
    end
    
    @testset "Design Shear (ACI Table 6.5.3)" begin
        wu_ksf = data.loads.wu / 1000
        ln_ext = data.clear_spans.ln_exterior
        ln_int = data.clear_spans.ln_interior
        
        # End span at first interior: 1.15 × wu × ln / 2
        Vu_first = 1.15 * wu_ksf * ln_ext / 2
        @test Vu_first ≈ data.design_shear.Vu_first_interior rtol=0.02
        
        # Exterior span at other supports: wu × ln / 2
        Vu_ext = wu_ksf * ln_ext / 2
        @test Vu_ext ≈ data.design_shear.Vu_exterior rtol=0.02
        
        # Interior span: wu × ln / 2
        Vu_int = wu_ksf * ln_int / 2
        @test Vu_int ≈ data.design_shear.Vu_interior rtol=0.02
    end
    
    @testset "Reinforcement Design" begin
        fc = data.materials.fc
        fy = data.materials.fy
        β1 = data.materials.β1
        b = 12.0  # in (unit strip)
        d = data.geometry.d
        h = data.geometry.h
        
        # Minimum reinforcement (ACI Table 7.6.1.1)
        # For fy = 60 ksi: As,min = 0.0018 × b × h
        As_min = 0.0018 * b * h
        @test As_min ≈ data.reinforcement.As_min rtol=0.01
        
        # Maximum spacing: min(3h, 18")
        s_max = min(3 * h, 18.0)
        @test s_max ≈ data.reinforcement.s_max rtol=0.01
        
        # Provided spacing satisfies maximum
        @test data.reinforcement.bar_spacing ≤ data.reinforcement.s_max
        
        # Provided area satisfies required
        @test data.reinforcement.As_provided ≥ data.reinforcement.As_calc
        @test data.reinforcement.As_provided ≥ data.reinforcement.As_min
    end
    
    @testset "Tension-Controlled Verification" begin
        # From document: εt = 0.056 > 0.005 → tension-controlled
        @test data.reinforcement.εt_calc > 0.005
        
        # φ = 0.9 for tension-controlled
        @test data.reinforcement.εt_calc ≥ 0.005
    end
    
    @testset "Stress Block Calculations" begin
        fc = data.materials.fc
        fy = data.materials.fy
        β1 = data.materials.β1
        b = 12.0
        d = data.geometry.d
        As = data.reinforcement.As_calc
        
        # Stress block depth: a = As × fy / (0.85 × f'c × b)
        a_calc = As * fy / (0.85 * fc * b)
        @test a_calc ≈ data.reinforcement.a_calc rtol=0.02
        
        # Neutral axis: c = a / β1
        c_calc = a_calc / β1
        @test c_calc ≈ data.reinforcement.c_calc rtol=0.02
        
        # Tensile strain: εt = 0.003 × (d - c) / c
        εt_calc = 0.003 * (d - c_calc) / c_calc
        @test εt_calc ≈ data.reinforcement.εt_calc rtol=0.05
    end
end

println("One-Way Slab Reference Tests completed.")
println("Note: These tests are NOT included in runtests.jl")
