# =============================================================================
# CIP Flat Plate Sizing Entry Point
# =============================================================================
#
# Orchestrates DDM, MDDM, and EFM analysis methods into a unified size_floor API.
#
# Reference: ACI 318-14/19 Chapter 8, StructurePoint Design Examples
#
# =============================================================================

"""
    size_floor(::FlatPlate, span, sdl, live; kwargs...)

Size a cast-in-place flat plate slab per ACI 318.

# Arguments
- `span`: Governing span length (typically longer clear span)
- `sdl`: Superimposed dead load (pressure)
- `live`: Live load (pressure)

# Keyword Arguments
- `material::Concrete`: Concrete material (default: NWC_4000)
- `options::FloorOptions`: Sizing options including `cip.analysis_method`
- `l2::Length`: Panel width perpendicular to span (default: same as span)
- `c1::Length`: Column dimension in span direction (default: estimated from span)
- `c2::Length`: Column dimension perpendicular to span (default: same as c1)
- `position::Symbol`: Panel position `:interior`, `:edge`, `:corner` (default: :interior)

# Analysis Methods (via `options.cip.analysis_method`)
- `:mddm` - Modified Direct Design Method (simplified coefficients, fastest)
- `:ddm` - Direct Design Method (full ACI tables)
- `:efm` - Equivalent Frame Method (most accurate)

# Returns
- `CIPSlabResult` with thickness, volume, and self-weight

# Example
```julia
using StructuralSizer, Unitful

span = 18u"ft"
sdl = 20u"psf"
live = 40u"psf"

result = size_floor(FlatPlate(), span, sdl, live)
# → CIPSlabResult(7 inches, ...)

# With options
opts = FloorOptions(cip=CIPOptions(analysis_method=:efm))
result = size_floor(FlatPlate(), span, sdl, live; options=opts)
```

# Reference
- ACI 318-14 Chapter 8 (Two-Way Slabs)
- ACI 318-14 Table 8.3.1.1 (Minimum Thickness)
"""
function size_floor(::FlatPlate, span::L, sdl::F, live::F;
                    material::Concrete = NWC_4000,
                    options::FloorOptions = FloorOptions(),
                    l2::Union{Nothing, Length} = nothing,
                    c1::Union{Nothing, Length} = nothing,
                    c2::Union{Nothing, Length} = nothing,
                    position::Symbol = :interior) where {L<:Length, F<:Pressure}
    
    opts = options.cip
    
    # Default panel width to span (square panel)
    l2_val = isnothing(l2) ? span : l2
    
    # Estimate column size if not provided
    c1_val = isnothing(c1) ? estimate_column_size_from_span(span; ratio=15.0) : c1
    c2_val = isnothing(c2) ? c1_val : c2
    
    # Clear span
    ln = clear_span(span, c1_val)
    
    # Determine if discontinuous edge
    discontinuous = position in (:edge, :corner)
    
    # =========================================================================
    # Phase 1: Minimum Thickness (ACI 8.3.1.1)
    # =========================================================================
    h_min = min_thickness_flat_plate(ln; discontinuous_edge=discontinuous)
    
    # Round up to nearest 0.5 inch (practical)
    h_in = ustrip(u"inch", h_min)
    h_in = ceil(h_in * 2) / 2  # Round up to nearest 0.5"
    h = h_in * u"inch"
    
    # =========================================================================
    # Phase 2: Compute Design Moments
    # =========================================================================
    
    # Self-weight
    γ_conc = material.ρ
    sw = γ_conc * h |> u"psf"
    
    # Factored load
    qu = 1.2 * (sw + sdl) + 1.6 * live
    
    # Static moment M0
    M0 = total_static_moment(qu, l2_val, ln)
    
    # Distribute moments based on analysis method
    l2_l1 = ustrip(u"ft", l2_val) / ustrip(u"ft", span)
    span_type = discontinuous ? :end_span : :interior_span
    
    moments = if opts.analysis_method == :mddm
        distribute_moments_mddm(M0, span_type)
    elseif opts.analysis_method == :ddm
        distribute_moments_aci(M0, span_type, l2_l1; edge_beam=opts.has_edge_beam)
    elseif opts.analysis_method == :efm
        # For EFM, we'd need the full frame analysis
        # For now, fall back to DDM for thickness sizing
        # (EFM is used when full panel design is needed)
        distribute_moments_aci(M0, span_type, l2_l1; edge_beam=opts.has_edge_beam)
    else
        error("Unknown analysis method: $(opts.analysis_method)")
    end
    
    # =========================================================================
    # Phase 3: Verify Thickness via Punching Shear
    # =========================================================================
    
    # Effective depth
    d = effective_depth(h)
    
    # Punching check at interior columns
    # (This is a simplified check - full design would check all columns)
    if position == :interior
        b0 = punching_perimeter(c1_val, c2_val, d)
        fc = material.fc
        Vc = punching_capacity_interior(b0, d, fc; c1=c1_val, c2=c2_val)
        
        # Tributary area for interior column (simplified as l1 × l2)
        At = span * l2_val
        Vu = punching_demand(qu, At, c1_val, c2_val, d)
        
        check = check_punching_shear(Vu, Vc)
        
        # If punching fails, increase thickness
        if !check.passes
            # Iterate thickness until punching passes
            for _ in 1:5
                h_in += 0.5
                h = h_in * u"inch"
                d = effective_depth(h)
                b0 = punching_perimeter(c1_val, c2_val, d)
                Vc = punching_capacity_interior(b0, d, fc; c1=c1_val, c2=c2_val)
                
                # Recalculate load with new self-weight
                sw = γ_conc * h |> u"psf"
                qu = 1.2 * (sw + sdl) + 1.6 * live
                Vu = punching_demand(qu, At, c1_val, c2_val, d)
                
                check = check_punching_shear(Vu, Vc)
                check.passes && break
            end
            
            if !check.passes
                @warn "Punching shear check fails at h=$(h). Consider drop panels or shear reinforcement."
            end
        end
    end
    
    # =========================================================================
    # Phase 4: Build Result
    # =========================================================================
    
    # Final self-weight
    sw_final = γ_conc * h |> u"psf"
    
    # Volume per area (thickness in length units = m³/m²)
    vol_per_area = uconvert(u"m", h)
    
    return CIPSlabResult(h, vol_per_area, sw_final)
