# =============================================================================
# Design Snapshot — lightweight state capture for parametric studies
# =============================================================================
#
# During design, several BuildingStructure fields are mutated:
#   - Column c1, c2, section
#   - Beam section
#   - Cell self_weight, live_load
#
# DesignSnapshot captures this mutable state so it can be restored between
# parametric runs, avoiding expensive deep copies or full re-initializations.
#
# Usage:
#   snapshot!(struc)           # save pristine state
#   <run sizing pipeline>
#   restore!(struc)            # revert to pristine state
# =============================================================================

"""
    DesignSnapshot{T, P}

Lightweight capture of mutable `BuildingStructure` fields that change during design.

Stored on `struc._snapshot` via `snapshot!(struc)`.
Restored via `restore!(struc)`.

# Captured fields
- Column dimensions (`c1`, `c2`) and sections
- Beam sections
- Cell self-weights and live loads
"""
struct DesignSnapshot{T, P}
    column_c1::Vector{Union{T, Nothing}}
    column_c2::Vector{Union{T, Nothing}}
    column_sections::Vector{Union{AbstractSection, Nothing}}
    beam_sections::Vector{Union{AbstractSection, Nothing}}
    cell_self_weights::Vector{P}
    cell_live_loads::Vector{P}
end
