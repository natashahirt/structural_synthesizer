using Printf

macro bench(label, expr)
    quote
        print("  ", $(esc(label)), " … ")
        local t = @elapsed $(esc(expr))
        @printf("%.4f s\n", t)
        t
    end
end

println("=== Cold-Start Performance Profile ===")
println()

# Package loading
print("  Package loading … ")
t_load = @elapsed begin
    using StructuralSynthesizer
    using StructuralSizer
    using Asap
    using Unitful
end
@printf("%.4f s\n", t_load)

println()
println("─── Stage 1: Skeleton + Structure ───")

skel = nothing
struc = nothing
t_skel = @bench "gen_medium_office" begin
    skel = gen_medium_office(54.0u"ft", 42.0u"ft", 9.0u"ft", 3, 3, 1)
end
t_struc = @bench "BuildingStructure" begin
    struc = BuildingStructure(skel)
end

println()
println("─── Stage 2: Initialize (breakdown) ───")

opts_ddm = FloorOptions(
    flat_plate = FlatPlateOptions(
        material = RC_4000_60,
        analysis_method = :ddm,
        cover = 0.75u"inch",
        bar_size = 5,
    ),
    tributary_axis = nothing
)

t_init_cells = @bench "initialize_cells!" initialize_cells!(struc)
t_init_slabs = @bench "initialize_slabs!" initialize_slabs!(struc; floor_type=:flat_plate, floor_kwargs=(options=opts_ddm,))
t_init_segments = @bench "initialize_segments!" initialize_segments!(struc)
t_update_bracing = @bench "update_bracing!" update_bracing!(struc)
t_init_members = @bench "initialize_members!" initialize_members!(struc)
t_parallel_batches = @bench "slab_parallel_batches!" compute_slab_parallel_batches!(struc)

println()
println("─── Stage 3: to_asap! ───")
t_to_asap = @bench "to_asap!" to_asap!(struc)

println()
println("─── Stage 3b: Column Estimation ───")
t_col_est = @bench "estimate_column_sizes!" estimate_column_sizes!(struc)

println()
println("─── Stage 4: Sizing ───")
t_ddm_cold = @bench "size_slabs!(DDM) 1st" size_slabs!(struc; options=opts_ddm, verbose=false, max_iterations=20)
t_ddm_warm = @bench "size_slabs!(DDM) 2nd" size_slabs!(struc; options=opts_ddm, verbose=false, max_iterations=20)

# Steel
skel_st = gen_medium_office(54.0u"ft", 42.0u"ft", 9.0u"ft", 3, 3, 1)
struc_st = BuildingStructure(skel_st)
initialize!(struc_st; floor_type=:flat_plate, floor_kwargs=(options=opts_ddm,))
to_asap!(struc_st)
Asap.solve!(struc_st.asap_model)
t_steel = @bench "size_steel_members!" size_steel_members!(struc_st; member_edge_group=:beams, resolution=200)

# ASAP micro
n1 = Node([0.0, 0.0, 0.0]u"m", :fixed)
n2 = Node([5.0, 0.0, 0.0]u"m", :free)
sec = Asap.Section(0.01u"m^2", 200e9u"Pa", 80e9u"Pa", 8.33e-5u"m^4", 8.33e-5u"m^4", 1.0e-4u"m^4", 7850.0u"kg/m^3")
el = Element(n1, n2, sec)
ld = NodeForce(n2, [0.0, 0.0, -10_000.0]u"N")
micro_model = FrameModel([n1, n2], [el], [ld])
Asap.process!(micro_model)
Asap.solve!(micro_model)
t_solve100 = @bench "100× solve!" for _ in 1:100; Asap.solve!(micro_model; reprocess=true); end

println()
println("============================================================")
println("  TIMING SUMMARY")
println("============================================================")
@printf("  Package loading           : %8.4f s\n", t_load)
println("  ─── Initialize ───")
@printf("    gen_medium_office       : %8.4f s\n", t_skel)
@printf("    BuildingStructure       : %8.4f s\n", t_struc)
@printf("    initialize_cells!       : %8.4f s\n", t_init_cells)
@printf("    initialize_slabs!       : %8.4f s\n", t_init_slabs)
@printf("    initialize_segments!    : %8.4f s\n", t_init_segments)
@printf("    update_bracing!         : %8.4f s\n", t_update_bracing)
@printf("    initialize_members!     : %8.4f s\n", t_init_members)
@printf("    parallel_batches!       : %8.4f s\n", t_parallel_batches)
@printf("    to_asap!                : %8.4f s\n", t_to_asap)
@printf("    estimate_col_sizes!     : %8.4f s\n", t_col_est)
println("  ─── Sizing ───")
@printf("    DDM slab (cold)         : %8.4f s\n", t_ddm_cold)
@printf("    DDM slab (warm)         : %8.4f s\n", t_ddm_warm)
@printf("    Steel beam sizing       : %8.4f s\n", t_steel)
println("  ─── ASAP Solver ───")
@printf("    100× resolve            : %8.4f s  (%.1f μs/solve)\n", t_solve100, t_solve100/100*1e6)
println("  ─── Totals ───")
t_init = t_init_cells + t_init_slabs + t_init_segments + t_update_bracing + t_init_members + t_parallel_batches + t_to_asap + t_col_est
t_sizing = t_ddm_cold + t_steel
@printf("    Init total (cold)       : %8.4f s\n", t_init)
@printf("    Sizing total (cold)     : %8.4f s\n", t_sizing)
@printf("    Pipeline total (cold)   : %8.4f s\n", t_init + t_sizing)
println("============================================================")
