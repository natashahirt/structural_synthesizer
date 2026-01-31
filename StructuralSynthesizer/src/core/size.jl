# ==============================================================================
# Iterative Structure Sizing
# ==============================================================================
# Top-level sizing function that handles load coupling between members.

"""
    size!(design::BuildingDesign; kwargs...)

Size all structural members iteratively until loads converge.

The sizing sequence handles load coupling:
1. Size beams (with estimated column loads)
2. Re-analyze (beam self-weight updates column demands)
3. Size columns  
4. Check convergence (did column demands change significantly?)
5. Repeat steps 1-4 until stable
6. Size foundations (with final column reactions)

Uses `design.params` for all sizing options:
- `params.beams`: SteelBeamOptions (or nothing for default)
- `params.columns`: SteelColumnOptions or ConcreteColumnOptions (or nothing for default)

# Keyword Arguments
- `max_iterations::Int = 3`: Maximum beam/column sizing iterations
- `convergence_tol::Float64 = 0.05`: Stop when max demand change < 5%
- `size_foundations::Bool = true`: Size foundations after members converge
- `verbose::Bool = true`: Log iteration progress

# Example
```julia
design = BuildingDesign(struc, DesignParameters(
    columns = ConcreteColumnOptions(grade = NWC_5000),
    beams = SteelBeamOptions(deflection_limit = 1/360),
))

size!(design)  # Iteratively sizes everything
```
"""
function size!(
    design::BuildingDesign;
    max_iterations::Int = 3,
    convergence_tol::Float64 = 0.05,
    size_foundations::Bool = true,
    verbose::Bool = true,
)
    struc = design.structure
    params = design.params
    
    # Resolve options from params (or use defaults)
    beam_opts = something(params.beams, StructuralSizer.SteelBeamOptions())
    column_opts = something(params.columns, StructuralSizer.SteelColumnOptions())
    
    prev_column_demands = nothing
    converged = false
    
    # =========================================================================
    # Iterative beam/column sizing
    # =========================================================================
    for iter in 1:max_iterations
        verbose && @info "Sizing iteration $iter/$max_iterations"
        
        # --- Size beams ---
        # TODO: Implement size_beams!(struc, beam_opts)
        # size_beams!(struc, beam_opts)
        
        # --- Re-analyze with updated beam self-weight ---
        Asap.process!(struc.asap_model)
        Asap.solve!(struc.asap_model)
        
        # --- Size columns with updated demands ---
        size_columns!(struc, column_opts)
        
        # --- Check convergence ---
        current_demands = _extract_column_demands(struc)
        
        if !isnothing(prev_column_demands)
            change = _max_demand_change(prev_column_demands, current_demands)
            verbose && @info "  Max demand change: $(round(change * 100, digits=1))%"
            
            if change < convergence_tol
                verbose && @info "  Converged!"
                converged = true
                break
            end
        end
        
        prev_column_demands = current_demands
        
        # Re-analyze for next iteration
        Asap.process!(struc.asap_model)
        Asap.solve!(struc.asap_model)
    end
    
    !converged && verbose && @warn "Did not converge within $max_iterations iterations"
    
    # =========================================================================
    # Final foundation sizing (after member convergence)
    # =========================================================================
    if size_foundations
        verbose && @info "Sizing foundations..."
        # TODO: Implement foundation sizing
        # size_foundations!(struc)
    end
    
    # =========================================================================
    # Update design results
    # =========================================================================
    _update_design_results!(design)
    
    return design
end

# ==============================================================================
# Internal Helpers
# ==============================================================================

"""Extract column axial demands for convergence checking."""
function _extract_column_demands(struc::BuildingStructure)
    demands = Float64[]
    
    # Get demands from ASAP model or member groups
    for col in struc.columns
        # TODO: Extract actual Pu from ASAP analysis results
        # For now, placeholder
        push!(demands, 0.0)
    end
    
    return demands
end

"""Compute maximum relative change in column demands."""
function _max_demand_change(prev::Vector{Float64}, curr::Vector{Float64})
    length(prev) == length(curr) || return 1.0
    
    max_change = 0.0
    for (p, c) in zip(prev, curr)
        if p > 0
            change = abs(c - p) / p
            max_change = max(max_change, change)
        elseif c > 0
            max_change = 1.0  # Went from zero to non-zero
        end
    end
    
    return max_change
end

"""Update BuildingDesign results after sizing."""
function _update_design_results!(design::BuildingDesign)
    struc = design.structure
    
    # Update column results
    for (col_idx, col) in enumerate(struc.columns)
        if !isnothing(col.base.section)
            result = get(design.columns, col_idx, ColumnDesignResult())
            result.section_size = string(col.base.section)
            design.columns[col_idx] = result
        end
    end
    
    # Update beam results
    for (beam_idx, beam) in enumerate(struc.beams)
        if !isnothing(beam.base.section)
            result = get(design.beams, beam_idx, BeamDesignResult())
            result.section_size = string(beam.base.section)
            design.beams[beam_idx] = result
        end
    end
    
    # Recompute summary
    _compute_design_summary!(design, struc, design.params)
end
