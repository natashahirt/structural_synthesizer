# =============================================================================
# Shear Stud Catalogs — Physical Dimensions for Headed Shear Stud Products
# =============================================================================
#
# All design uses ACI 318 equations.  Catalogs only constrain physical stud
# dimensions: shank diameter, head diameter, head thickness, head area.
#
# Sources:
#   INCON ISS — INCON-ISS-Shear-Studs-Catalog.pdf, Page 7 (Imperial table)
#   Ancon Shearfix — Shearfix_Punching_Shear_Reinforcement.pdf, p.3
#
# =============================================================================

using Unitful
using Unitful: @u_str
using Asap: Length, Area

"""
    StudSpec

Physical specification for a single headed shear stud size from a manufacturer.

All design calculations (ACI 318 §11.11.5) use only `shank_diameter` and
`head_area`.  The remaining fields are for detailing / drawing output.

Lengths and areas are stored in **concrete Unitful types** (not parametric)
so that catalog vectors are concretely typed `Vector{StudSpec}`.

# Fields
- `catalog::Symbol`                — Manufacturer key, e.g. `:incon_iss`, `:ancon_shearfix`, `:generic`
- `shank_diameter::typeof(1.0u"m")` — Nominal shank (bar) diameter
- `head_diameter::typeof(1.0u"m")`  — Forged head diameter
- `head_thickness::typeof(1.0u"m")` — Head plate thickness
- `head_area::typeof(1.0u"m^2")`    — Cross-sectional area of the **shank** (used in Av calc)
"""
struct StudSpec
    catalog::Symbol
    shank_diameter::typeof(1.0u"m")
    head_diameter::typeof(1.0u"m")
    head_thickness::typeof(1.0u"m")
    head_area::typeof(1.0u"m^2")
end

"""Convenience constructor: auto-convert any Length/Area to canonical meter/m² units."""
function StudSpec(catalog::Symbol, d::Length, hd::Length, ht::Length, ha::Area)
    StudSpec(catalog,
             uconvert(u"m", d),
             uconvert(u"m", hd),
             uconvert(u"m", ht),
             uconvert(u"m^2", ha))
end

function Base.show(io::IO, s::StudSpec)
    d_in = round(ustrip(u"inch", s.shank_diameter), digits=3)
    print(io, "StudSpec($(s.catalog), d=$(d_in)\")")
end

# ---------------------------------------------------------------------------
# Built-in catalogs
# ---------------------------------------------------------------------------

"""
    INCON_ISS_CATALOG :: Vector{StudSpec}

INCON ISS headed shear studs — imperial sizes.

Source: INCON-ISS-Shear-Studs-Catalog.pdf, Page 7
"Sizes and Dimensions of ISS – Shear Studs (Imperial Units)"

| Shank ∅ | Head ∅ | Head t | Head A (in²) |
|---------|--------|--------|--------------|
| 3/8"    | 1"     | 3/16"  | 0.11         |
| 1/2"    | 1-1/4" | 1/4"   | 0.20         |
| 5/8"    | 1-1/2" | 5/16"  | 0.31         |
| 3/4"    | 1-3/4" | 3/8"   | 0.44         |
| 7/8"    | 2"     | 7/16"  | 0.60         |
"""
const INCON_ISS_CATALOG = [
    StudSpec(:incon_iss, 0.375u"inch", 1.000u"inch", 0.1875u"inch", 0.11u"inch^2"),
    StudSpec(:incon_iss, 0.500u"inch", 1.250u"inch", 0.2500u"inch", 0.20u"inch^2"),
    StudSpec(:incon_iss, 0.625u"inch", 1.500u"inch", 0.3125u"inch", 0.31u"inch^2"),
    StudSpec(:incon_iss, 0.750u"inch", 1.750u"inch", 0.3750u"inch", 0.44u"inch^2"),
    StudSpec(:incon_iss, 0.875u"inch", 2.000u"inch", 0.4375u"inch", 0.60u"inch^2"),
]

