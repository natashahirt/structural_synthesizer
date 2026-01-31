# ==============================================================================
# Column Sizing API
# ==============================================================================
# Clean, type-dispatched interface for column sizing.
# One function, material-specific options types.

# ==============================================================================
# Main API: size_columns
# ==============================================================================

"""
    size_columns(Pu, Mux, geometries, opts::SteelColumnOptions; Muy=zeros(...))
    size_columns(Pu, Mux, geometries, opts::ConcreteColumnOptions; Muy=zeros(...))

Size columns using the specified options.

# Arguments
- `Pu`: Factored axial loads (positive = compression)
  - Steel: Newtons
  - Concrete: kip
- `Mux`: Factored moments about x-axis
  - Steel: Newton-meters
  - Concrete: kip-ft
- `geometries`: Member geometries (auto-converted as needed)
- `opts`: `SteelColumnOptions` or `ConcreteColumnOptions`

# Keyword Arguments
- `Muy`: Factored moments about y-axis (default: zeros)

# Returns
Named tuple with:
- `sections`: Optimal sections (one per member)
- `section_indices`: Indices into catalog
- `status`: Solver status
- `objective_value`: Final objective value

# Example
```julia
# Steel W columns (all defaults)
result = size_columns(Pu_N, Mux_Nm, geometries, SteelColumnOptions())

# Steel HSS with depth limit
result = size_columns(Pu_N, Mux_Nm, geometries, SteelColumnOptions(
    section_type = :hss,
    max_depth = 0.4,
))

# Concrete columns with biaxial
result = size_columns(Pu_kip, Mux_kipft, geometries, ConcreteColumnOptions(
    grade = NWC_5000,
); Muy = Muy_kipft)
```
"""
function size_columns end

# ==============================================================================
# Steel Implementation
# ==============================================================================

function size_columns(
    Pu::Vector,
    Mux::Vector,
    geometries::Vector,
    opts::SteelColumnOptions;
    Muy::Vector = zeros(length(Pu)),
    mip_gap::Real = 1e-4,
    output_flag::Integer = 0,
)
    n = length(Pu)
    n == length(Mux) || throw(ArgumentError("Pu and Mux must have same length"))
    n == length(geometries) || throw(ArgumentError("demands and geometries must have same length"))
    
    # Convert geometries if needed
    steel_geoms = [to_steel_geometry(g) for g in geometries]
    
    # Build catalog
    cat = isnothing(opts.custom_catalog) ? 
        steel_column_catalog(opts.section_type, opts.catalog) : 
        opts.custom_catalog
    
    # Build demands
    demands = [MemberDemand(i; Pu_c=Pu[i], Mux=Mux[i], Muy=Muy[i]) for i in 1:n]
    
    # Create checker
    checker = AISCChecker(; max_depth = opts.max_depth)
    
    # Optimize
    return optimize_discrete(
        checker, demands, steel_geoms, cat, opts.material;
        objective = opts.objective,
        n_max_sections = opts.n_max_sections,
        optimizer = opts.optimizer,
        mip_gap = mip_gap,
        output_flag = output_flag,
    )
end

# ==============================================================================
# Concrete Implementation
# ==============================================================================

function size_columns(
    Pu::Vector,
    Mux::Vector,
    geometries::Vector,
    opts::ConcreteColumnOptions;
    Muy::Vector = zeros(length(Pu)),
    mip_gap::Real = 1e-4,
    output_flag::Integer = 0,
)
    n = length(Pu)
    n == length(Mux) || throw(ArgumentError("Pu and Mux must have same length"))
    n == length(geometries) || throw(ArgumentError("demands and geometries must have same length"))
    
    # Convert geometries if needed
    conc_geoms = [to_concrete_geometry(g) for g in geometries]
    
    # Build catalog (with section_shape dispatch)
    cat = isnothing(opts.custom_catalog) ? 
        rc_column_catalog(opts.section_shape, opts.catalog) : 
        opts.custom_catalog
    
    # Build demands
    demands = [RCColumnDemand(i; Pu=Pu[i], Mux=Mux[i], Muy=Muy[i], βdns=opts.βdns) for i in 1:n]
    
    # Create checker
    checker = ACIColumnChecker(;
        include_slenderness = opts.include_slenderness,
        include_biaxial = opts.include_biaxial,
        fy_ksi = opts.rebar_fy_ksi,
        max_depth = opts.max_depth,
    )
    
    # Optimize
    return optimize_discrete(
        checker, demands, conc_geoms, cat, opts.grade;
        objective = opts.objective,
        n_max_sections = opts.n_max_sections,
        optimizer = opts.optimizer,
        mip_gap = mip_gap,
        output_flag = output_flag,
    )
end

# ==============================================================================
# Geometry Converters
# ==============================================================================

"""
    to_steel_geometry(geom) -> SteelMemberGeometry

Convert any geometry to steel geometry.
"""
function to_steel_geometry(geom::ConcreteMemberGeometry)
    SteelMemberGeometry(geom.L; Lb=geom.Lu, Kx=geom.k, Ky=geom.k)
end
to_steel_geometry(geom::SteelMemberGeometry) = geom

"""
    to_concrete_geometry(geom) -> ConcreteMemberGeometry

Convert any geometry to concrete geometry.
"""
function to_concrete_geometry(geom::SteelMemberGeometry)
    ConcreteMemberGeometry(geom.L; Lu=geom.Lb, k=geom.Ky)
end
to_concrete_geometry(geom::ConcreteMemberGeometry) = geom

"""
    convert_geometries(geometries, target::Symbol)

Convert geometries to target type (`:steel` or `:concrete`).
"""
function convert_geometries(geometries::Vector, target::Symbol)
    if target === :steel
        return [to_steel_geometry(g) for g in geometries]
    elseif target === :concrete
        return [to_concrete_geometry(g) for g in geometries]
    else
        throw(ArgumentError("Unknown target=$target. Use :steel or :concrete"))
    end
end

# ==============================================================================
# Demand Converters
# ==============================================================================

"""
    to_steel_demands(demands) -> Vector{MemberDemand}

Convert RC demands to steel demands.
"""
function to_steel_demands(demands::Vector{<:RCColumnDemand})
    [MemberDemand(d.member_idx; Pu_c=d.Pu, Mux=d.Mux, Muy=d.Muy) for d in demands]
end
to_steel_demands(demands::Vector{<:MemberDemand}) = demands

"""
    to_rc_demands(demands; βdns=0.6) -> Vector{RCColumnDemand}

Convert steel demands to RC demands.
"""
function to_rc_demands(demands::Vector{<:MemberDemand}; βdns=0.6)
    [RCColumnDemand(d.member_idx; Pu=d.Pu_c, Mux=d.Mux, Muy=d.Muy, βdns=βdns) for d in demands]
end
to_rc_demands(demands::Vector{<:RCColumnDemand}; βdns=nothing) = demands
