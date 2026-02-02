# AISC HSS (Rectangular/Square) + Round HSS Catalog Loader (v15 CSV)

using Asap: asfloat, maybe_asfloat

const HSS_RECT_CATALOG = Dict{String, HSSRectSection}()
const HSS_ROUND_CATALOG = Dict{String, HSSRoundSection}()

# Conversion factors (Float64) to avoid Rational overflow with Unitful at high powers
const _IN_TO_M   = 0.0254
const _IN2_TO_M2 = _IN_TO_M^2
const _IN3_TO_M3 = _IN_TO_M^3
const _IN4_TO_M4 = _IN_TO_M^4

function load_hss_rect_catalog!()
    csv_path = joinpath(@__DIR__, "data/aisc-shapes-v15.csv")
    for row in CSV.File(csv_path)
        row.Type == "HSS" || continue
        name = String(row.AISC_Manual_Label)
        # Rectangular/square HSS have Ht and B. Round HSS should be handled separately.
        Ht = maybe_asfloat(row.Ht)
        B  = maybe_asfloat(row.B)
        t  = maybe_asfloat(row.tdes)
        (Ht === nothing || B === nothing || t === nothing) && continue

        # Required properties
        A  = maybe_asfloat(row.A)
        Ix = maybe_asfloat(row.Ix)
        Iy = maybe_asfloat(row.Iy)
        Sx = maybe_asfloat(row.Sx)
        Sy = maybe_asfloat(row.Sy)
        Zx = maybe_asfloat(row.Zx)
        Zy = maybe_asfloat(row.Zy)
        J  = maybe_asfloat(row.J)
        rx = maybe_asfloat(row.rx)
        ry = maybe_asfloat(row.ry)

        (A === nothing || Ix === nothing || Iy === nothing || Sx === nothing || Sy === nothing ||
         Zx === nothing || Zy === nothing || J === nothing || rx === nothing || ry === nothing) && continue

        # Convert to SI and store
        H = (Ht * _IN_TO_M) * u"m"
        Bm = (B * _IN_TO_M) * u"m"
        tm = (t * _IN_TO_M) * u"m"

        Am  = (A * _IN2_TO_M2) * u"m^2"
        Ixm = (Ix * _IN4_TO_M4) * u"m^4"
        Iym = (Iy * _IN4_TO_M4) * u"m^4"
        Sxm = (Sx * _IN3_TO_M3) * u"m^3"
        Sym = (Sy * _IN3_TO_M3) * u"m^3"
        Zxm = (Zx * _IN3_TO_M3) * u"m^3"
        Zym = (Zy * _IN3_TO_M3) * u"m^3"
        Jm  = (J * _IN4_TO_M4) * u"m^4"
        rxm = (rx * _IN_TO_M) * u"m"
        rym = (ry * _IN_TO_M) * u"m"

        # Use catalog constructor with database values
        HSS_RECT_CATALOG[name] = HSSRectSection(
            name, H, Bm, tm,
            Am, Ixm, Iym, Sxm, Sym, Zxm, Zym, Jm, rxm, rym,
            false  # is_preferred
        )
    end
end

function load_hss_round_catalog!()
    csv_path = joinpath(@__DIR__, "data/aisc-shapes-v15.csv")
    for row in CSV.File(csv_path)
        row.Type == "PIPE" || continue
        name = String(row.AISC_Manual_Label)

        OD = maybe_asfloat(row.OD)
        ID = maybe_asfloat(row.ID)
        t  = maybe_asfloat(row.tdes)
        (OD === nothing || t === nothing) && continue
        ID === nothing && (ID = OD - 2t)

        # Required properties
        A  = maybe_asfloat(row.A)
        Ix = maybe_asfloat(row.Ix)
        Sx = maybe_asfloat(row.Sx)
        Zx = maybe_asfloat(row.Zx)
        J  = maybe_asfloat(row.J)
        rx = maybe_asfloat(row.rx)

        (A === nothing || Ix === nothing || Sx === nothing ||
         Zx === nothing || J === nothing || rx === nothing) && continue

        # Convert to SI
        ODm = (OD * _IN_TO_M) * u"m"
        IDm = (ID * _IN_TO_M) * u"m"
        tm  = (t * _IN_TO_M) * u"m"

        Am  = (A * _IN2_TO_M2) * u"m^2"
        Im  = (Ix * _IN4_TO_M4) * u"m^4"  # I = Ix = Iy for round
        Sm  = (Sx * _IN3_TO_M3) * u"m^3"  # S = Sx = Sy
        Zm  = (Zx * _IN3_TO_M3) * u"m^3"  # Z = Zx = Zy
        Jm  = (J * _IN4_TO_M4) * u"m^4"
        rm  = (rx * _IN_TO_M) * u"m"      # r = rx = ry

        # Use catalog constructor
        HSS_ROUND_CATALOG[name] = HSSRoundSection(
            name, ODm, IDm, tm,
            Am, Im, Sm, Zm, Jm, rm,
            false  # is_preferred
        )
    end
end

# =============================================================================
# Accessors
# =============================================================================

"""Get rectangular/square HSS section by AISC name (e.g., "HSS20X20X3/4")."""
function HSS(name::String)
    isempty(HSS_RECT_CATALOG) && load_hss_rect_catalog!()
    haskey(HSS_RECT_CATALOG, name) || error("HSS section '$name' not found")
    return HSS_RECT_CATALOG[name]
end

"""Get round HSS (pipe) section by AISC name (e.g., "Pipe8STD")."""
function HSSRound(name::String)
    isempty(HSS_ROUND_CATALOG) && load_hss_round_catalog!()
    haskey(HSS_ROUND_CATALOG, name) || error("Round HSS (PIPE) section '$name' not found")
    return HSS_ROUND_CATALOG[name]
end

# Alias for backwards compatibility
const PIPE = HSSRound

HSS_names() = (isempty(HSS_RECT_CATALOG) && load_hss_rect_catalog!(); collect(keys(HSS_RECT_CATALOG)))
HSSRound_names() = (isempty(HSS_ROUND_CATALOG) && load_hss_round_catalog!(); collect(keys(HSS_ROUND_CATALOG)))
PIPE_names() = HSSRound_names()  # Alias

all_HSS() = (isempty(HSS_RECT_CATALOG) && load_hss_rect_catalog!(); collect(values(HSS_RECT_CATALOG)))
all_HSSRound() = (isempty(HSS_ROUND_CATALOG) && load_hss_round_catalog!(); collect(values(HSS_ROUND_CATALOG)))
all_PIPE() = all_HSSRound()  # Alias
