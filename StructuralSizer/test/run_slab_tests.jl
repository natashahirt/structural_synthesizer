# Run slab-related tests
using Test

@testset "Slab Tests" begin
    include("slabs/test_flat_plate.jl")
    include("slabs/test_efm_stiffness.jl")
    include("slabs/test_efm_pipeline.jl")
    include("slabs/test_shear_transfer.jl")
end