end

"""
    size_floor(::FlatSlab, span, sdl, live; kwargs...)

Size a cast-in-place flat slab (with drop panels) per ACI 318.

Same interface as FlatPlate, but uses flat slab thickness rules (ACI Table 8.3.1.1).
Drop panels allow for thinner slabs and better punching shear capacity.
"""
function size_floor(::FlatSlab, span::L, sdl::F, live::F;
                    material::Concrete = NWC_4000,
                    options::FloorOptions = FloorOptions(),
                    l2::Union{Nothing, Length} = nothing,
                    c1::Union{Nothing, Length} = nothing,
                    c2::Union{Nothing, Length} = nothing,
                    position::Symbol = :interior) where {L<:Length, F<:Pressure}
    
    # Flat slab has slightly different thickness rules (drop panels help)
    # For now, use flat plate rules with a 10% reduction for drop panels
    opts = FloorOptions(
        cip = CIPOptions(
            support = options.cip.support,
            rebar_material = options.cip.rebar_material,
            has_edge_beam = options.cip.has_edge_beam,
            has_drop_panels = true,
            analysis_method = options.cip.analysis_method,
            grouping = options.cip.grouping,
            deflection_limit = options.cip.deflection_limit,
            check_long_term = options.cip.check_long_term
        ),
        vault = options.vault,
        composite = options.composite,
        timber = options.timber,
        tributary_axis = options.tributary_axis
    )
    
    result = size_floor(FlatPlate(), span, sdl, live;
                        material=material, options=opts, l2=l2, c1=c1, c2=c2, position=position)
    
    # ACI allows 10% reduction in thickness with drop panels meeting requirements
    # ACI 8.3.1.1: For slabs with drop panels, h_min = ln/36 (interior) or ln/33 (exterior)
    # vs ln/33 and ln/30 for flat plates
    h_reduced = result.thickness * 0.9
    h_in = ustrip(u"inch", h_reduced)
    h_in = max(ceil(h_in * 2) / 2, 5.0)  # Round up, minimum 5"
    h = h_in * u"inch"
    
    # Recalculate self-weight
    sw = material.ρ * h |> u"psf"
    vol_per_area = uconvert(u"m", h)
    
    return CIPSlabResult(h, vol_per_area, sw)
