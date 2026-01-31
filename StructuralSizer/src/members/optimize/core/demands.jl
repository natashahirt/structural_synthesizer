# Demand Types
# Force demands for structural members. Geometry (L, Lb, K, Cb) comes from Member.

abstract type AbstractDemand end

# ==============================================================================
# Steel/General Member Demand (AISC-style)
# ==============================================================================

"""
Unified demand for framing members (beams, columns, beam-columns).

# Fields
- `member_idx`: Index of the member group
- `Pu_c`: Compression magnitude (always positive) [N]
- `Pu_t`: Tension magnitude (always positive) [N]
- `Mux`: Strong-axis moment [N*m]
- `Muy`: Weak-axis moment [N*m]
- `Vu_strong`: Strong-axis shear [N]
- `Vu_weak`: Weak-axis shear [N]
- `δ_max`: Maximum local deflection from analysis [m] (for deflection scaling)
- `I_ref`: Reference moment of inertia used in analysis [m⁴] (for deflection scaling)
"""
struct MemberDemand{T} <: AbstractDemand
    member_idx::Int
    Pu_c::T      # Compression magnitude (always positive)
    Pu_t::T      # Tension magnitude (always positive)
    Mux::T       # Strong-axis moment
    Muy::T       # Weak-axis moment
    Vu_strong::T # Strong-axis shear
    Vu_weak::T   # Weak-axis shear
    δ_max::T     # Max local deflection from analysis (for scaling)
    I_ref::T     # Reference I used in analysis (for scaling)
end

# Flexible constructor with defaults
function MemberDemand(idx::Int; 
    Pu_c=0.0, Pu_t=0.0, Mux=0.0, Muy=0.0, 
    Vu_strong=0.0, Vu_weak=0.0,
    δ_max=0.0, I_ref=1.0  # Deflection fields with safe defaults
)
    T = promote_type(
        typeof(Pu_c), typeof(Pu_t), typeof(Mux), typeof(Muy), 
        typeof(Vu_strong), typeof(Vu_weak), typeof(δ_max), typeof(I_ref)
    )
    MemberDemand{T}(idx, T(Pu_c), T(Pu_t), T(Mux), T(Muy), T(Vu_strong), T(Vu_weak), T(δ_max), T(I_ref))
end

# ==============================================================================
# RC Column Demand (ACI-style)
# ==============================================================================

"""
    RCColumnDemand <: AbstractDemand

Demand for reinforced concrete columns including biaxial moments.
All force/moment values can be in any Unitful units - they will be
converted internally to kip/kip-ft for ACI calculations.

# Fields
- `member_idx`: Index of the member group
- `Pu`: Factored axial load (positive = compression)
- `Mux`: Factored moment about x-axis
- `Muy`: Factored moment about y-axis
- `βdns`: Ratio of sustained to total factored load (for slenderness)

# Examples
```julia
# Using kip/kip-ft (US units)
demand = RCColumnDemand(1; Pu=500.0, Mux=100.0, Muy=50.0)

# Using Unitful (SI or mixed)
demand = RCColumnDemand(1; 
    Pu=2000u"kN", 
    Mux=150u"kN*m", 
    Muy=75u"kN*m"
)
```
"""
struct RCColumnDemand{T} <: AbstractDemand
    member_idx::Int
    Pu::T           # Factored axial (positive = compression)
    Mux::T          # Moment about x-axis
    Muy::T          # Moment about y-axis
    βdns::Float64   # Sustained load ratio (for slenderness) - always Float64
end

function RCColumnDemand(idx::Int;
    Pu = 0.0,
    Mux = 0.0,
    Muy = 0.0,
    βdns = 0.6  # Default: 60% sustained (typical for gravity)
)
    T = promote_type(typeof(Pu), typeof(Mux), typeof(Muy))
    RCColumnDemand{T}(idx, T(Pu), T(Mux), T(Muy), Float64(βdns))
end
