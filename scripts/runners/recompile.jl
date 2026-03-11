using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))

# Force full recompile
pkg = Base.identify_package("StructuralSizer")
println("Recompiling StructuralSizer...")
Base.compilecache(pkg)
println("Done!")