end

"""
    size_floor(::TwoWay, span, sdl, live; kwargs...)

Size a cast-in-place two-way slab with beams per ACI 318.

Two-way slabs have beams on all sides, which provide additional support
and allow for thinner slabs than flat plates.
"""
function size_floor(::TwoWay, span::L, sdl::F, live::F;
                    material::Concrete = NWC_4000,
                    options::FloorOptions = FloorOptions(),
                    l2::Union{Nothing, Length} = nothing,
                    position::Symbol = :interior) where {L<:Length, F<:Pressure}
    
    l2_val = isnothing(l2) ? span : l2
    
    # Two-way with beams: ACI Table 8.3.1.2
    # h_min depends on αfm (beam stiffness ratio)
    # For typical cases with substantial beams: h = ln/36 or greater
    
    # Simplified: use shorter span for two-way
    ln = min(span, l2_val)
    ln_in = ustrip(u"inch", ln)
    
    # ACI 8.3.1.2 for two-way slabs with beams between supports on all sides
    # When αfm ≥ 2.0: h_min = ln(0.8 + fy/200000) / 36
    # Simplified for fy = 60 ksi: h_min ≈ ln/33
    fy = options.cip.rebar_material.Fy
    fy_psi = ustrip(u"psi", fy)
    
    h_min_in = ln_in * (0.8 + fy_psi / 200000) / 36
    h_min_in = max(h_min_in, 3.5)  # Absolute minimum for two-way with beams
    
    # Round up to nearest 0.5"
    h_in = ceil(h_min_in * 2) / 2
    h = h_in * u"inch"
    
    # Self-weight and result
    sw = material.ρ * h |> u"psf"
    vol_per_area = uconvert(u"m", h)
    
    return CIPSlabResult(h, vol_per_area, sw)
end

"""
    size_floor(::OneWay, span, sdl, live; kwargs...)

Size a cast-in-place one-way slab per ACI 318.

One-way slabs span primarily in one direction (aspect ratio > 2).
"""
function size_floor(::OneWay, span::L, sdl::F, live::F;
                    material::Concrete = NWC_4000,
                    options::FloorOptions = FloorOptions()) where {L<:Length, F<:Pressure}
    
    opts = options.cip
    
    # ACI Table 7.3.1.1 - Minimum thickness for one-way slabs
    # Simply supported: h = l/20
    # One end continuous: h = l/24  
    # Both ends continuous: h = l/28
    # Cantilever: h = l/10
    
    ln_in = ustrip(u"inch", span)
    fy = opts.rebar_material.Fy
    fy_psi = ustrip(u"psi", fy)
    
    # Adjustment factor for fy ≠ 60 ksi
    fy_factor = 0.4 + fy_psi / 100000
    
    h_min_in = if opts.support == SIMPLE
        ln_in / 20 * fy_factor
    elseif opts.support == ONE_END_CONT
        ln_in / 24 * fy_factor
    elseif opts.support == BOTH_ENDS_CONT
        ln_in / 28 * fy_factor
    elseif opts.support == CANTILEVER
        ln_in / 10 * fy_factor
    else
        ln_in / 24 * fy_factor  # Default to one end continuous
    end
    
    # Minimum thickness = 4" for one-way
    h_min_in = max(h_min_in, 4.0)
    
    # Round up to nearest 0.5"
    h_in = ceil(h_min_in * 2) / 2
    h = h_in * u"inch"
    
    # Self-weight and result
    sw = material.ρ * h |> u"psf"
    vol_per_area = uconvert(u"m", h)
    
    return CIPSlabResult(h, vol_per_area, sw)
