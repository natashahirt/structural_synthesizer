# =============================================================================
# Test: Shear Stud Catalogs — StudSpec, INCON ISS, Ancon Shearfix, snap_to_catalog
# =============================================================================
#
# Verifies:
#   1. Catalog data matches manufacturer specifications
#   2. snap_to_catalog returns correct products for various target diameters
#   3. Edge cases: exact match, between sizes, below smallest, above largest
#   4. stud_catalog() dispatch returns the correct catalog
#   5. Cross-unit consistency (metric Ancon studs used in imperial calcs)
#
# Sources:
#   INCON ISS — INCON-ISS-Shear-Studs-Catalog.pdf, Page 7 (Imperial table)
#   Ancon Shearfix — Shearfix_Punching_Shear_Reinforcement.pdf, p.3
# =============================================================================

using Test
using Unitful
using Unitful: @u_str
using StructuralSizer

# Aliases for internal symbols
const SS = StructuralSizer

# =============================================================================
# INCON ISS Catalog — Physical Dimensions (Imperial)
# =============================================================================
@testset "INCON ISS Catalog Dimensions" begin
    catalog = SS.INCON_ISS_CATALOG

    # Catalog should have exactly 5 sizes: 3/8", 1/2", 5/8", 3/4", 7/8"
    @test length(catalog) == 5

    # ─── 3/8" stud ───
    s = catalog[1]
    @test s.catalog === :incon_iss
    @test ustrip(u"inch", s.shank_diameter) ≈ 0.375 atol=1e-4
    @test ustrip(u"inch", s.head_diameter)  ≈ 1.000 atol=1e-4
    @test ustrip(u"inch", s.head_thickness) ≈ 0.1875 atol=1e-4
    # Catalog states head_area = 0.11 in² (shank cross-sectional area)
    @test ustrip(u"inch^2", s.head_area) ≈ 0.11 atol=0.005

    # ─── 1/2" stud ───
    s = catalog[2]
    @test ustrip(u"inch", s.shank_diameter) ≈ 0.500 atol=1e-4
    @test ustrip(u"inch", s.head_diameter)  ≈ 1.250 atol=1e-4
    @test ustrip(u"inch", s.head_thickness) ≈ 0.250 atol=1e-4
    @test ustrip(u"inch^2", s.head_area) ≈ 0.20 atol=0.005

    # ─── 5/8" stud ───
    s = catalog[3]
    @test ustrip(u"inch", s.shank_diameter) ≈ 0.625 atol=1e-4
    @test ustrip(u"inch", s.head_diameter)  ≈ 1.500 atol=1e-4
    @test ustrip(u"inch", s.head_thickness) ≈ 0.3125 atol=1e-4
    @test ustrip(u"inch^2", s.head_area) ≈ 0.31 atol=0.005

    # ─── 3/4" stud ───
    s = catalog[4]
    @test ustrip(u"inch", s.shank_diameter) ≈ 0.750 atol=1e-4
    @test ustrip(u"inch", s.head_diameter)  ≈ 1.750 atol=1e-4
    @test ustrip(u"inch", s.head_thickness) ≈ 0.375 atol=1e-4
    @test ustrip(u"inch^2", s.head_area) ≈ 0.44 atol=0.005

    # ─── 7/8" stud ───
    s = catalog[5]
    @test ustrip(u"inch", s.shank_diameter) ≈ 0.875 atol=1e-4
    @test ustrip(u"inch", s.head_diameter)  ≈ 2.000 atol=1e-4
    @test ustrip(u"inch", s.head_thickness) ≈ 0.4375 atol=1e-4
    @test ustrip(u"inch^2", s.head_area) ≈ 0.60 atol=0.005

    # ─── INCON areas differ from π d²/4 (they are catalog-specific values) ───
    # 3/8" stud: π(0.375)²/4 ≈ 0.1104 ≈ 0.11 ✓
    # 1/2" stud: π(0.500)²/4 ≈ 0.1963 ≈ 0.20 ✓ (catalog rounds up)
    # 7/8" stud: π(0.875)²/4 ≈ 0.6013 ≈ 0.60 ✓
    for s in catalog
        d_in = ustrip(u"inch", s.shank_diameter)
        generic_area = π * d_in^2 / 4
        catalog_area = ustrip(u"inch^2", s.head_area)
        # INCON areas should be within ~5% of π d²/4 (they round to 2 decimals)
        @test abs(catalog_area - generic_area) / generic_area < 0.06
    end
