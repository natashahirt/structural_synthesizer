using Test
using Random: MersenneTwister
using StructuralSynthesizer: slab_conflict_coloring

# =============================================================================
# Helper: verify a coloring has no conflicts
# =============================================================================

"""
    verify_no_conflicts(batches, slab_column_sets) -> Bool

For every batch, assert no two slabs share a column.
Returns true if valid; throws on violation.
"""
function verify_no_conflicts(batches::Vector{Vector{Int}},
                             slab_column_sets::Vector{Set{Int}})
    for (b, batch) in enumerate(batches)
        for i in 1:length(batch), j in (i+1):length(batch)
            s_i = batch[i]
            s_j = batch[j]
            shared = intersect(slab_column_sets[s_i], slab_column_sets[s_j])
            if !isempty(shared)
                error("CONFLICT in batch $b: slabs $s_i and $s_j share columns $shared")
            end
        end
    end
    return true
end

"""All slab indices appear exactly once across batches."""
function verify_coverage(batches::Vector{Vector{Int}}, n_slabs::Int)
    seen = sort(vcat(batches...))
    @test seen == collect(1:n_slabs)
end

# =============================================================================
# Tests
# =============================================================================

@testset "Slab Conflict Coloring" begin

    # ─── Empty input ───
    @testset "empty" begin
        batches = slab_conflict_coloring(Set{Int}[])
        @test isempty(batches)
    end

    # ─── Single slab ───
    @testset "single slab" begin
        sets = [Set([1, 2, 3])]
        batches = slab_conflict_coloring(sets)
        @test length(batches) == 1
        @test batches[1] == [1]
        @test verify_no_conflicts(batches, sets)
    end

    # ─── Independent slabs (no shared columns) ───
    @testset "independent slabs → 1 batch" begin
        sets = [Set([1, 2]), Set([3, 4]), Set([5, 6]), Set([7, 8])]
        batches = slab_conflict_coloring(sets)
        @test length(batches) == 1          # all fit in one batch
        verify_coverage(batches, 4)
        @test verify_no_conflicts(batches, sets)
    end

    # ─── Fully connected (all slabs share column 1) ───
    @testset "fully connected → n batches" begin
        sets = [Set([1, 2]), Set([1, 3]), Set([1, 4]), Set([1, 5])]
        batches = slab_conflict_coloring(sets)
        @test length(batches) == 4          # each slab alone
        verify_coverage(batches, 4)
        @test verify_no_conflicts(batches, sets)
    end

    # ─── 2×2 grid (checkerboard) ───
    #
    #   C1──C2──C3
    #   │ S1│ S2│
    #   C4──C5──C6
    #   │ S3│ S4│
    #   C7──C8──C9
    #
    # S1 shares C2,C5 with S2; C4,C5 with S3; C5 with S4
    # S2 shares C5,C6 with S4; C2,C5 with S1; C5 with S3
    # Checkerboard: {S1,S4} and {S2,S3} should work (2 colors)
    @testset "2×2 grid → ≤ 4 colors, no conflicts" begin
        sets = [
            Set([1, 2, 4, 5]),   # S1
            Set([2, 3, 5, 6]),   # S2
            Set([4, 5, 7, 8]),   # S3
            Set([5, 6, 8, 9]),   # S4
        ]
        batches = slab_conflict_coloring(sets)
        @test length(batches) >= 2     # at least 2 colors needed
        @test length(batches) <= 4     # greedy won't exceed 4
        verify_coverage(batches, 4)
        @test verify_no_conflicts(batches, sets)
    end

    # ─── 3×3 grid → more stress ───
    @testset "3×3 grid → no conflicts" begin
        # 9 slabs in a 3×3 grid, 16 columns (4×4 grid of columns)
        # Column numbering: row-major 1..16 in a 4×4 grid
        #   1  2  3  4
        #   5  6  7  8
        #   9 10 11 12
        #  13 14 15 16
        #
        # Slab (r,c) uses columns at corners:
        #   col(r,c), col(r,c+1), col(r+1,c), col(r+1,c+1)
        col(r, c) = (r - 1) * 4 + c
        sets = Set{Int}[]
        for r in 1:3, c in 1:3
            push!(sets, Set([col(r, c), col(r, c+1), col(r+1, c), col(r+1, c+1)]))
        end
        @test length(sets) == 9

        batches = slab_conflict_coloring(sets)
        @test length(batches) >= 2
        verify_coverage(batches, 9)
        @test verify_no_conflicts(batches, sets)
    end

    # ─── Linear chain (each slab shares one column with its neighbour) ───
    @testset "linear chain → 2 colors" begin
        # S1: {1,2}, S2: {2,3}, S3: {3,4}, S4: {4,5}
        sets = [Set([k, k+1]) for k in 1:6]
        batches = slab_conflict_coloring(sets)
        @test length(batches) == 2      # bipartite graph → 2 colors
        verify_coverage(batches, 6)
        @test verify_no_conflicts(batches, sets)
    end

    # ─── Star topology (one central slab shares columns with all others) ───
    @testset "star topology" begin
        # Central slab uses cols 1..4, each outer slab shares one column
        center = Set([1, 2, 3, 4])
        outer = [Set([k, 10+k]) for k in 1:4]  # each shares one col with center
        sets = [center; outer]
        batches = slab_conflict_coloring(sets)
        @test length(batches) >= 2      # center can't be with any outer
        verify_coverage(batches, 5)
        @test verify_no_conflicts(batches, sets)
    end

    # ─── Odd cycle (3 slabs in a triangle) ───
    @testset "odd cycle (triangle) → 3 colors" begin
        sets = [Set([1, 2]), Set([2, 3]), Set([3, 1])]
        batches = slab_conflict_coloring(sets)
        @test length(batches) == 3      # odd cycle needs 3 colors
        verify_coverage(batches, 3)
        @test verify_no_conflicts(batches, sets)
    end

    # ─── Large random test (stress test for correctness) ───
    @testset "random 50 slabs, 30 columns" begin
        rng = MersenneTwister(42)
        n_slabs = 50
        n_cols = 30
        sets = [Set(rand(rng, 1:n_cols, rand(rng, 2:6))) for _ in 1:n_slabs]

        batches = slab_conflict_coloring(sets)
        verify_coverage(batches, n_slabs)
        @test verify_no_conflicts(batches, sets)
    end

end

println("All slab coloring tests passed!")
