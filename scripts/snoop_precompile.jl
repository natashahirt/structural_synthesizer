#!/usr/bin/env julia
# =============================================================================
# SnoopCompile-based precompilation profiling
# =============================================================================
#
# Identifies which methods should be added to the PrecompileTools workload.
#
# Usage:
#   1. Add SnoopCompile to the root project:
#        julia --project=. -e 'using Pkg; Pkg.add("SnoopCompile")'
#   2. Run this script:
#        julia --project=. scripts/snoop_precompile.jl
#   3. Review the output — methods with high inclusive/exclusive time
#      should be exercised in the @compile_workload blocks.
#
# Reference: https://timholy.github.io/SnoopCompile.jl/stable/
# =============================================================================

using SnoopCompile

println("Running @snoopi_deep inference profiling …")

tinf = @snoopi_deep begin
    using StructuralSynthesizer
    using StructuralSizer
    using Unitful

    redirect_stdio(; stdout=devnull, stderr=devnull) do
        # ── Exercise the main hot paths ──

        # 1. Building generation
        skel = gen_medium_office(40.0u"m", 30.0u"m", 4.0u"m", 3, 2, 1)
        struc = BuildingStructure(skel)

        # 2. Steel beam catalog + AISC check
        cat = all_W()
        checker = AISCChecker()
        cache = create_cache(checker, length(cat))
        precompute_capacities!(checker, cache, cat, A992_Steel, MinVolume())

        # 3. RC column catalog + ACI P-M
        rc_cat = rc_column_catalog(:rect, :standard)
        aci_checker = ACIColumnChecker(;
            fy_ksi = ustrip(ksi, Rebar_60.Fy),
            Es_ksi = ustrip(ksi, Rebar_60.E),
        )
        aci_cache = create_cache(aci_checker, length(rc_cat))
        precompute_capacities!(aci_checker, aci_cache, rc_cat, NWC_4000, MinVolume())

        # 4. MIP solve (HiGHS, small problem)
        try
            Pu_test = [200.0kip]
            Mux_test = [100.0kip*u"ft"]
            geom_test = [ConcreteMemberGeometry(12.0u"ft")]
            opts_test = ConcreteColumnOptions()
            size_columns(Pu_test, Mux_test, geom_test, opts_test;
                optimizer=:highs, output_flag=0, mip_gap=1e-3, time_limit_sec=5.0)
        catch
        end
    end
end

# =============================================================================
# Analyze and report
# =============================================================================

itrigs = SnoopCompile.inference_triggers(tinf)
println("\n=== Top 30 inference triggers (by inclusive time) ===")
show(stdout, MIME("text/plain"), itrigs; maxdepth=30)

# Flame-graph data (can be viewed with ProfileView or PProf)
mtrigs = SnoopCompile.method_invalidations(tinf)
println("\n\n=== Summary ===")
println("Total inference roots: ", length(SnoopCompile.staleinstances(tinf)))
println("Unique method triggers: ", length(itrigs))
println("\nDone.  Use `SnoopCompile.parcel(tinf)` for per-module precompile directives.")
