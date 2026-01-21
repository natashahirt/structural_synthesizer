"""
    StructuralUnits

Shared unit definitions for structural engineering packages.
Defines US customary units commonly used in structural analysis.

# Units Defined (in addition to Unitful built-ins like lbf, psi, lb, inch, ft)
- `kip` - kilopound-force (1000 lbf)
- `ksi` - kips per square inch (6.895 MPa)
- `psf` - pounds per square foot (47.88 Pa)

# Usage
Import units directly for precompile-safe use:
```julia
using StructuralBase: StructuralUnits
using StructuralUnits: kip, ksi, psf
using Unitful: lbf, psi  # These are Unitful built-ins
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

# Export the new units
export kip, ksi, psf

# =============================================================================
# Physical Constants
# =============================================================================

"""Standard gravity acceleration."""
const GRAVITY = 9.80665u"m/s^2"
export GRAVITY

end # module
