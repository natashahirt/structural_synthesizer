# ==============================================================================
# RC Column Section Catalog
# ==============================================================================
# Standard RC column sections for discrete optimization.
# Follows the same interface as steel section catalogs.
#
# Uses existing Concrete type from materials/types.jl
# Presets: NWC_3000, NWC_4000, NWC_5000, NWC_6000, NWC_GGBS, NWC_PFA 
#          in materials/concrete.jl

using Unitful
using Asap: ksi

# ==============================================================================
# Standard Column Sizes
# ==============================================================================

"""
    standard_rc_columns(; 
        sizes = 12:2:36,      # inches
        bar_sizes = [5, 6, 7, 8, 9, 10, 11],
        n_bars_range = 4:4:20,
        cover_in = 1.5
    ) -> Vector{RCColumnSection}

Generate a catalog of standard RC column sections.

# Arguments
- `sizes`: Range of square column sizes (inches)
- `bar_sizes`: Available rebar sizes
- `n_bars_range`: Range of bar counts (must be ≥4 for corners)
- `cover_in`: Clear cover (inches)

# Returns
Vector of RCColumnSection with varying sizes and reinforcement

# Example
```julia
catalog = standard_rc_columns()           # Default: 12"-36" with various rebar
catalog = standard_rc_columns(sizes=14:2:24, bar_sizes=[8,9,10])
```
"""
function standard_rc_columns(;
    sizes = 12:2:36,
    bar_sizes = [6, 7, 8, 9, 10, 11],
    n_bars_range = 4:4:16,
    cover_in = 1.5
)
    catalog = RCColumnSection[]
    
    for size in sizes
        b = Float64(size) * u"inch"
        h = b  # Square columns
        
        for bar_size in bar_sizes
            # Check minimum size for this bar
            bar = StructuralSizer.rebar(bar_size)
            db = ustrip(u"inch", bar.diameter)
            
            # Minimum column size should fit bars with adequate spacing
            min_cover_to_center = cover_in + db/2
            if 2 * min_cover_to_center > size * 0.4
                continue  # Skip if bars would be too close
            end
            
            for n_bars in n_bars_range
                # Ensure reasonable reinforcement ratio (1-8% per ACI)
                As_total = n_bars * ustrip(u"inch^2", bar.A)
                Ag = size^2
                ρ = As_total / Ag
                
                if ρ < 0.01 || ρ > 0.08
                    continue  # Skip invalid ratios
                end
                
                # Cover to bar center
                cover = (cover_in + db/2) * u"inch"
                
                try
                    section = RCColumnSection(
                        b = b,
                        h = h,
                        cover = cover,
                        bar_size = bar_size,
                        n_bars = n_bars,
                        tie_type = :tied,
                        arrangement = :perimeter
                    )
                    push!(catalog, section)
                catch e
                    # Skip invalid combinations (e.g., bar spacing too tight)
                    continue
                end
            end
        end
    end
    
    # Sort by size then by steel area (smaller first for minimum weight)
    sort!(catalog, by = s -> (ustrip(u"inch", s.b), _total_As(s)))
    
    return catalog
end

"""Calculate total steel area in section."""
function _total_As(section::RCColumnSection)
    sum(ustrip(u"inch^2", bar.As) for bar in section.bars)
end

# ==============================================================================
# Concrete Material Helpers (for unit conversion)
# ==============================================================================
# Use existing Concrete type from materials/types.jl
# All presets are defined in materials/concrete.jl

"""
    concrete_fc_ksi(mat::Concrete) -> Float64

Extract concrete compressive strength in ksi from Concrete material.
Handles unit conversion from any pressure unit.
"""
function concrete_fc_ksi(mat::Concrete)
    ustrip(ksi, mat.fc′)
end

"""
    concrete_fc_mpa(mat::Concrete) -> Float64

Extract concrete compressive strength in MPa from Concrete material.
"""
function concrete_fc_mpa(mat::Concrete)
    ustrip(u"MPa", mat.fc′)
end

"""
    concrete_E_ksi(mat::Concrete) -> Float64

Extract concrete elastic modulus in ksi from Concrete material.
"""
function concrete_E_ksi(mat::Concrete)
    ustrip(ksi, mat.E)
end

"""
    concrete_wc_pcf(mat::Concrete) -> Float64

Extract concrete unit weight in pcf (lb/ft³) from Concrete material.
Handles conversion from kg/m³ density.
"""
function concrete_wc_pcf(mat::Concrete)
    # ρ is density in kg/m³, convert to weight in lbf/ft³
    ustrip(u"lbf/ft^3", mat.ρ * 1u"gn")