end

"""
    size_floor(::Waffle, span, sdl, live; kwargs...)

Size a cast-in-place waffle slab per ACI 318.

Waffle slabs (two-way joist system) allow for longer spans
with reduced weight compared to solid slabs.
"""
function size_floor(::Waffle, span::L, sdl::F, live::F;
                    material::Concrete = NWC_4000,
                    options::FloorOptions = FloorOptions(),
                    l2::Union{Nothing, Length} = nothing,
                    position::Symbol = :interior) where {L<:Length, F<:Pressure}
    
    # Waffle slabs: ACI 9.8 (two-way joist construction)
    # Total depth typically governed by span/20 to span/24
    # Ribs are typically 6" wide at 3' or 4' on center
    
    l2_val = isnothing(l2) ? span : l2
    ln = max(span, l2_val)  # Longer span governs
    ln_in = ustrip(u"inch", ln)
    
    # Waffle depth: span/20 to span/24 (use span/22 as default)
    h_min_in = ln_in / 22
    h_min_in = max(h_min_in, 8.0)  # Minimum practical waffle depth
    
    # Round up to practical waffle form depths (8", 10", 12", 14", 16", 20")
    standard_depths = [8.0, 10.0, 12.0, 14.0, 16.0, 20.0, 24.0]
    h_in = first(d for d in standard_depths if d >= h_min_in)
    h = h_in * u"inch"
    
    # Self-weight for waffle (approximately 60% of solid slab)
    # Typical void ratio is ~40%
    void_ratio = 0.40
    sw_solid = material.ρ * h |> u"psf"
    sw = sw_solid * (1 - void_ratio)
    
    # Volume per area accounts for voids
    vol_per_area = uconvert(u"m", h) * (1 - void_ratio)
    
    return CIPSlabResult(h, vol_per_area, sw)
end

"""
    size_floor(::PTBanded, span, sdl, live; kwargs...)

Size a post-tensioned banded slab per ACI 318 and PTI.

PT banded slabs allow for longer spans and shallower depths
through post-tensioning.
"""
function size_floor(::PTBanded, span::L, sdl::F, live::F;
                    material::Concrete = NWC_4000,
                    options::FloorOptions = FloorOptions(),
                    l2::Union{Nothing, Length} = nothing,
                    position::Symbol = :interior) where {L<:Length, F<:Pressure}
    
    # PT slabs can be thinner than RC: span/45 to span/50
    # With drop panels: even thinner
    
    l2_val = isnothing(l2) ? span : l2
    ln = max(span, l2_val)  # Longer span governs
    ln_in = ustrip(u"inch", ln)
    
    has_drops = options.cip.has_drop_panels
    
    # PT thickness rules (PTI guidelines)
    divisor = has_drops ? 50.0 : 45.0
    h_min_in = ln_in / divisor
    h_min_in = max(h_min_in, 5.0)  # PT minimum is typically 5"
    
    # Round up to nearest 0.5"
    h_in = ceil(h_min_in * 2) / 2
    h = h_in * u"inch"
    
    # Self-weight
    sw = material.ρ * h |> u"psf"
    vol_per_area = uconvert(u"m", h)
    
    return CIPSlabResult(h, vol_per_area, sw)
end

# =============================================================================
# Exports
# =============================================================================

export size_floor
