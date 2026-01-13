# AISC W-Shape Catalog

const W_CATALOG = Dict{String, ISymmSection}()

function load_w_catalog!()
    csv_path = joinpath(@__DIR__, "data/aisc-shapes-v15.csv")
    
    for row in CSV.File(csv_path)
        row.Type == "W" || continue
        (ismissing(row.d) || ismissing(row.bf) || ismissing(row.tw) || ismissing(row.tf)) && continue
        
        name = string(row.AISC_Manual_Label)
        d  = row.d * u"inch"
        bf = row.bf * u"inch"
        tw = row.tw * u"inch"
        tf = row.tf * u"inch"
        
        # Database values (more accurate than thin-walled approximations)
        J_db   = ismissing(row.J)   ? nothing : row.J * u"inch^4"
        Cw_db  = ismissing(row.Cw)  ? nothing : row.Cw * u"inch^6"
        rts_db = ismissing(row.rts) ? nothing : row.rts * u"inch"
        ho_db  = ismissing(row.ho)  ? nothing : row.ho * u"inch"
        
        W_CATALOG[name] = ISymmSection(d, bf, tw, tf; 
            name=name, J_db=J_db, Cw_db=Cw_db, rts_db=rts_db, ho_db=ho_db)
    end
    @debug "Loaded $(length(W_CATALOG)) W sections"
end

"""Get W section by AISC name (e.g., "W10X22")."""
function W(name::String)
    isempty(W_CATALOG) && load_w_catalog!()
    haskey(W_CATALOG, name) || error("W section '$name' not found")
    return W_CATALOG[name]
end

W_names() = (isempty(W_CATALOG) && load_w_catalog!(); collect(keys(W_CATALOG)))
all_W() = (isempty(W_CATALOG) && load_w_catalog!(); collect(values(W_CATALOG)))