end

# =============================================================================
# Ancon Shearfix Catalog — Physical Dimensions (Metric)
# =============================================================================
@testset "Ancon Shearfix Catalog Dimensions" begin
    catalog = SS.ANCON_SHEARFIX_CATALOG

    # Catalog should have 6 sizes: 10, 12, 14, 16, 20, 25 mm
    @test length(catalog) == 6

    expected_diameters_mm = [10.0, 12.0, 14.0, 16.0, 20.0, 25.0]

    for (i, d_mm) in enumerate(expected_diameters_mm)
        s = catalog[i]
        @test s.catalog === :ancon_shearfix

        # Shank diameter matches
        @test ustrip(u"mm", s.shank_diameter) ≈ d_mm atol=0.01

        # Head diameter = 3× shank per Shearfix spec
        @test ustrip(u"mm", s.head_diameter) ≈ 3.0 * d_mm atol=0.01

        # Head thickness ≈ 0.5× shank (assumed standard practice)
        @test ustrip(u"mm", s.head_thickness) ≈ 0.5 * d_mm atol=0.01

        # Head area = π d²/4 (generic formula for Ancon)
        expected_area_mm2 = π * d_mm^2 / 4
        @test ustrip(u"mm^2", s.head_area) ≈ expected_area_mm2 atol=0.1
    end

    # ─── Cross-unit check: Ancon 12mm ≈ 0.472" shank ───
    s12 = catalog[2]
    @test ustrip(u"inch", s12.shank_diameter) ≈ 0.4724 atol=0.001
    # Area in imperial: π(12mm)²/4 ≈ 113.1 mm² ≈ 0.1753 in²
    @test ustrip(u"inch^2", s12.head_area) ≈ 0.1753 atol=0.001
end

# =============================================================================
# Generic Catalog — π d²/4 Areas
# =============================================================================
@testset "Generic Stud Catalog" begin
    catalog = SS.GENERIC_STUD_CATALOG

    # Same 5 sizes as INCON
    @test length(catalog) == 5

    for s in catalog
        @test s.catalog === :generic
        d_in = ustrip(u"inch", s.shank_diameter)
        # Generic uses exact π d²/4
        @test ustrip(u"inch^2", s.head_area) ≈ π * d_in^2 / 4 atol=1e-6
    end

    # Generic and INCON should have same shank diameters
    for (g, i) in zip(catalog, SS.INCON_ISS_CATALOG)
        @test ustrip(u"inch", g.shank_diameter) ≈ ustrip(u"inch", i.shank_diameter) atol=1e-6
    end
end

# =============================================================================
# stud_catalog() Dispatch
# =============================================================================
@testset "stud_catalog() Dispatch" begin
    # Each reinforcement symbol returns the correct catalog
    @test SS.stud_catalog(:headed_studs_incon) === SS.INCON_ISS_CATALOG
    @test SS.stud_catalog(:headed_studs_ancon) === SS.ANCON_SHEARFIX_CATALOG
    @test SS.stud_catalog(:headed_studs_generic) === SS.GENERIC_STUD_CATALOG

    # Unknown symbol throws
    @test_throws ErrorException SS.stud_catalog(:unknown_product)
    @test_throws ErrorException SS.stud_catalog(:shear_caps)
end