"""
    ANCON_SHEARFIX_CATALOG :: Vector{StudSpec}

Ancon Shearfix headed shear studs — metric sizes converted to imperial.

Source: Shearfix_Punching_Shear_Reinforcement.pdf, p.3
"Available in 10, 12, 14, 16, 20 and 25mm diameters"
Heads are forged to 3× the bar diameter.

Head thickness assumed ≈ 0.5 × shank diameter (standard practice).
Head area = π d²/4 (shank cross-sectional area).
"""
const ANCON_SHEARFIX_CATALOG = [
    # 10 mm ≈ 0.394"
    StudSpec(:ancon_shearfix, 10.0u"mm", 30.0u"mm", 5.0u"mm",
             π * (10.0u"mm")^2 / 4),
    # 12 mm ≈ 0.472"
    StudSpec(:ancon_shearfix, 12.0u"mm", 36.0u"mm", 6.0u"mm",
             π * (12.0u"mm")^2 / 4),
    # 14 mm ≈ 0.551"
    StudSpec(:ancon_shearfix, 14.0u"mm", 42.0u"mm", 7.0u"mm",
             π * (14.0u"mm")^2 / 4),
    # 16 mm ≈ 0.630"
    StudSpec(:ancon_shearfix, 16.0u"mm", 48.0u"mm", 8.0u"mm",
             π * (16.0u"mm")^2 / 4),
    # 20 mm ≈ 0.787"
    StudSpec(:ancon_shearfix, 20.0u"mm", 60.0u"mm", 10.0u"mm",
             π * (20.0u"mm")^2 / 4),
    # 25 mm ≈ 0.984"
    StudSpec(:ancon_shearfix, 25.0u"mm", 75.0u"mm", 12.5u"mm",
             π * (25.0u"mm")^2 / 4),
]

"""
    GENERIC_STUD_CATALOG :: Vector{StudSpec}

Generic headed shear studs — standard imperial sizes with π d²/4 head areas.
Used when no specific manufacturer is selected (`:generic`).
"""
const GENERIC_STUD_CATALOG = [
    StudSpec(:generic, 0.375u"inch", 1.000u"inch", 0.1875u"inch",
             π * (0.375u"inch")^2 / 4),
    StudSpec(:generic, 0.500u"inch", 1.250u"inch", 0.2500u"inch",
             π * (0.500u"inch")^2 / 4),
    StudSpec(:generic, 0.625u"inch", 1.500u"inch", 0.3125u"inch",
             π * (0.625u"inch")^2 / 4),
    StudSpec(:generic, 0.750u"inch", 1.750u"inch", 0.3750u"inch",
             π * (0.750u"inch")^2 / 4),
    StudSpec(:generic, 0.875u"inch", 2.000u"inch", 0.4375u"inch",
             π * (0.875u"inch")^2 / 4),
]

"""
    stud_catalog(reinforcement::Symbol) -> Vector{StudSpec}

Return the stud catalog for the given `punching_reinforcement` symbol.

# Supported values
- `:headed_studs_generic`  → `GENERIC_STUD_CATALOG`
- `:headed_studs_incon`    → `INCON_ISS_CATALOG`
- `:headed_studs_ancon`    → `ANCON_SHEARFIX_CATALOG`
"""
function stud_catalog(reinforcement::Symbol)
    reinforcement === :headed_studs_incon   && return INCON_ISS_CATALOG
    reinforcement === :headed_studs_ancon   && return ANCON_SHEARFIX_CATALOG
    reinforcement === :headed_studs_generic && return GENERIC_STUD_CATALOG
    error("Unknown stud catalog: $reinforcement. " *
          "Use :headed_studs_generic, :headed_studs_incon, or :headed_studs_ancon.")
end

"""
    snap_to_catalog(catalog::Vector{StudSpec}, target_diameter::Length) -> StudSpec

Select the smallest stud in `catalog` whose shank diameter ≥ `target_diameter`.
If no stud is large enough, returns the largest available.

This lets the user request e.g. 0.5" studs and get the closest catalog product.
"""
function snap_to_catalog(catalog::Vector{StudSpec}, target_diameter::Length)
    target_in = ustrip(u"inch", target_diameter)
    
    # Sort by shank diameter ascending (catalogs are already sorted, but be safe)
    sorted = sort(catalog, by = s -> ustrip(u"inch", s.shank_diameter))
    
    for spec in sorted
        if ustrip(u"inch", spec.shank_diameter) >= target_in - 1e-6
            return spec
        end
    end
    
    # Fallback: largest available
    return sorted[end]
end
