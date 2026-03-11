using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))

using StructuralSizer
using Unitful

println("StructuralSizer loaded OK")
sec = W("W14X22")
println("W14X22 PA = ", sec.PA)
println("exposed_perimeter (3-sided) = ", exposed_perimeter(sec; exposure=:three_sided))
println("exposed_perimeter (4-sided) = ", exposed_perimeter(sec; exposure=:four_sided))

# Verify binary search is accessible
println("optimize_binary_search is exported: ", isdefined(StructuralSizer, :optimize_binary_search))

# Verify coating functions
coating = SurfaceCoating(1.5, 15.0, "SFRM")
vol = coating_volume(sec, coating, 6.0u"m")
println("Coating volume = ", vol)
ec = coating_ec(sec, coating, 6.0u"m")
println("Coating EC = ", ec, " kgCO₂e")

println("\nAll verifications passed!")
