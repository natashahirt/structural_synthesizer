# AISC W-Shape Catalog

const W_CATALOG = Dict{String, ISymmSection}()

_asfloat(x::Real) = Float64(x)
_asfloat(x::AbstractString) = parse(Float64, x)
_asfloat(x) = throw(ArgumentError("Cannot parse numeric value from $(typeof(x)) = $(repr(x))"))

_maybe_asfloat(x) = ismissing(x) ? nothing : _asfloat(x)

# Conversion factors (Float64) to avoid Rational{Int64} overflow in Unitful
# for high powers (like inch^6 -> m^6)
const _IN_TO_M = 0.0254
const _IN2_TO_M2 = _IN_TO_M^2
const _IN4_TO_M4 = _IN_TO_M^4
const _IN6_TO_M6 = _IN_TO_M^6

function load_w_catalog!()
    csv_path = joinpath(@__DIR__, "data/aisc-shapes-v15.csv")
    
    for row in CSV.File(csv_path)
        row.Type == "W" || continue
        (ismissing(row.d) || ismissing(row.bf) || ismissing(row.tw) || ismissing(row.tf)) && continue
        
        # CSV.jl may return InlineStrings; coerce to String for dictionary keys and section names
        name = String(row.AISC_Manual_Label)
        
        # Load and convert to SI Base Units (Meters) using float factors
        # Explicit multiplication by u"m" applies the unit after numeric conversion
        d  = (_asfloat(row.d)  * _IN_TO_M) * u"m"
        bf = (_asfloat(row.bf) * _IN_TO_M) * u"m"
        tw = (_asfloat(row.tw) * _IN_TO_M) * u"m"
        tf = (_asfloat(row.tf) * _IN_TO_M) * u"m"
        
        # Database values (more accurate than thin-walled approximations)
        Jv   = _maybe_asfloat(row.J)
        J_db = Jv === nothing ? nothing : (Jv * _IN4_TO_M4) * u"m^4"

        Cwv   = _maybe_asfloat(row.Cw)
        Cw_db = Cwv === nothing ? nothing : (Cwv * _IN6_TO_M6) * u"m^6"

        rtsv   = _maybe_asfloat(row.rts)
        rts_db = rtsv === nothing ? nothing : (rtsv * _IN_TO_M) * u"m"

        hov   = _maybe_asfloat(row.ho)
        ho_db = hov === nothing ? nothing : (hov * _IN_TO_M) * u"m"
        
        W_CATALOG[name] = ISymmSection(d, bf, tw, tf; 
            name=name, J_db=J_db, Cw_db=Cw_db, rts_db=rts_db, ho_db=ho_db)
    end
    @debug "Loaded $(length(W_CATALOG)) W sections (SI units)"
end

"""Get W section by AISC name (e.g., "W10X22")."""
function W(name::String)
    isempty(W_CATALOG) && load_w_catalog!()
    haskey(W_CATALOG, name) || error("W section '$name' not found")
    return W_CATALOG[name]
end

W_names() = (isempty(W_CATALOG) && load_w_catalog!(); collect(keys(W_CATALOG)))
all_W() = (isempty(W_CATALOG) && load_w_catalog!(); collect(values(W_CATALOG)))
