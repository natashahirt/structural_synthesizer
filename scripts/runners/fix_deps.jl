using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
println("Resolving dependencies...")
Pkg.resolve()
println("Instantiating...")
Pkg.instantiate()
println("Done!")
