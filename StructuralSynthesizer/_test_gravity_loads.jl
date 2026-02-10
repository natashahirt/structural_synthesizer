println("--- Loading StructuralSynthesizer ---")
using StructuralSynthesizer

println("\n--- GravityLoads Struct ---")
g = GravityLoads()
println("Default: $g")

println("\n--- Presets ---")
println("office_loads:      $(office_loads)")
println("residential_loads: $(residential_loads)")
println("assembly_loads:    $(assembly_loads)")
println("storage_loads:     $(storage_loads)")

println("\n--- Custom Loads ---")
custom = GravityLoads(floor_LL = 65.0psf, floor_SDL = 20.0psf)
println("Custom: $custom")

println("\n--- load_map ---")
println(load_map(office_loads))

println("\n--- Envelope Pressure ---")
combos = [strength_1_4D, strength_1_2D_1_6L]
p = envelope_pressure(combos, 100.0psf, 50.0psf)
println("envelope_pressure([1.4D, 1.2D+1.6L], 100psf, 50psf) = $p")

println("\n--- DesignParameters with loads ---")
params = DesignParameters(
    loads = office_loads,
    load_combinations = [strength_1_2D_1_6L, strength_1_4D],
)
println("params.loads.floor_LL = $(params.loads.floor_LL)")
println("params.load_combinations = $(length(params.load_combinations)) combos")
println("governing_combo = $(governing_combo(params))")

println("\n--- design_building integration (build a small structure) ---")
using StructuralSizer
skel = StructuralSynthesizer.gen_medium_office(;
    lx = 6.0u"m", ly = 6.0u"m", n_bays_x = 2, n_bays_y = 2,
    n_stories = 2, story_height = 3.5u"m",
)
struc = BuildingStructure(skel)
println("Created BuildingStructure")

# Test that initialize! accepts loads kwarg
initialize!(struc; loads = office_loads, floor_type = :flat_plate)
println("Cells initialized: $(length(struc.cells))")
for c in struc.cells[1:min(3, length(struc.cells))]
    println("  Cell $(c.face_idx): LL=$(c.live_load), SDL=$(c.sdl)")
end

println("\n✅ All gravity loads tests passed!")
