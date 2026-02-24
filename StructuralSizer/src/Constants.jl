# =============================================================================
# StructuralSizer Constants
# =============================================================================
# Structural engineering constants for design and analysis.

module Constants

using Unitful
using Asap: Torque, Force, Length, Pressure, Area, psf

# =============================================================================
# Solver/Optimization Constants
# =============================================================================

const BIG_M = 1e9

export BIG_M

# =============================================================================
# ACI 318-11 Code Constants
# =============================================================================

# §10.6.4 — Crack control stress limit (psi)
const ACI_CRACK_CONTROL_FS_PSI = 40000

export ACI_CRACK_CONTROL_FS_PSI

# PCA Notes on ACI 318-11 — Prismatic Stiffness Factors
# Geometry-dependent k, COF, m are computed via pca_slab_beam_factors() and
# pca_column_factors() in codes/aci/pca_tables.jl.

# PCA Notes on ACI 318-11 — Non-Prismatic Factors (Flat Slab)
# Geometry-dependent k, COF, FEM are computed via pca_slab_beam_factors_np()
# and pca_column_factors() in codes/aci/pca_tables.jl (Tables A2–A5, A7).

# =============================================================================
# Load factors: use LoadCombination from loads/combinations.jl
# (DL_FACTOR / LL_FACTOR removed — replaced by default_combo.D / .L)
# =============================================================================

# =============================================================================
# Standard Units (for consistent internal representation)
# =============================================================================

const STANDARD_LENGTH = u"m"
const STANDARD_AREA = u"m^2"
const STANDARD_FORCE = u"kN"
const STANDARD_PRESSURE = u"kN/m^2"

export STANDARD_LENGTH, STANDARD_AREA, STANDARD_FORCE, STANDARD_PRESSURE

# =============================================================================
# Vector Helpers
end # module
