# Demand Types
# Force demands for structural members. Geometry (L, Lb, K, Cb) comes from Member.

abstract type AbstractDemand end

"""Unified demand for framing members (beams, columns, beam-columns)."""
struct MemberDemand{T} <: AbstractDemand
    member_idx::Int
    Pu::T    # axial (+tension, -compression, 0=pure flexure)
    Mux::T   # strong-axis moment
    Muy::T   # weak-axis moment
    Vu::T    # shear
end

# Full constructor
MemberDemand(idx::Int, Pu::T, Mux::T, Muy::T, Vu::T) where T = MemberDemand{T}(idx, Pu, Mux, Muy, Vu)

# Beam (flexure + shear only)
MemberDemand(idx::Int, Mux::T, Vu::T) where T = MemberDemand{T}(idx, zero(Mux), Mux, zero(Mux), Vu)

# Column (axial only)
function MemberDemand(idx::Int, Pu::T; Mux=zero(Pu), Muy=zero(Pu), Vu=zero(Pu)) where T
    MemberDemand{T}(idx, Pu, Mux, Muy, Vu)
end