end

# ==============================================================================
# Prebuilt Catalogs
# ==============================================================================
# Note: RCColumnDemand is defined in members/optimize/demands.jl

"""Return a small catalog of common column sizes (12"-24")."""
function common_rc_rect_columns()
    standard_rc_columns(
        sizes = 12:4:24,
        bar_sizes = [6, 8, 9, 11],
        n_bars_range = 4:4:12
    )
end

"""Return a large catalog for optimization (10"-48")."""
function all_rc_rect_columns()
    standard_rc_columns(
        sizes = 10:2:48,
        bar_sizes = [5, 6, 7, 8, 9, 10, 11, 14, 18],
        n_bars_range = 4:2:24
    )
end

# ==============================================================================
# Circular Column Catalog
# ==============================================================================

"""
    standard_rc_circular_columns(; 
        diameters = 12:2:36,       # inches
        bar_sizes = [6, 7, 8, 9, 10, 11],
        n_bars_range = 6:2:16,
        cover_in = 1.5
    ) -> Vector{RCCircularSection}

Generate a catalog of standard circular RC column sections.

# Arguments
- `diameters`: Range of column diameters (inches)
- `bar_sizes`: Available rebar sizes
- `n_bars_range`: Range of bar counts (minimum 6 for spiral columns)
- `cover_in`: Clear cover (inches)

# Returns
Vector of RCCircularSection with varying sizes and reinforcement

# Example
```julia
catalog = standard_rc_circular_columns()
catalog = standard_rc_circular_columns(diameters=16:4:32, bar_sizes=[8,9,10])
```
"""
function standard_rc_circular_columns(;
    diameters = 12:2:36,
    bar_sizes = [6, 7, 8, 9, 10, 11],
    n_bars_range = 6:2:16,
    cover_in = 1.5
)
    catalog = RCCircularSection[]
    
    for D_val in diameters
        D = Float64(D_val) * u"inch"
        
        for bar_size in bar_sizes
            # Check minimum size for this bar
            bar = StructuralSizer.rebar(bar_size)
            db = ustrip(u"inch", bar.diameter)
            
            # Minimum diameter should fit bars with adequate spacing
            # For circular, need clearance around perimeter
            min_cover_to_center = cover_in + 0.5 + db/2  # 0.5" for spiral
            R_bars = D_val/2 - min_cover_to_center
            
            if R_bars < db
                continue  # Skip if bars would be too close to center
            end
            
            for n_bars in n_bars_range
                # Check bar spacing around circumference
                circumference = 2 * π * R_bars
                spacing = circumference / n_bars
                min_spacing = max(1.5 * db, 1.5)  # ACI minimum
                
                if spacing < min_spacing
                    continue  # Skip if bars too close together
                end
                
                # Ensure reasonable reinforcement ratio (1-8% per ACI)
                As_total = n_bars * ustrip(u"inch^2", bar.A)
                Ag = π * (D_val/2)^2
                ρ = As_total / Ag
                
                if ρ < 0.01 || ρ > 0.08
                    continue  # Skip invalid ratios
                end
                
                try
                    section = RCCircularSection(
                        D = D,
                        bar_size = bar_size,
                        n_bars = n_bars,
                        cover = cover_in * u"inch",
                        tie_type = :spiral  # Circular columns typically use spiral
                    )
                    push!(catalog, section)
                catch e
                    # Skip invalid combinations
                    continue
                end
            end
        end
    end
    
    # Sort by diameter then by steel area (smaller first)
    sort!(catalog, by = s -> (ustrip(u"inch", s.D), _total_As_circular(s)))
    
    return catalog
end

"""Calculate total steel area in circular section."""
function _total_As_circular(section::RCCircularSection)
    sum(ustrip(u"inch^2", bar.As) for bar in section.bars)
end

"""Return a small catalog of common circular column sizes (12"-24")."""
function common_rc_circular_columns()
    standard_rc_circular_columns(
        diameters = 12:4:24,
        bar_sizes = [6, 8, 9, 10],
        n_bars_range = 6:2:12
    )
end

"""Return a large catalog of circular columns for optimization (12"-48")."""
function all_rc_circular_columns()
    standard_rc_circular_columns(
        diameters = 12:2:48,
        bar_sizes = [5, 6, 7, 8, 9, 10, 11, 14],
        n_bars_range = 6:2:20
    )
end