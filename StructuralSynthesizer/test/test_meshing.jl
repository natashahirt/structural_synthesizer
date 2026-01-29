using Test
using StructuralSynthesizer
using Meshes
using Unitful

@testset "Meshing Utilities" begin
    
    @testset "Quad Suitability" begin
        # Perfect rectangle
        rect = Meshes.Quadrangle(
            Meshes.Point(0.0, 0.0, 0.0),
            Meshes.Point(4.0, 0.0, 0.0),
            Meshes.Point(4.0, 3.0, 0.0),
            Meshes.Point(0.0, 3.0, 0.0)
        )
        @test StructuralSynthesizer.is_quad_suitable(rect)
        
        # Square
        sq = Meshes.Quadrangle(
            Meshes.Point(0.0, 0.0, 0.0),
            Meshes.Point(1.0, 0.0, 0.0),
            Meshes.Point(1.0, 1.0, 0.0),
            Meshes.Point(0.0, 1.0, 0.0)
        )
        @test StructuralSynthesizer.is_quad_suitable(sq)
        
        # Parallelogram (not suitable - angles not 90°)
        para = Meshes.Quadrangle(
            Meshes.Point(0.0, 0.0, 0.0),
            Meshes.Point(4.0, 0.0, 0.0),
            Meshes.Point(5.0, 3.0, 0.0),  # shifted
            Meshes.Point(1.0, 3.0, 0.0)
        )
        @test !StructuralSynthesizer.is_quad_suitable(para)
    end
    
    @testset "Triangulation" begin
        # Square should triangulate into 2 triangles
        sq = Meshes.Quadrangle(
            Meshes.Point(0.0, 0.0, 0.0),
            Meshes.Point(1.0, 0.0, 0.0),
            Meshes.Point(1.0, 1.0, 0.0),
            Meshes.Point(0.0, 1.0, 0.0)
        )
        
        tris = StructuralSynthesizer.triangulate_polygon_fan(sq)
        @test length(tris) == 2
        @test tris[1] == (1, 2, 3)
        @test tris[2] == (1, 3, 4)
        
        # Pentagon should triangulate into 3 triangles
        pent = Meshes.Ngon(
            Meshes.Point(0.0, 0.0, 0.0),
            Meshes.Point(1.0, 0.0, 0.0),
            Meshes.Point(1.5, 0.5, 0.0),
            Meshes.Point(1.0, 1.0, 0.0),
            Meshes.Point(0.0, 1.0, 0.0)
        )
        
        tris = StructuralSynthesizer.triangulate_polygon_fan(pent)
        @test length(tris) == 3
    end
    
    @testset "Element Spec" begin
        spec_tri = StructuralSynthesizer.ElementSpec(:tri3, [1, 2, 3])
        @test spec_tri.type == :tri3
        @test spec_tri.vertex_indices == [1, 2, 3]
        
        spec_quad = StructuralSynthesizer.ElementSpec(:quad4, [1, 2, 3, 4])
        @test spec_quad.type == :quad4
        @test spec_quad.vertex_indices == [1, 2, 3, 4]
    end
    
end
