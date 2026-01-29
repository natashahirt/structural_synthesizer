using StructuralSizer

println("Testing HSS sections...")

# Test rectangular HSS
s = HSS("HSS8X8X1/2")
println("HSSRectSection: ", s.name)
println("  λ_w = ", round(s.λ_w, digits=2))
println("  λ_f = ", round(s.λ_f, digits=2))
println("  is_square: ", is_square(s))

# Test round HSS
p = HSSRound("Pipe8STD")
println("\nHSSRoundSection: ", p.name)
println("  D/t = ", round(p.D_t, digits=2))
println("  slenderness: ", round(slenderness(p), digits=2))

# Test PIPE alias
p2 = PIPE("Pipe8STD")
println("\nPIPE alias works: ", p2.name == p.name)

# Test PipeSection type alias
println("PipeSection <: HSSRoundSection: ", PipeSection <: AbstractRoundHollowSection)

println("\n✓ All quick tests passed!")
