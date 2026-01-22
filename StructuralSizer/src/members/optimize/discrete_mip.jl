import JuMP
import HiGHS

# Optional Gurobi import (accelerator). Keep HiGHS as the baseline open-source solver.
const _HAS_GUROBI = Ref(false)
try
    import Gurobi
    _HAS_GUROBI[] = true
catch
    _HAS_GUROBI[] = false
end

# =============================================================================
# Capacity Caching (avoids repeated AISC capacity calculations)
# =============================================================================

"""Round length to nearest mm for cache key (avoids floating-point key issues)."""
@inline _length_key(L_m::Float64)::Int = round(Int, L_m * 1000)

"""
    CapacityCache

Local cache for length-dependent capacity calculations during MIP feasibility filtering.
Avoids repeated `get_ϕPn` and `get_ϕMn` calls for the same (section, length) pairs.
"""
struct CapacityCache
    ϕPn_strong::Dict{Tuple{Int, Int}, Float64}   # (section_idx, Lc_mm) → ϕPn
    ϕPn_weak::Dict{Tuple{Int, Int}, Float64}
    ϕPn_torsional::Dict{Tuple{Int, Int}, Float64}
    ϕMn_strong::Dict{Tuple{Int, Int, Int}, Float64}  # (section_idx, Lb_mm, Cb_100) → ϕMn
end

CapacityCache() = CapacityCache(
    Dict{Tuple{Int, Int}, Float64}(),
    Dict{Tuple{Int, Int}, Float64}(),
    Dict{Tuple{Int, Int}, Float64}(),
    Dict{Tuple{Int, Int, Int}, Float64}()
)

"""Get cached ϕPn or compute and cache."""
function _get_ϕPn_cached!(
    cache::CapacityCache, 
    axis::Symbol, 
    j::Int, 
    Lc_m::Float64,
    section, 
    material
)::Float64
    Lc_key = _length_key(Lc_m)
    dict = if axis === :strong
        cache.ϕPn_strong
    elseif axis === :weak
        cache.ϕPn_weak
    else
        cache.ϕPn_torsional
    end
    
    key = (j, Lc_key)
    val = get(dict, key, nothing)
    if isnothing(val)
        Lc = Lc_m * u"m"
        val = ustrip(uconvert(u"N", get_ϕPn(section, material, Lc; axis=axis)))
        dict[key] = val
    end
    return val
end

"""Get cached ϕMn (strong axis) or compute and cache."""
function _get_ϕMnx_cached!(
    cache::CapacityCache,
    j::Int,
    Lb_m::Float64,
    Cb::Float64,
    section,
    material,
    ϕ_b::Float64
)::Float64
    Lb_key = _length_key(Lb_m)
    Cb_key = round(Int, Cb * 100)  # 2 decimal precision
    key = (j, Lb_key, Cb_key)
    
    val = get(cache.ϕMn_strong, key, nothing)
    if isnothing(val)
        Lb = Lb_m * u"m"
        val = ustrip(uconvert(u"N*m", get_ϕMn(section, material; Lb=Lb, Cb=Cb, axis=:strong, ϕ=ϕ_b)))
        cache.ϕMn_strong[key] = val
    end
    return val
end

"""
    _choose_mip_optimizer(optimizer::Symbol)

Select a JuMP optimizer constructor.

- `:auto`: prefer Gurobi if available, else HiGHS
- `:gurobi`: require Gurobi
- `:highs`: use HiGHS
"""
function _choose_mip_optimizer(optimizer::Symbol)
    if optimizer === :highs
        return (() -> HiGHS.Optimizer()), :highs
    elseif optimizer === :gurobi
        _HAS_GUROBI[] || throw(ArgumentError("optimizer=:gurobi requested, but Gurobi.jl is not available in this environment."))
        return (() -> Gurobi.Optimizer()), :gurobi
    elseif optimizer === :auto
        return _HAS_GUROBI[] ? (() -> Gurobi.Optimizer(), :gurobi) : (() -> HiGHS.Optimizer(), :highs)
    else
        throw(ArgumentError("Unknown optimizer=$optimizer. Use :auto, :gurobi, or :highs."))
    end
end