# =============================================================================
# snap_to_catalog() — Selection Logic
# =============================================================================
@testset "snap_to_catalog — Exact Match" begin
    catalog = SS.INCON_ISS_CATALOG

    # Exact match: requesting 1/2" should return the 1/2" stud
    spec = SS.snap_to_catalog(catalog, 0.5u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.500 atol=1e-4
    @test ustrip(u"inch^2", spec.head_area) ≈ 0.20 atol=0.005

    # Exact match: 3/8"
    spec = SS.snap_to_catalog(catalog, 0.375u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.375 atol=1e-4

    # Exact match: 7/8"
    spec = SS.snap_to_catalog(catalog, 0.875u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.875 atol=1e-4
end

@testset "snap_to_catalog — Snap Up to Next Size" begin
    catalog = SS.INCON_ISS_CATALOG

    # Requesting 0.45" (between 3/8" and 1/2") → should snap up to 1/2"
    spec = SS.snap_to_catalog(catalog, 0.45u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.500 atol=1e-4

    # Requesting 0.55" (between 1/2" and 5/8") → should snap up to 5/8"
    spec = SS.snap_to_catalog(catalog, 0.55u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.625 atol=1e-4

    # Requesting 0.80" (between 3/4" and 7/8") → should snap up to 7/8"
    spec = SS.snap_to_catalog(catalog, 0.80u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.875 atol=1e-4
end

@testset "snap_to_catalog — Below Smallest" begin
    catalog = SS.INCON_ISS_CATALOG

    # Requesting 0.25" (below smallest 3/8") → should return 3/8"
    spec = SS.snap_to_catalog(catalog, 0.25u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.375 atol=1e-4

    # Requesting 0" → should return smallest
    spec = SS.snap_to_catalog(catalog, 0.0u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.375 atol=1e-4
end

@testset "snap_to_catalog — Above Largest (Fallback)" begin
    catalog = SS.INCON_ISS_CATALOG

    # Requesting 1.0" (above largest 7/8") → should return 7/8" (largest)
    spec = SS.snap_to_catalog(catalog, 1.0u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.875 atol=1e-4

    # Requesting 2.0" → still returns largest
    spec = SS.snap_to_catalog(catalog, 2.0u"inch")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.875 atol=1e-4
end

@testset "snap_to_catalog — Metric Target on Imperial Catalog" begin
    catalog = SS.INCON_ISS_CATALOG

    # 12mm ≈ 0.472" → should snap up to 1/2" (0.500")
    spec = SS.snap_to_catalog(catalog, 12.0u"mm")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.500 atol=1e-4

    # 16mm ≈ 0.630" → should snap up to 3/4" (0.750")
    spec = SS.snap_to_catalog(catalog, 16.0u"mm")
    @test ustrip(u"inch", spec.shank_diameter) ≈ 0.750 atol=1e-4
end

@testset "snap_to_catalog — Imperial Target on Metric Catalog" begin
    catalog = SS.ANCON_SHEARFIX_CATALOG

    # 1/2" = 12.7mm → should snap up to 14mm
    spec = SS.snap_to_catalog(catalog, 0.5u"inch")
    @test ustrip(u"mm", spec.shank_diameter) ≈ 14.0 atol=0.01

    # 3/8" = 9.525mm → should snap up to 10mm
    spec = SS.snap_to_catalog(catalog, 0.375u"inch")
    @test ustrip(u"mm", spec.shank_diameter) ≈ 10.0 atol=0.01

    # 7/8" = 22.225mm → should snap up to 25mm
    spec = SS.snap_to_catalog(catalog, 0.875u"inch")
    @test ustrip(u"mm", spec.shank_diameter) ≈ 25.0 atol=0.01
end

# =============================================================================
# StudSpec — Display / Show
# =============================================================================
@testset "StudSpec Show Method" begin
    s = SS.INCON_ISS_CATALOG[2]
    str = sprint(show, s)
    @test occursin("incon_iss", str)
    @test occursin("0.5", str)
end

# =============================================================================
# Catalog Ordering — Monotonically Increasing Diameters
# =============================================================================
@testset "Catalog Ordering" begin
    for (name, catalog) in [
        ("INCON", SS.INCON_ISS_CATALOG),
        ("Ancon", SS.ANCON_SHEARFIX_CATALOG),
        ("Generic", SS.GENERIC_STUD_CATALOG),
    ]
        diameters = [ustrip(u"inch", s.shank_diameter) for s in catalog]
        @test issorted(diameters) || @warn "$name catalog is not sorted by diameter"
        # All diameters positive
        @test all(d -> d > 0, diameters)
        # All areas positive
        areas = [ustrip(u"inch^2", s.head_area) for s in catalog]
        @test all(a -> a > 0, areas)
        # Areas should increase with diameter
        @test issorted(areas) || @warn "$name catalog areas not monotonically increasing"
    end
end

println("\n✅ All stud catalog tests completed!")
