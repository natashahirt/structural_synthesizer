# =============================================================================
# Load Combinations
# =============================================================================
# Configurable load combinations for structural design.
# Replaces hardcoded Constants.DL_FACTOR / LL_FACTOR.
#
# Standard combinations follow ASCE 7-22 strength design.
# =============================================================================

"""
    LoadCombination(; name, D, L, S, W, E)

A load combination for structural design.

# Fields
- `name::Symbol`: Identifier (e.g., :strength_1_2, :service)
- `D::Float64`: Dead load factor
- `L::Float64`: Live load factor
- `Lr::Float64`: Roof live load factor (default 0)
- `S::Float64`: Snow load factor (default 0)
- `R::Float64`: Rain load factor (default 0)
- `W::Float64`: Wind load factor (default 0)
- `E::Float64`: Earthquake load factor (default 0)

# Standard Combinations (ASCE 7-22 §2.3.1)
- `STRENGTH_1_4D`: 1.4D
- `STRENGTH_1_2D_1_6L`: 1.2D + 1.6L + 0.5(Lr or S or R)
- `STRENGTH_1_2D_1_0W`: 1.2D + 1.0W + L + 0.5(Lr or S or R)
- `STRENGTH_1_2D_1_0E`: 1.2D + 1.0E + L + 0.2S
- `STRENGTH_0_9D_1_0W`: 0.9D + 1.0W
- `STRENGTH_0_9D_1_0E`: 0.9D + 1.0E
- `ASD`: 1.0D + 1.0L (Allowable Stress Design)
- `SERVICE`: 1.0D + 1.0L (Serviceability checks)

# Examples
```julia
# Use a standard combination
combo = STRENGTH_1_2D_1_6L
p_factored = factored_pressure(combo, dead_load, live_load)

# Custom combination
custom = LoadCombination(name=:custom, D=1.35, L=1.5)  # Eurocode-ish
```
"""
Base.@kwdef struct LoadCombination
    name::Symbol = :strength
    D::Float64 = 1.2
    L::Float64 = 1.6
    Lr::Float64 = 0.0   # Roof live load
    S::Float64 = 0.0    # Snow
    R::Float64 = 0.0    # Rain
    W::Float64 = 0.0    # Wind
    E::Float64 = 0.0    # Earthquake
end

# =============================================================================
# Standard Combinations (ASCE 7-22 §2.3.1)
# =============================================================================

# Combination 1: 1.4D
const STRENGTH_1_4D = LoadCombination(
    name = :strength_1_4D,
    D = 1.4,
    L = 0.0
)

# Combination 2: 1.2D + 1.6L + 0.5(Lr or S or R)
# Note: User should set Lr, S, or R as appropriate
const STRENGTH_1_2D_1_6L = LoadCombination(
    name = :strength_1_2D_1_6L,
    D = 1.2,
    L = 1.6,
    Lr = 0.5,
    S = 0.5,
    R = 0.5
)

# Combination 3: 1.2D + 1.6(Lr or S or R) + (L or 0.5W)
const STRENGTH_1_2D_1_6Lr = LoadCombination(
    name = :strength_1_2D_1_6Lr,
    D = 1.2,
    L = 1.0,
    Lr = 1.6,
    S = 1.6,
    R = 1.6,
    W = 0.5
)

# Combination 4: 1.2D + 1.0W + L + 0.5(Lr or S or R)
const STRENGTH_1_2D_1_0W = LoadCombination(
    name = :strength_1_2D_1_0W,
    D = 1.2,
    L = 1.0,
    Lr = 0.5,
    S = 0.5,
    R = 0.5,
    W = 1.0
)

# Combination 5: 1.2D + 1.0E + L + 0.2S
const STRENGTH_1_2D_1_0E = LoadCombination(
    name = :strength_1_2D_1_0E,
    D = 1.2,
    L = 1.0,
    S = 0.2,
    E = 1.0
)

# Combination 6: 0.9D + 1.0W
const STRENGTH_0_9D_1_0W = LoadCombination(
    name = :strength_0_9D_1_0W,
    D = 0.9,
    W = 1.0
)

# Combination 7: 0.9D + 1.0E
const STRENGTH_0_9D_1_0E = LoadCombination(
    name = :strength_0_9D_1_0E,
    D = 0.9,
    E = 1.0
)

# Allowable Stress Design (ASD)
const ASD = LoadCombination(
    name = :asd,
    D = 1.0,
    L = 1.0
)

# Serviceability (unfactored for deflection checks)
const SERVICE = LoadCombination(
    name = :service,
    D = 1.0,
    L = 1.0
)

# Alias for the most common strength combination
const DEFAULT_STRENGTH = STRENGTH_1_2D_1_6L

# =============================================================================
# Factored Pressure Functions
# =============================================================================

"""
    factored_pressure(combo::LoadCombination, dead, live)

Apply load combination factors to dead and live loads.
Returns `combo.D * dead + combo.L * live`.

# Example
```julia
p_u = factored_pressure(STRENGTH_1_2D_1_6L, 5.0u"kN/m^2", 3.0u"kN/m^2")
# → 1.2 * 5.0 + 1.6 * 3.0 = 10.8 kN/m²
```
"""
function factored_pressure(combo::LoadCombination, dead::P, live::P) where P
    return combo.D * dead + combo.L * live
end

"""
    factored_pressure(combo::LoadCombination; D=0, L=0, Lr=0, S=0, R=0, W=0, E=0)

Apply load combination with all load types.

# Example
```julia
p_u = factored_pressure(STRENGTH_1_2D_1_0W; 
    D=5.0u"kN/m^2", L=3.0u"kN/m^2", W=1.5u"kN/m^2")
# → 1.2*5.0 + 1.0*3.0 + 1.0*1.5 = 10.5 kN/m²
```
"""
function factored_pressure(combo::LoadCombination; 
    D::T=0.0, L::T=0.0, Lr::T=0.0, S::T=0.0, R::T=0.0, W::T=0.0, E::T=0.0
) where T
    return (combo.D * D + combo.L * L + combo.Lr * Lr + 
            combo.S * S + combo.R * R + combo.W * W + combo.E * E)
end

"""
    factored_load(combo::LoadCombination, dead, live)

Alias for `factored_pressure` - works for any load type (force, moment, etc.).
"""
const factored_load = factored_pressure

# =============================================================================
# Combination Sets
# =============================================================================

"""
    ASCE7_STRENGTH_COMBINATIONS

All ASCE 7-22 strength load combinations for envelope analysis.
"""
const ASCE7_STRENGTH_COMBINATIONS = [
    STRENGTH_1_4D,
    STRENGTH_1_2D_1_6L,
    STRENGTH_1_2D_1_6Lr,
    STRENGTH_1_2D_1_0W,
    STRENGTH_1_2D_1_0E,
    STRENGTH_0_9D_1_0W,
    STRENGTH_0_9D_1_0E
]

"""
    GRAVITY_COMBINATIONS

Common gravity-only combinations (no lateral).
"""
const GRAVITY_COMBINATIONS = [
    STRENGTH_1_4D,
    STRENGTH_1_2D_1_6L,
    SERVICE
]
