# Demand Types
# Material-agnostic structures for structural optimization.

abstract type AbstractDemand end

"""Demand for flexural members (beams, girders)."""
struct FlexuralDemand{T} <: AbstractDemand
    id::Any
    Mu::T       # factored moment
    Vu::T       # factored shear
    L::T        # span
    Lb::T       # unbraced length (LTB)
    Cb::Float64 # moment gradient factor
end

function FlexuralDemand(; id, Mu, Vu, L, Lb=L, Cb=1.0)
    FlexuralDemand{typeof(Mu)}(id, Mu, Vu, L, Lb, Float64(Cb))
end

"""Demand for compression members (columns) with optional bending."""
struct CompressionDemand{T} <: AbstractDemand
    id::Any
    Pu::T       # factored axial
    Mux::T      # factored strong-axis moment
    Muy::T      # factored weak-axis moment
    Lx::T       # unbraced length (x-axis)
    Ly::T       # unbraced length (y-axis)
    Lb::T       # unbraced length (LTB)
    Kx::Float64
    Ky::Float64
    Cb::Float64
end

function CompressionDemand(; id, Pu, Mux=zero(Pu), Muy=zero(Pu), 
                            Lx, Ly=Lx, Lb=Lx, Kx=1.0, Ky=1.0, Cb=1.0)
    CompressionDemand{typeof(Pu)}(id, Pu, Mux, Muy, Lx, Ly, Lb, 
                                   Float64(Kx), Float64(Ky), Float64(Cb))
end

"""Demand for tension members (braces, hangers)."""
struct TensionDemand{T} <: AbstractDemand
    id::Any
    Tu::T
end

TensionDemand(; id, Tu) = TensionDemand{typeof(Tu)}(id, Tu)

# Utility
demand_type(::FlexuralDemand) = :flexure
demand_type(::CompressionDemand) = :compression
demand_type(::TensionDemand) = :tension
