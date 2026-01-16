# Demand Types
# Force demands for structural members. Geometry (L, Lb, K, Cb) comes from Member.

abstract type AbstractDemand end

"""Unified demand for framing members (beams, columns, beam-columns)."""
struct MemberDemand{T} <: AbstractDemand
    member_idx::Int
    Pu_c::T      # Compression magnitude (always positive)
    Pu_t::T      # Tension magnitude (always positive)
    Mux::T       # Strong-axis moment
    Muy::T       # Weak-axis moment
    Vu_strong::T # Strong-axis shear
    Vu_weak::T   # Weak-axis shear
end

# Legacy support / Convenience constructors need updating or removal if we change the struct layout.
# Let's provide a flexible constructor.

function MemberDemand(idx::Int; Pu_c=0.0, Pu_t=0.0, Mux=0.0, Muy=0.0, Vu_strong=0.0, Vu_weak=0.0)
    T = promote_type(typeof(Pu_c), typeof(Pu_t), typeof(Mux), typeof(Muy), typeof(Vu_strong), typeof(Vu_weak))
    MemberDemand{T}(idx, T(Pu_c), T(Pu_t), T(Mux), T(Muy), T(Vu_strong), T(Vu_weak))
end
