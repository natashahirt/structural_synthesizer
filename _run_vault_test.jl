# Quick vault pipeline test runner
using Pkg
Pkg.activate(joinpath(@__DIR__))

using Test, Unitful, StructuralSizer, StructuralSynthesizer, Asap

println("=== Running vault pipeline test ===")
include("StructuralSynthesizer/test/sizing/slabs/test_vault_pipeline.jl")

println("\n=== Running vault visualization ===")
# Small vault building for visualization
skel = gen_medium_office(30.0u"ft", 24.0u"ft", 12.0u"ft", 2, 2, 1)
struc = BuildingStructure(skel)

design = design_building(struc, DesignParameters(
    name = "Vault Vis Test",
    floor_options = FloorOptions(
        floor_type = :vault,
        vault = VaultOptions(lambda = 8.0, material = NWC_4000),
    ),
))

# Vault cross-section + 3D view
visualize_vault(design)

# Standard design view — vaults render as parabolic arches
visualize(design, show_sections=:solid)

println("\n✓ Done!")
