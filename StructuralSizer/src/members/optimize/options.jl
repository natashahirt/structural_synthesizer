# ==============================================================================
# Member Sizing Options
# ==============================================================================
# Clean, material-specific configuration for column and beam sizing.
# Each type has sensible defaults - override only what you need.

# ==============================================================================
# Steel Column Options
# ==============================================================================

"""
    SteelColumnOptions

Configuration for steel column sizing.

# Example
```julia
# Use all defaults (W shapes, A992 steel)
opts = SteelColumnOptions()

# HSS columns with depth limit
opts = SteelColumnOptions(
    section_type = :hss,
    max_depth = 0.4,  # meters
)

# Combined W + HSS catalog
opts = SteelColumnOptions(section_type = :w_and_hss)
```

# Fields
- `material`: Steel grade (default: A992_Steel)
- `section_type`: `:w`, `:hss`, `:pipe`, `:w_and_hss` (default: `:w`)
- `catalog`: `:common`, `:preferred`, `:all` (default: `:preferred`)
- `custom_catalog`: Custom section vector (overrides catalog)
- `max_depth`: Maximum depth in meters (default: Inf)
- `n_max_sections`: Limit unique sections, 0 = no limit (default: 0)
- `objective`: MinVolume(), MinWeight(), MinCost(), MinCarbon() (default: MinVolume())
- `optimizer`: `:auto`, `:highs`, `:gurobi` (default: `:auto`)
"""
Base.@kwdef struct SteelColumnOptions
    material::StructuralSteel = A992_Steel
    section_type::Symbol = :w           # :w, :hss, :pipe, :w_and_hss
    catalog::Symbol = :preferred        # :common, :preferred, :all
    custom_catalog::Union{Nothing, Vector} = nothing
    max_depth::Float64 = Inf            # meters
    n_max_sections::Int = 0             # 0 = no limit
    objective::AbstractObjective = MinVolume()
    optimizer::Symbol = :auto           # :auto, :highs, :gurobi
end

# ==============================================================================
# Concrete Column Options
# ==============================================================================

"""
    ConcreteColumnOptions

Configuration for reinforced concrete column sizing.

# Example
```julia
# Use all defaults (4000 psi, rectangular, slenderness + biaxial enabled)
opts = ConcreteColumnOptions()

# Circular spiral columns
opts = ConcreteColumnOptions(section_shape = :circular)

# High-strength rectangular with depth limit
opts = ConcreteColumnOptions(
    grade = NWC_6000,
    section_shape = :rect,
    max_depth = 0.6,  # meters
)
```

# Fields
- `grade`: Concrete material (default: NWC_4000)
- `section_shape`: `:rect` or `:circular` (default: `:rect`)
- `rebar_fy_ksi`: Rebar yield strength in ksi (default: 60.0)
- `catalog`: `:common`, `:all` (default: `:common`)
- `custom_catalog`: Custom section vector (overrides catalog)
- `max_depth`: Maximum depth/diameter in meters (default: Inf)
- `n_max_sections`: Limit unique sections, 0 = no limit (default: 0)
- `include_slenderness`: Consider slenderness effects (default: true)
- `include_biaxial`: Consider biaxial bending (default: true)
- `βdns`: Sustained load ratio for slenderness (default: 0.6)
- `objective`: MinVolume(), MinWeight(), MinCost(), MinCarbon() (default: MinVolume())
- `optimizer`: `:auto`, `:highs`, `:gurobi` (default: `:auto`)
"""
Base.@kwdef struct ConcreteColumnOptions
    grade::Concrete = NWC_4000
    section_shape::Symbol = :rect       # :rect or :circular
    rebar_fy_ksi::Float64 = 60.0
    catalog::Symbol = :common           # :common, :all
    custom_catalog::Union{Nothing, Vector} = nothing
    max_depth::Float64 = Inf            # meters (depth for rect, diameter for circular)
    n_max_sections::Int = 0             # 0 = no limit
    include_slenderness::Bool = true
    include_biaxial::Bool = true
    βdns::Float64 = 0.6
    objective::AbstractObjective = MinVolume()
    optimizer::Symbol = :auto
end

# ==============================================================================
# Steel Beam Options
# ==============================================================================

"""
    SteelBeamOptions

Configuration for steel beam sizing.

# Example
```julia
# Standard floor beams (L/360)
opts = SteelBeamOptions()

# Strict deflection for sensitive equipment
opts = SteelBeamOptions(deflection_limit = 1/480)

# Roof beams
opts = SteelBeamOptions(deflection_limit = 1/240)
```

# Fields
- `material`: Steel grade (default: A992_Steel)
- `catalog`: `:common`, `:all` (default: `:common`)
- `custom_catalog`: Custom section vector (overrides catalog)
- `max_depth`: Maximum depth in meters (default: Inf)
- `deflection_limit`: L/δ limit as fraction (default: 1/360)
- `n_max_sections`: Limit unique sections, 0 = no limit (default: 0)
- `objective`: MinVolume(), MinWeight(), MinCost(), MinCarbon() (default: MinVolume())
- `optimizer`: `:auto`, `:highs`, `:gurobi` (default: `:auto`)
"""
Base.@kwdef struct SteelBeamOptions
    material::StructuralSteel = A992_Steel
    catalog::Symbol = :common
    custom_catalog::Union{Nothing, Vector} = nothing
    max_depth::Float64 = Inf
    deflection_limit::Float64 = 1/360
    n_max_sections::Int = 0
    objective::AbstractObjective = MinVolume()
    optimizer::Symbol = :auto
