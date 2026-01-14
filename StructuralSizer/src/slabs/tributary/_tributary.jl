# Tributary load distribution (stub)

"""
    distribute_slab_loads(beam_ids, total_force)

Very simple load distributor for pipeline testing.

Returns a vector of per-beam loads. Each entry is a NamedTuple:
`(beam_id, xs, F)` where:
- `xs` is a vector of normalized positions in [0,1]
- `F` is a vector of global point-load vectors (N) at each station in `xs`

This test implementation splits `total_force` evenly across all `beam_ids` and
applies a single point load at midspan (`xs = 0.5`) for each beam.
"""
function distribute_slab_loads(
    beam_ids::AbstractVector{<:Integer},
    total_force::NTuple{3, Float64};
)
    n_beams = length(beam_ids)
    n_beams > 0 || return NamedTuple[]

    Fx, Fy, Fz = total_force
    scale = 1.0 / n_beams
    f_per = (Fx * scale, Fy * scale, Fz * scale)

    xs = [0.5]

    return [
        (beam_id = Int(b), xs = xs, F = [f_per])
        for b in beam_ids
    ]
end