using StructuralSynthesizer
using StructuralSizer
using Test
using Unitful
using Meshes

@testset "StructuralSynthesizer.jl" begin
    @testset "BuildingSkeleton" begin
        skel = BuildingSkeleton{Float64}()
        @test length(skel.vertices) == 0
        @test length(skel.edges) == 0
        
        p1 = Point(0.0, 0.0, 0.0)
        p2 = Point(5.0, 0.0, 0.0)
        idx1 = add_vertex!(skel, p1)
        idx2 = add_vertex!(skel, p2)
        @test idx1 == 1
        @test idx2 == 2
        @test length(skel.vertices) == 2
    end

    @testset "BuildingStructure" begin
        skel = BuildingSkeleton{Float64}()
        struc = BuildingStructure(skel)
        @test struc.skeleton === skel
        @test length(struc.slabs) == 0
    end

    @testset "Slab sizing by slab groups" begin
        # Build a minimal skeleton with two rectangular floor faces (Unitful geometry).
        skel = BuildingSkeleton{typeof(1.0u"m")}()

        # Face 1: 6m x 8m  -> short span = 6m
        f1 = Quadrangle(Point(0.0u"m", 0.0u"m", 0.0u"m"),
                        Point(6.0u"m", 0.0u"m", 0.0u"m"),
                        Point(6.0u"m", 8.0u"m", 0.0u"m"),
                        Point(0.0u"m", 8.0u"m", 0.0u"m"))

        # Face 2: 9m x 12m -> short span = 9m
        f2 = Quadrangle(Point(0.0u"m", 0.0u"m", 0.0u"m"),
                        Point(9.0u"m", 0.0u"m", 0.0u"m"),
                        Point(9.0u"m", 12.0u"m", 0.0u"m"),
                        Point(0.0u"m", 12.0u"m", 0.0u"m"))

        push!(skel.faces, f1)
        push!(skel.faces, f2)
        skel.groups_faces[:floor] = [1, 2]

        struc = BuildingStructure(skel)
        initialize_cells!(struc)

        @test length(struc.cells) == 2

        # Case A: both cells are in the same design group -> same result governed by short span = 9m
        initialize_slabs!(struc; floor_type=:one_way, slab_group_ids=[UInt64(1), UInt64(1)])
        @test length(struc.slabs) == 2

        expected = StructuralSizer.size_floor(StructuralSizer.OneWay(), 9.0u"m", struc.cells[2].sdl, struc.cells[2].live_load)
        h_expected = StructuralSizer.total_depth(expected)

        @test thickness(struc.slabs[1]) == h_expected
        @test thickness(struc.slabs[2]) == h_expected
        @test struc.cells[1].self_weight == StructuralSizer.self_weight(expected)
        @test struc.cells[2].self_weight == StructuralSizer.self_weight(expected)

        # Case B: separate design groups -> each cell sized off its own short span
        initialize_slabs!(struc; floor_type=:one_way, slab_group_ids=[UInt64(10), UInt64(20)])
        h1 = thickness(struc.slabs[1])
        h2 = thickness(struc.slabs[2])
        @test h2 >= h1
        @test h1 == StructuralSizer.total_depth(StructuralSizer.size_floor(StructuralSizer.OneWay(), 6.0u"m", struc.cells[1].sdl, struc.cells[1].live_load))
        @test h2 == StructuralSizer.total_depth(StructuralSizer.size_floor(StructuralSizer.OneWay(), 9.0u"m", struc.cells[2].sdl, struc.cells[2].live_load))
    end
end
