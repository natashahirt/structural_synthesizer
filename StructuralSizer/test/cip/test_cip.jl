using Test
using StructuralSizer
using StructuralBase
using Unitful: @u_str, ustrip, uconvert, unit

"""
Small regression tests for CIP slab sizing (ACI min thickness).

Design philosophy:
- Avoid exact numeric values (except code minima), focus on ordering/consistency.
- Exercise kwargs passthrough in `size_floor` (support, fy, has_edge_beam, etc.).
"""

@testset "CIP slabs (ACI min thickness)" begin
    span_m = 6.0u"m"
    sdl = 1.0u"kN/m^2"
    live = 2.0u"kN/m^2"

    # -------------------------------------------------------------------------
    # Smoke tests (all CIP subtypes)
    # -------------------------------------------------------------------------
    @testset "smoke" begin
        for st in (OneWay(), TwoWay(), FlatPlate(), FlatSlab(), PTBanded(), Waffle())
            r = size_floor(st, span_m, sdl, live; material=NWC_4000)
            @test r isa CIPSlabResult
            @test ustrip(u"inch", r.thickness) > 0
            @test ustrip(u"inch", r.volume_per_area) > 0
            @test ustrip(unit(sdl), r.self_weight) > 0
            @test unit(r.self_weight) == unit(sdl)
        end
    end

    # -------------------------------------------------------------------------
    # Code minima (short spans should hit the hard minimum thicknesses)
    # -------------------------------------------------------------------------
    @testset "minimum thickness floors" begin
        short_span = 0.5u"m"

        r1 = size_floor(OneWay(), short_span, sdl, live; material=NWC_4000)
        @test ustrip(u"inch", r1.thickness) ≥ 5.0

        for st in (TwoWay(), FlatPlate(), Waffle())
            r = size_floor(st, short_span, sdl, live; material=NWC_4000)
            @test ustrip(u"inch", r.thickness) ≥ 5.0
        end

        r_fs = size_floor(FlatSlab(), short_span, sdl, live; material=NWC_4000)
        @test ustrip(u"inch", r_fs.thickness) ≥ 4.0

        r_pt = size_floor(PTBanded(), short_span, sdl, live; material=NWC_4000, has_drop_panels=true)
        @test ustrip(u"inch", r_pt.thickness) ≥ 4.0
    end

    # -------------------------------------------------------------------------
    # Support-condition monotonicity (one-way)
    # -------------------------------------------------------------------------
    @testset "one-way support ordering" begin
        span = 8.0u"m"
        fy = 60.0 * StructuralBase.Constants.ksi

        h_cant = size_floor(OneWay(), span, sdl, live; material=NWC_4000, support=CANTILEVER, fy=fy).thickness
        h_simple = size_floor(OneWay(), span, sdl, live; material=NWC_4000, support=SIMPLE, fy=fy).thickness
        h_one = size_floor(OneWay(), span, sdl, live; material=NWC_4000, support=ONE_END_CONT, fy=fy).thickness
        h_both = size_floor(OneWay(), span, sdl, live; material=NWC_4000, support=BOTH_ENDS_CONT, fy=fy).thickness

        # Smaller divisors => larger thickness; cantilever should be thickest.
        @test ustrip(u"inch", h_cant) ≥ ustrip(u"inch", h_simple) ≥ ustrip(u"inch", h_one) ≥ ustrip(u"inch", h_both)
    end

    # -------------------------------------------------------------------------
    # Two-way panel type / edge beam effects
    # -------------------------------------------------------------------------
    @testset "two-way edge beam effects" begin
        span = 9.0u"m"
        fy = 60.0 * StructuralBase.Constants.ksi

        h_interior = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, support=BOTH_ENDS_CONT, fy=fy).thickness
        h_ext_with = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, support=SIMPLE, fy=fy, has_edge_beam=true).thickness
        h_ext_no = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, support=SIMPLE, fy=fy, has_edge_beam=false).thickness

        @test ustrip(u"inch", h_interior) ≤ ustrip(u"inch", h_ext_no)
        @test ustrip(u"inch", h_ext_with) ≤ ustrip(u"inch", h_ext_no)
    end

    # -------------------------------------------------------------------------
    # fy interpolation + clamping behavior (two-way)
    # -------------------------------------------------------------------------
    @testset "fy interpolation + clamping (two-way)" begin
        span = 10.0u"m"

        h40 = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, fy=40.0 * StructuralBase.Constants.ksi).thickness
        h50 = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, fy=50.0 * StructuralBase.Constants.ksi).thickness
        h60 = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, fy=60.0 * StructuralBase.Constants.ksi).thickness
        h80 = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, fy=80.0 * StructuralBase.Constants.ksi).thickness

        # In the ACI table used here, higher fy => smaller divisor => larger thickness.
        @test ustrip(u"inch", h40) < ustrip(u"inch", h50) < ustrip(u"inch", h60) < ustrip(u"inch", h80)

        h30 = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, fy=30.0 * StructuralBase.Constants.ksi).thickness
        h100 = size_floor(TwoWay(), span, sdl, live; material=NWC_4000, fy=100.0 * StructuralBase.Constants.ksi).thickness

        @test isapprox(ustrip(u"inch", h30), ustrip(u"inch", h40); atol=1e-9, rtol=0)
        @test isapprox(ustrip(u"inch", h100), ustrip(u"inch", h80); atol=1e-9, rtol=0)
    end

    # -------------------------------------------------------------------------
    # Unit robustness: equivalent spans produce equivalent thickness
    # -------------------------------------------------------------------------
    @testset "unit robustness" begin
        span1 = 6.0u"m"
        span2 = uconvert(u"ft", span1)

        r_m = size_floor(OneWay(), span1, sdl, live; material=NWC_4000)
        r_ft = size_floor(OneWay(), span2, sdl, live; material=NWC_4000)

        h_m_in = ustrip(u"inch", uconvert(u"inch", r_m.thickness))
        h_ft_in = ustrip(u"inch", uconvert(u"inch", r_ft.thickness))
        @test isapprox(h_m_in, h_ft_in; rtol=1e-10, atol=1e-8)
    end
end

