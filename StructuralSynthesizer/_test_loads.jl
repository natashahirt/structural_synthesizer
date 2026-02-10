println("--- Precompiling StructuralSynthesizer ---")
using StructuralSynthesizer
println("  OK")

println("\n--- LoadCombination (from StructuralSizer) ---")
println("  default_combo: $(default_combo)")
println("  D=$(default_combo.D), L=$(default_combo.L)")

println("\n--- GravityLoads (from StructuralSizer) ---")
println("  default_loads: $(default_loads)")
println("  office_loads:  $(office_loads)")

println("\n--- factored_pressure ---")
p = factored_pressure(default_combo, 100.0psf, 50.0psf)
println("  1.2*100 + 1.6*50 = $p (expect 200 psf)")

println("\n--- envelope_pressure ---")
combos = [strength_1_4D, strength_1_2D_1_6L]
pe = envelope_pressure(combos, 100.0psf, 50.0psf)
println("  max(1.4*100, 1.2*100+1.6*50) = $pe (expect 200 psf)")

println("\n--- DesignParameters with loads ---")
params = DesignParameters(
    loads = office_loads,
    load_combinations = [strength_1_2D_1_6L, strength_1_4D],
)
println("  loads.floor_LL = $(params.loads.floor_LL)")
println("  combos = $(length(params.load_combinations)) entries")

println("\n--- Build a structure + initialize with loads ---")
using StructuralSizer
skel = StructuralSynthesizer.gen_medium_office(;
    lx = 6.0u"m", ly = 6.0u"m", n_bays_x = 2, n_bays_y = 2,
    n_stories = 2, story_height = 3.5u"m",
)
struc = BuildingStructure(skel)
initialize!(struc; loads = office_loads, floor_type = :flat_plate)
println("  Cells: $(length(struc.cells))")
c1 = struc.cells[1]
println("  Cell 1: LL=$(c1.live_load), SDL=$(c1.sdl)")

println("\n  All passed!")
