# ==============================================================================
# Steel Headed Stud Anchor Strength — AISC 360-16 Section I8.2a
# ==============================================================================

# ==============================================================================
# Single-Stud Nominal Shear Strength
# ==============================================================================

"""
    get_Qn(anchor::HeadedStudAnchor, slab::SolidSlabOnBeam) -> Force

Nominal shear strength of one steel headed stud anchor in a solid slab per AISC I8.2a (Eq. I8-1):

    Qn = 0.5 × Asa × √(fc′ × Ec) ≤ Rg × Rp × Asa × Fu

For solid slabs: Rg = 1.0, Rp = 0.75 (AISC I8.2a User Note table).
"""
function get_Qn(anchor::HeadedStudAnchor, slab::SolidSlabOnBeam)
    Asa = π / 4 * anchor.d_sa^2
    Rg, Rp = _Rg_Rp(anchor, slab)

    # Eq. I8-1: Qn = 0.5 Asa √(fc′ Ec) ≤ Rg Rp Asa Fu
    Qn_concrete = 0.5 * Asa * sqrt(slab.fc′ * slab.Ec)
    Qn_steel    = Rg * Rp * Asa * anchor.Fu
    return min(Qn_concrete, Qn_steel)
end

"""
    get_Qn(anchor::HeadedStudAnchor, slab::DeckSlabOnBeam) -> Force

Nominal shear strength for deck slab configuration. Deck modifies Rg and Rp per AISC I8.2a.
"""
function get_Qn(anchor::HeadedStudAnchor, slab::DeckSlabOnBeam)
    Asa = π / 4 * anchor.d_sa^2
    Rg, Rp = _Rg_Rp(anchor, slab)

    Qn_concrete = 0.5 * Asa * sqrt(slab.fc′ * slab.Ec)
    Qn_steel    = Rg * Rp * Asa * anchor.Fu
    return min(Qn_concrete, Qn_steel)
end

# ==============================================================================
# Rg and Rp Factors (AISC I8.2a)
# ==============================================================================

"""Rg and Rp for solid slab — no deck (AISC I8.2a User Note table, "No decking" row)."""
function _Rg_Rp(::HeadedStudAnchor, ::SolidSlabOnBeam)
    return (1.0, 0.75)
end

"""
Rg and Rp for deck slab — depends on orientation, rib geometry, and studs per rib.

Reference: AISC I8.2a User Note table.
"""
function _Rg_Rp(anchor::HeadedStudAnchor, slab::DeckSlabOnBeam)
    if slab.deck_orientation === :parallel
        ratio = ustrip(slab.wr / slab.hr)
        if ratio >= 1.5
            return (1.0, 0.75)
        else
            return (0.85, 0.75)
        end
    else  # :perpendicular
        n = anchor.n_per_row
        Rp = 0.6  # default; may be 0.75 when e_mid_ht ≥ 2 in. (conservative default)
        if n == 1
            Rg = 1.0
        elseif n == 2
            Rg = 0.85
        else
            Rg = 0.7
        end
        return (Rg, Rp)
    end
end

# ==============================================================================
# Stud Validation Checks
# ==============================================================================

"""
    validate_stud_diameter(anchor::HeadedStudAnchor, tf) -> nothing

AISC I8.1: Stud diameter shall not exceed 2.5 × flange thickness,
unless welded to a flange directly over a web.
Throws `ArgumentError` if violated.
"""
function validate_stud_diameter(anchor::HeadedStudAnchor, tf)
    d_max = 2.5 * tf
    if anchor.d_sa > d_max
        throw(ArgumentError(
            "Stud diameter $(anchor.d_sa) exceeds 2.5×tf = $(d_max) " *
            "(AISC I8.1). Use a smaller stud or verify stud is welded directly over the web."))
    end
    return nothing
end

"""
    validate_stud_length(anchor::HeadedStudAnchor, slab::AbstractSlabOnBeam) -> nothing

AISC I8.2: Stud length ≥ 4 × stud diameter (base to top of head, after installation).
Also checks minimum concrete cover of ½ in. (13 mm) above the stud head (AISC I3.2c(1)(b)).
"""
function validate_stud_length(anchor::HeadedStudAnchor, slab::AbstractSlabOnBeam)
    min_length = 4 * anchor.d_sa
    if anchor.l_sa < min_length
        throw(ArgumentError(
            "Stud length $(anchor.l_sa) < 4×d_sa = $(min_length) (AISC I8.2)."))
    end
    min_cover = 0.5u"inch"
    available_depth = _available_embed_depth(slab)
    if anchor.l_sa + min_cover > available_depth
        throw(ArgumentError(
            "Stud length $(anchor.l_sa) + ½ in. cover exceeds available slab depth $(available_depth)."))
    end
    return nothing
end

_available_embed_depth(slab::SolidSlabOnBeam) = slab.t_slab
_available_embed_depth(slab::DeckSlabOnBeam)  = slab.t_slab + slab.hr  # concrete above deck + rib

"""
    check_stud_spacing(anchor::HeadedStudAnchor, slab::AbstractSlabOnBeam, n_studs, L_beam) -> nothing

Verify stud longitudinal spacing per AISC I8.2d:
  (d) Minimum center-to-center = max(6 × d_sa along beam, 4 × d_sa any direction)
  (e) Maximum center-to-center = min(8 × t_slab, 36 in.)

`n_studs` is total studs on ONE side of the point of maximum moment.
"""
function check_stud_spacing(anchor::HeadedStudAnchor, slab::AbstractSlabOnBeam, n_studs::Int, L_half)
    if n_studs <= 1
        return nothing
    end

    n_rows = ceil(Int, n_studs / anchor.n_per_row)
    spacing = L_half / n_rows

    # AISC I8.2d(d): minimum spacing — 6d_sa longitudinal for solid slab, 4d_sa any direction
    s_min = max(6 * anchor.d_sa, 4 * anchor.d_sa)
    if spacing < s_min
        @warn "Stud spacing $(spacing) < minimum $(s_min) (AISC I8.2d). Consider fewer studs or multi-row layout."
    end

    # AISC I8.2d(e): maximum spacing
    s_max = min(8 * slab.t_slab, 36.0u"inch")
    if spacing > s_max
        @warn "Stud spacing $(spacing) > maximum $(s_max) (AISC I8.2d). Add more studs."
    end

    return nothing
end
