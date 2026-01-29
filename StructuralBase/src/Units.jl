"""
    StructuralUnits

Shared unit definitions for structural engineering packages.
Defines US customary units commonly used in structural analysis.

# Units Defined (in addition to Unitful built-ins like lbf, psi, lb, inch, ft)
- `kip` - kilopound-force (1000 lbf)
- `ksi` - kips per square inch (6.895 MPa)
- `psf` - pounds per square foot (47.88 Pa)
- `ksf` - kips per square foot

# Type Aliases for Structural Quantities
- `Length`, `Area`, `Volume`, `Inertia` - geometric quantities
- `Pressure`, `Force`, `Moment`, `LinearLoad` - structural quantities

# Usage
Import units directly for precompile-safe use:
```julia
using StructuralBase: StructuralUnits
using StructuralUnits: kip, ksi, psf, Length, Moment
force = 10.0kip
stress = 50.0ksi
```

To use `u"..."` syntax, register at runtime:
```julia
using StructuralBase: StructuralUnits
Unitful.register(StructuralUnits)
force = 10.0u"kip"
```
"""
module StructuralUnits

using Unitful

# =============================================================================
# Custom Unit Definitions for Structural Engineering
# (lbf, psi, lb, inch, ft are already in Unitful)
# =============================================================================

# Kilopound-force: 1 kip = 1000 lbf = 4448.2216 N
Unitful.@unit kip "kip" Kip 4448.2216152605u"N" false

# Kips per square inch: 1 ksi = 1000 psi = 6.894757 MPa
Unitful.@unit ksi "ksi" KipPerSquareInch 6.894757e6u"Pa" false

# Pounds per square foot: 1 psf = 1 lbf/ft² = 47.88 Pa
Unitful.@unit psf "psf" PoundPerSquareFoot 47.88025898u"Pa" false

# Kips per square foot: 1 ksf = 1000 psf
Unitful.@unit ksf "ksf" KipPerSquareFoot 47880.25898u"Pa" false

# Pounds per cubic foot: 1 pcf = 1 lb/ft³
Unitful.@unit pcf "pcf" PoundPerCubicFoot 16.01846337u"kg/m^3" false

# Export the new units
export kip, ksi, psf, ksf, pcf

# =============================================================================
# Type Aliases for Structural Quantities
# =============================================================================
# These enable cleaner type annotations: `f(x::Length)` instead of `f(x::Unitful.Length)`

"""Length quantity (m, ft, inch, etc.)"""
const Length = Unitful.Quantity{T, Unitful.𝐋, U} where {T<:Real, U}

"""Area quantity (m², ft², inch², etc.)"""
const Area = Unitful.Quantity{T, Unitful.𝐋^2, U} where {T<:Real, U}

"""Volume or section modulus quantity (m³, ft³, inch³, etc.)"""
const Volume = Unitful.Quantity{T, Unitful.𝐋^3, U} where {T<:Real, U}

"""Moment of inertia quantity (m⁴, ft⁴, inch⁴, etc.)"""
const Inertia = Unitful.Quantity{T, Unitful.𝐋^4, U} where {T<:Real, U}

"""Warping constant quantity (inch⁶, etc.)"""
const WarpingConstant = Unitful.Quantity{T, Unitful.𝐋^6, U} where {T<:Real, U}

"""Pressure/stress quantity (Pa, psi, ksi, etc.)"""
const Pressure = Unitful.Quantity{T, Unitful.𝐌*Unitful.𝐋^-1*Unitful.𝐓^-2, U} where {T<:Real, U}

"""Force quantity (N, lbf, kip, etc.)"""
const Force = Unitful.Quantity{T, Unitful.𝐌*Unitful.𝐋*Unitful.𝐓^-2, U} where {T<:Real, U}

"""Moment/torque quantity (N·m, kip·ft, lb·in, etc.) - same dimension as Energy"""
const Moment = Unitful.Quantity{T, Unitful.𝐌*Unitful.𝐋^2*Unitful.𝐓^-2, U} where {T<:Real, U}

"""Linear load quantity (N/m, kip/ft, plf, etc.) - Force per unit length"""
const LinearLoad = Unitful.Quantity{T, Unitful.𝐌*Unitful.𝐓^-2, U} where {T<:Real, U}

"""Area load quantity (Pa, psf, ksf, etc.) - Force per unit area (same as Pressure)"""
const AreaLoad = Pressure

"""Density quantity (kg/m³, pcf, etc.)"""
const Density = Unitful.Quantity{T, Unitful.𝐌*Unitful.𝐋^-3, U} where {T<:Real, U}

export Length, Area, Volume, Inertia, WarpingConstant
export Pressure, Force, Moment, LinearLoad, AreaLoad, Density

# =============================================================================
# Physical Constants
# =============================================================================

"""Standard gravity acceleration."""
const GRAVITY = 9.80665u"m/s^2"
export GRAVITY

# =============================================================================
# CSV/Catalog Parsing Utilities
# =============================================================================
# Shared utilities for parsing numeric values from CSV catalogs

"""Convert a value to Float64 (for catalog parsing)."""
asfloat(x::Real) = Float64(x)
asfloat(x::AbstractString) = parse(Float64, x)
asfloat(x) = throw(ArgumentError("Cannot parse numeric value from $(typeof(x)) = $(repr(x))"))

"""Convert a value to Float64 or nothing if missing/invalid (for optional catalog fields)."""
function maybe_asfloat(x)
    ismissing(x) && return nothing
    if x isa AbstractString
        sx = strip(x)
        (sx == "–" || sx == "-" || sx == "—" || isempty(sx)) && return nothing
    end
    return asfloat(x)
end

# Note: underscore naming to match Julia convention for internal helpers
export asfloat, maybe_asfloat

end # module
