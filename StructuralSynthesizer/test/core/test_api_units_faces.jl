using StructuralSynthesizer
using Test
using Unitful

@testset "API units and explicit faces" begin
    @testset "_to_display_length fails fast on non-length" begin
        du = DisplayUnits(:imperial)
        @test isapprox(StructuralSynthesizer._to_display_length(du, 1.0u"m"), 3.280839895; atol=1e-9)
        @test_throws ArgumentError StructuralSynthesizer._to_display_length(du, 1.0u"m^2")
    end

    @testset "Explicit face must map to existing edges" begin
        input = StructuralSynthesizer.APIInput(
            units = "m",
            vertices = [
                [0.0, 0.0, 0.0],
                [1.0, 0.0, 0.0],
                [1.0, 1.0, 0.0],
                [0.0, 1.0, 0.0],
            ],
            edges = StructuralSynthesizer.APIEdgeGroups(
                beams = [[1, 3]],   # diagonal only; no boundary edges for explicit face
                columns = Vector{Vector{Int}}(),
                braces = Vector{Vector{Int}}(),
            ),
            supports = Int[],
            faces = Dict(
                "floor" => [
                    [
                        [0.0, 0.0, 0.0],
                        [1.0, 0.0, 0.0],
                        [1.0, 1.0, 0.0],
                        [0.0, 1.0, 0.0],
                    ],
                ],
            ),
        )

        @test_throws ArgumentError json_to_skeleton(input)
    end
end
