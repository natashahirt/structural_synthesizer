using StructuralSynthesizer
using StructuralSizer
using Unitful

println("Testing DDM design_building path...")
try
    skel = gen_medium_office(40.0u"m", 30.0u"m", 4.0u"m", 3, 2, 1)
    struc = BuildingStructure(skel)
    design = design_building(struc, DesignParameters(
        name = "precompile_ddm",
        floor_options = FloorOptions(
            flat_plate = FlatPlateOptions(
                material = RC_4000_60,
                analysis_method = :ddm,
            ),
        ),
        max_iterations = 2,
    ))
    println("  ✅ DDM design_building succeeded!")
catch e
    println("  ❌ DDM design_building FAILED: ", e)
    showerror(stdout, e, catch_backtrace())
    println()
end

println("\nTesting EFM design_building path...")
try
    skel2 = gen_medium_office(40.0u"m", 30.0u"m", 4.0u"m", 2, 2, 1)
    struc2 = BuildingStructure(skel2)
    design2 = design_building(struc2, DesignParameters(
        name = "precompile_efm",
        floor_options = FloorOptions(
            flat_plate = FlatPlateOptions(
                material = RC_4000_60,
                analysis_method = :efm,
            ),
        ),
        max_iterations = 2,
    ))
    println("  ✅ EFM design_building succeeded!")
catch e
    println("  ❌ EFM design_building FAILED: ", e)
    showerror(stdout, e, catch_backtrace())
    println()
end

println("\nTesting steel member sizing path...")
try
    skel3 = gen_medium_office(40.0u"m", 30.0u"m", 4.0u"m", 2, 2, 1)
    struc3 = BuildingStructure(skel3)
    initialize!(struc3; floor_type = :flat_plate)
    to_asap!(struc3)
    Asap.solve!(struc3.asap_model)
    size_steel_members!(struc3;
        member_edge_group = :beams,
        resolution = 20,
    )
    println("  ✅ Steel sizing succeeded!")
catch e
    println("  ❌ Steel sizing FAILED: ", e)
    showerror(stdout, e, catch_backtrace())
    println()
end

println("\nDone.")