"""
    optimize_member_groups_discrete(
        demands::AbstractVector{<:MemberDemand},
        lengths,
        Lbs,
        Cbs,
        Kxs,
        Kys;
        catalogue=all_W(),
        material=A992_Steel,
        max_depth=Inf*u"m",
        n_max_sections::Integer=0,
        optimizer::Symbol=:auto,
        objective::AbstractObjective=MinVolume(),
        prefer_penalty::Real=1.0,
        ϕ_b=0.9,
        ϕ_v=1.0,
        mip_gap=1e-4,
        output_flag::Integer=0,
        deflection_limit::Union{Nothing, Real}=nothing,
    )

Discrete, simultaneous section assignment for *member groups*.

Strength checks (AISC 360-16):
- Shear: Checks Strong Axis (`abs(Vu_strong) ≤ ϕVn_strong`) and Weak Axis (`abs(Vu_weak) ≤ ϕVn_weak`).
- Interaction (H1-1/H1-2):
  - Checks **Compression** interaction (`Pu_c`, `Mux`, `Muy`) using `ϕPnc` (Flexural/Torsional Buckling).
  - Checks **Tension** interaction (`Pu_t`, `Mux`, `Muy`) using `ϕPnt` (Yielding/Rupture).
  - Flexure checks include LTB (`Cb`) and FLB.

# Deflection Limit (Optional)
If `deflection_limit` is set (e.g., `1/360`), sections are filtered to ensure:
  `δ / L ≤ deflection_limit`
where δ is scaled from the analysis deflection using moment of inertia ratios.

# Preferred Sections
If `prefer_penalty > 1.0`, non-preferred (non-bolded) sections are penalized in the objective.
E.g., `prefer_penalty=1.05` makes non-preferred sections appear 5% heavier, biasing the
optimizer toward AISC "economical" sections when weights are close.

Returns a named tuple:
`(; section_indices, sections, status, objective_value)`.
"""
function optimize_member_groups_discrete(
    demands::AbstractVector{<:MemberDemand},
    lengths,
    Lbs,
    Cbs,
    Kxs,
    Kys;
    catalogue=all_W(),
    material=A992_Steel,
    max_depth=Inf * u"m",
    n_max_sections::Integer=0,
    optimizer::Symbol=:auto,
    objective::AbstractObjective=MinVolume(),
    prefer_penalty::Real=1.0,
    ϕ_b=0.9,
    ϕ_v=1.0,
    mip_gap=1e-4,
    output_flag::Integer=0,
    deflection_limit::Union{Nothing, Real}=nothing,
)
    n_groups = length(demands)
    n_groups == length(lengths) == length(Lbs) == length(Cbs) == length(Kxs) == length(Kys) ||
        throw(ArgumentError("demands/lengths/Lbs/Cbs/Kxs/Kys must have the same length"))

    # --- Convert group demands/geometry to numeric SI (Float64) for JuMP ---
    Pu_c = Vector{Float64}(undef, n_groups)
    Pu_t = Vector{Float64}(undef, n_groups)
    Mux  = Vector{Float64}(undef, n_groups)
    Muy  = Vector{Float64}(undef, n_groups)
    Vus  = Vector{Float64}(undef, n_groups)
    Vuw  = Vector{Float64}(undef, n_groups)
    δ_max_g = Vector{Float64}(undef, n_groups)  # Max local deflection from analysis
    I_ref_g = Vector{Float64}(undef, n_groups)  # Reference I for deflection scaling
    
    Ltot = Vector{Float64}(undef, n_groups)
    Lb_g = Vector{typeof(1.0u"m")}(undef, n_groups)
    Cb_g = Vector{Float64}(undef, n_groups)
    Kx_g = Vector{Float64}(undef, n_groups)
    Ky_g = Vector{Float64}(undef, n_groups)

    for i in 1:n_groups
        d = demands[i]
        # Conventions:
        # - If demands are Unitful, convert to SI base.
        # - If demands are plain reals, assume SI base (N, N*m).
        Pu_c[i] = d.Pu_c isa Unitful.Quantity ? ustrip(uconvert(u"N",   d.Pu_c)) : Float64(d.Pu_c)
        Pu_t[i] = d.Pu_t isa Unitful.Quantity ? ustrip(uconvert(u"N",   d.Pu_t)) : Float64(d.Pu_t)
        Mux[i]  = d.Mux  isa Unitful.Quantity ? ustrip(uconvert(u"N*m", d.Mux))  : Float64(d.Mux)
        Muy[i]  = d.Muy  isa Unitful.Quantity ? ustrip(uconvert(u"N*m", d.Muy))  : Float64(d.Muy)
        Vus[i]  = d.Vu_strong isa Unitful.Quantity ? ustrip(uconvert(u"N", d.Vu_strong)) : Float64(d.Vu_strong)
        Vuw[i]  = d.Vu_weak   isa Unitful.Quantity ? ustrip(uconvert(u"N", d.Vu_weak))   : Float64(d.Vu_weak)
        
        # Deflection data (already in SI: meters, m^4)
        δ_max_g[i] = d.δ_max isa Unitful.Quantity ? ustrip(uconvert(u"m", d.δ_max)) : Float64(d.δ_max)
        I_ref_g[i] = d.I_ref isa Unitful.Quantity ? ustrip(uconvert(u"m^4", d.I_ref)) : Float64(d.I_ref)
        
        Ltot[i] = lengths[i] isa Unitful.Quantity ? ustrip(uconvert(u"m", lengths[i])) : Float64(lengths[i])
        Lb_g[i] = Lbs[i] isa Unitful.Quantity ? uconvert(u"m", Lbs[i]) : (Float64(Lbs[i]) * u"m")
        Cb_g[i] = Float64(Cbs[i])
        Kx_g[i] = Float64(Kxs[i])
        Ky_g[i] = Float64(Kys[i])
    end

    # --- Catalog properties (SI numeric) ---
    n_sections = length(catalogue)
    A  = Vector{Float64}(undef, n_sections)
    d  = Vector{Float64}(undef, n_sections)
    Ix = Vector{Float64}(undef, n_sections)    # Strong axis moment of inertia (for deflection scaling)
    ϕVn_s = Vector{Float64}(undef, n_sections) # Strong axis shear
    ϕVn_w = Vector{Float64}(undef, n_sections) # Weak axis shear
    ϕMny = Vector{Float64}(undef, n_sections)  # Weak axis flexure (FLB/Yielding)
    ϕPnt = Vector{Float64}(undef, n_sections)  # Tension capacity
    obj_coeffs = Vector{Float64}(undef, n_sections)

    # Determine target unit for objective
    ref_obj = objective_value(objective, catalogue[1], material, 1.0u"m")
    ref_unit = ref_obj isa Unitful.Quantity ? unit(ref_obj) : Unitful.NoUnits

    for j in 1:n_sections
        s = catalogue[j]
        A[j] = ustrip(uconvert(u"m^2", area(s)))
        d[j] = ustrip(uconvert(u"m", depth(s)))
        Ix[j] = ustrip(uconvert(u"m^4", s.Ix))  # Strong axis I for deflection scaling
        
        # Shear Capacities
        ϕVn_s[j] = ustrip(uconvert(u"N", get_ϕVn(s, material; axis=:strong, ϕ=ϕ_v)))
        ϕVn_w[j] = ustrip(uconvert(u"N", get_ϕVn(s, material; axis=:weak,   ϕ=ϕ_v)))
        
        # Weak Axis Flexure (Length-independent for I-shapes)
        ϕMny[j] = ustrip(uconvert(u"N*m", get_ϕMn(s, material; axis=:weak, ϕ=ϕ_b)))
        
        # Tension Capacity
        ϕPnt[j] = ustrip(uconvert(u"N", get_ϕPn_tension(s, material)))
        
        # Calculate objective coefficient (value per meter)
        val = objective_value(objective, s, material, 1.0u"m")
        if ref_unit != Unitful.NoUnits
            obj_coeffs[j] = ustrip(uconvert(ref_unit, val))
        else
            obj_coeffs[j] = val
        end
        
        # Apply penalty to non-preferred sections (biases toward AISC "economical" shapes)
        if prefer_penalty > 1.0 && !s.is_preferred
            obj_coeffs[j] *= prefer_penalty
        end
    end

    max_depth_m = ustrip(uconvert(u"m", max_depth))

    # --- Candidate filtering per group (with capacity caching) ---
    cache = CapacityCache()
    feasible = Dict{Int, Vector{Int}}()
    
    # Convert Lb to Float64 meters for cache keys
    Lb_m = [ustrip(uconvert(u"m", Lb_g[i])) for i in 1:n_groups]
    
    for i in 1:n_groups
        idxs = Int[]
        
        # Precompute effective lengths for this group (in meters, for cache)
        Lc_x_m = Kx_g[i] * Ltot[i]
        Lc_y_m = Ky_g[i] * Ltot[i]
        
        for j in 1:n_sections
            d[j] <= max_depth_m || continue
            
            # Shear Checks (length-independent, precomputed)
            ϕVn_s[j] >= Vus[i] || continue
            ϕVn_w[j] >= Vuw[i] || continue

            # Strong Axis Flexure (cached by Lb, Cb)
            ϕMnx = _get_ϕMnx_cached!(cache, j, Lb_m[i], Cb_g[i], catalogue[j], material, ϕ_b)
            
            # --- Check 1: Compression Interaction ---
            # Cached compression capacities
            ϕPn_x = _get_ϕPn_cached!(cache, :strong, j, Lc_x_m, catalogue[j], material)
            ϕPn_y = _get_ϕPn_cached!(cache, :weak, j, Lc_y_m, catalogue[j], material)
            ϕPn_z = _get_ϕPn_cached!(cache, :torsional, j, Lc_y_m, catalogue[j], material)
            
            ϕPnc = min(ϕPn_x, ϕPn_y, ϕPn_z)

            ur_c = check_PMxMy_interaction(Pu_c[i], Mux[i], Muy[i], ϕPnc, ϕMnx, ϕMny[j])
            ur_c <= 1.0 || continue

            # --- Check 2: Tension Interaction ---
            ur_t = check_PMxMy_interaction(Pu_t[i], Mux[i], Muy[i], ϕPnt[j], ϕMnx, ϕMny[j])
            ur_t <= 1.0 || continue

            # --- Check 3: Deflection Limit (Optional) ---
            if !isnothing(deflection_limit) && I_ref_g[i] > 0 && δ_max_g[i] > 0
                δ_scaled = δ_max_g[i] * I_ref_g[i] / Ix[j]
                δ_ratio = δ_scaled / Ltot[i]
                δ_ratio <= deflection_limit || continue
            end

            push!(idxs, j)
        end
        
        if isempty(idxs) 
            msg = "No feasible sections for group $i: " * 
                  "Pu_c=$(Pu_c[i]) N, Pu_t=$(Pu_t[i]) N, " * 
                  "Mux=$(Mux[i]) N*m, Muy=$(Muy[i]) N*m, " *
                  "Vus=$(Vus[i]) N, Vuw=$(Vuw[i]) N."
            throw(ArgumentError(msg))
        end
        feasible[i] = idxs
    end

    opt_factory, solver = _choose_mip_optimizer(optimizer)
    m = JuMP.Model(opt_factory)

    # Common solver attributes
    if solver === :highs
        JuMP.set_optimizer_attribute(m, "output_flag", output_flag)
        JuMP.set_optimizer_attribute(m, "mip_rel_gap", mip_gap)
    else
        # Gurobi or other MIP solvers
        JuMP.set_optimizer_attribute(m, "OutputFlag", output_flag)
        JuMP.set_optimizer_attribute(m, "MIPGap", mip_gap)
    end

    # Decision: x[i,j] = 1 if group i uses section j (only for feasible pairs)
    JuMP.@variable(m, x[i=1:n_groups, j=feasible[i]], binary=true)
    JuMP.@constraint(m, [i=1:n_groups], sum(x[i,j] for j in feasible[i]) == 1)

    # Optional: limit the number of unique sections used
    if n_max_sections > 0
        JuMP.@variable(m, z[j=1:n_sections], binary=true)
        # If any group selects section j, then z[j]=1
        JuMP.@constraint(m, [j=1:n_sections],
            sum(x[i,j] for i in 1:n_groups if j in feasible[i]) <= n_groups * z[j]
        )
        JuMP.@constraint(m, sum(z[j] for j in 1:n_sections) <= n_max_sections)
    end

    # Minimize total objective value: sum(x[i,j] * coeff[j] * L[i])
    JuMP.@objective(m, Min, sum(sum(x[i,j] * obj_coeffs[j] * Ltot[i] for j in feasible[i]) for i in 1:n_groups))
    JuMP.optimize!(m)

    status = JuMP.termination_status(m)
    status == JuMP.MOI.OPTIMAL || status == JuMP.MOI.TIME_LIMIT ||
        @warn "MIP did not reach OPTIMAL" status

    section_indices = Vector{Int}(undef, n_groups)
    sections = Vector{typeof(first(catalogue))}(undef, n_groups)
    for i in 1:n_groups
        # Choose argmax over feasible indices. Avoid `argmax` on JuMP's SparseAxisArray.
        vals = [JuMP.value(x[i, j]) for j in feasible[i]]
        bestj = feasible[i][argmax(vals)]
        section_indices[i] = bestj
        sections[i] = catalogue[bestj]
    end

    return (; section_indices, sections, status, objective_value=JuMP.objective_value(m))
end
