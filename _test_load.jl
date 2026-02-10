println("Loading packages...")
t0 = time()
using StructuralSizer
using StructuralSynthesizer
using Asap
using Unitful
using Test
t1 = time()
println("Loaded in $(round(t1-t0, digits=1))s\n")

println("═"^60)
println("  StructuralSizer tests")
println("═"^60)
t2 = time()
include("StructuralSizer/test/runtests.jl")
t3 = time()
println("StructuralSizer done in $(round(t3-t2, digits=1))s\n")

println("═"^60)
println("  StructuralSynthesizer tests")
println("═"^60)
t4 = time()
include("StructuralSynthesizer/test/runtests.jl")
t5 = time()
println("StructuralSynthesizer done in $(round(t5-t4, digits=1))s\n")

println("═"^60)
println("  All tests complete! ($(round(t5-t0, digits=1))s total)")
println("═"^60)
