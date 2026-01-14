# Dowel-Laminated Timber (DLT) Panel Sizing
# Hardwood dowels connect softwood laminations (no adhesive)

# TODO: Load DLT manufacturer data (StructureCraft, etc.)
# Typically one-way spanning, similar depths to CLT

"""
Select DLT panel for given span and load.

# Arguments
- `span`: Clear span
- `load`: Superimposed load
- `material`: Timber material (placeholder for future timber material types)
- `fire_rating`: Required fire rating in hours (default 1)

# Returns
- `TimberPanelResult` with panel specification
"""
function size_floor(::DLT, span::Real, load::Real;
                    material::AbstractMaterial=NWC_4000,  # placeholder until Timber type exists
                    fire_rating::Int=1)
    error("DLT sizing not yet implemented")
end