end

# ==============================================================================
# Union Type for Dispatch
# ==============================================================================

"""Column sizing options (either steel or concrete)."""
const ColumnOptions = Union{SteelColumnOptions, ConcreteColumnOptions}

# ==============================================================================
# Display
# ==============================================================================

function Base.show(io::IO, opts::SteelColumnOptions)
    mat_str = material_name(opts.material)
    sec_type = uppercase(string(opts.section_type))
    print(io, "SteelColumnOptions(", mat_str, " ", sec_type)
    opts.max_depth < Inf && print(io, ", max_depth=", opts.max_depth, "m")
    opts.n_max_sections > 0 && print(io, ", n_max=", opts.n_max_sections)
    print(io, ")")
end

function Base.show(io::IO, opts::ConcreteColumnOptions)
    mat_str = material_name(opts.grade)
    shape_str = opts.section_shape == :circular ? "CIRCULAR" : "RECT"
    print(io, "ConcreteColumnOptions(", mat_str, " ", shape_str)
    opts.max_depth < Inf && print(io, ", max_depth=", opts.max_depth, "m")
    opts.n_max_sections > 0 && print(io, ", n_max=", opts.n_max_sections)
    !opts.include_slenderness && print(io, ", no_slenderness")
    !opts.include_biaxial && print(io, ", no_biaxial")
    print(io, ")")
end

function Base.show(io::IO, opts::SteelBeamOptions)
    mat_str = material_name(opts.material)
    print(io, "SteelBeamOptions(", mat_str)
    opts.max_depth < Inf && print(io, ", max_depth=", opts.max_depth, "m")
    print(io, ", L/", Int(round(1/opts.deflection_limit)))
    opts.n_max_sections > 0 && print(io, ", n_max=", opts.n_max_sections)
    print(io, ")")
end

# ==============================================================================
# Catalog Builders
# ==============================================================================

"""
    steel_column_catalog(section_type, catalog) -> Vector{<:AbstractSection}

Build a steel column catalog based on section type.

# Arguments
- `section_type`: `:w`, `:hss`, `:pipe`, `:w_and_hss`
- `catalog`: `:common`, `:all`, `:preferred`

# Examples
```julia
steel_column_catalog(:hss, :all)          # All rectangular HSS
steel_column_catalog(:w_and_hss, :preferred)  # Preferred W + all HSS
```
"""
function steel_column_catalog(section_type::Symbol, catalog::Symbol)
    if section_type === :w
        if catalog === :preferred
            return preferred_W()
        else  # :common or :all
            return all_W()
        end
    elseif section_type === :hss
        return all_HSS()
    elseif section_type === :pipe
        return all_HSSRound()
    elseif section_type === :w_and_hss
        w_sections = catalog === :preferred ? preferred_W() : all_W()
        hss_sections = all_HSS()
        return vcat(w_sections, hss_sections)
    else
        throw(ArgumentError("Unknown section_type=$section_type. Use :w, :hss, :pipe, or :w_and_hss"))
    end
end

"""
    rc_column_catalog(section_shape, catalog) -> Vector{<:AbstractSection}

Build an RC column catalog.

# Arguments
- `section_shape`: `:rect` or `:circular`
- `catalog`: `:common` or `:all`

# Examples
```julia
rc_column_catalog(:rect, :common)      # Common rectangular columns
rc_column_catalog(:circular, :all)     # All circular columns
```
"""
function rc_column_catalog(section_shape::Symbol, catalog::Symbol)
    if section_shape === :rect
        if catalog === :common
            return common_rc_rect_columns()
        elseif catalog === :all
            return all_rc_rect_columns()
        else
            throw(ArgumentError("Unknown catalog=$catalog. Use :common or :all"))
        end
    elseif section_shape === :circular
        if catalog === :common
            return common_rc_circular_columns()
        elseif catalog === :all
            return all_rc_circular_columns()
        else
            throw(ArgumentError("Unknown catalog=$catalog. Use :common or :all"))
        end
    else
        throw(ArgumentError("Unknown section_shape=$section_shape. Use :rect or :circular"))
    end
end

# Legacy single-argument version (defaults to rectangular)
function rc_column_catalog(catalog::Symbol)
    rc_column_catalog(:rect, catalog)
end
