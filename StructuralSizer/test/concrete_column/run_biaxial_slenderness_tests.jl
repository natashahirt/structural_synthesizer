# Run biaxial and slenderness tests
using StructuralSizer
using Test

println("="^60)
println("Running Biaxial Bending Tests")
println("="^60)
include("test_biaxial.jl")

println("\n" * "="^60)
println("Running Slenderness Effects Tests")
println("="^60)
include("test_slenderness.jl")

println("\n" * "="^60)
println("All tests completed!")
println("="^60)
