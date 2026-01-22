# Foundation initialization and sizing utilities

"""
    initialize_supports!(struc::BuildingStructure)

Create Support objects for each support vertex in the skeleton.
Must be called after `to_asap!(struc)` and `solve!(struc.asap_model)`.

Extracts reaction forces from the ASAP model nodes.
"""
function initialize_supports!(struc::BuildingStructure{T}) where T
    skel = struc.skeleton
    model = struc.asap_model
    
    isempty(model.nodes) && throw(ArgumentError("ASAP model has no nodes. Call to_asap!() first."))
    model.processed || throw(ArgumentError("ASAP model not solved. Call solve!(struc.asap_model) first."))
    
    support_vertex_indices = get(skel.groups_vertices, :support, Int[])
    isempty(support_vertex_indices) && (@warn "No support vertices found in skeleton"; return struc)
    
    empty!(struc.supports)
    
    for v_idx in support_vertex_indices
        node = model.nodes[v_idx]  # Vertex index maps to node index (from to_asap!)
        
        # Extract reactions with units (forces and moments separately)
        # Convert to kN/kN*m to match BuildingStructure's unit convention
        rxn = node.reaction
        forces = (
            uconvert(u"kN", rxn[1]),
            uconvert(u"kN", rxn[2]),
            uconvert(u"kN", rxn[3])
        )
        moments = (
            uconvert(u"kN*m", rxn[4]),
            uconvert(u"kN*m", rxn[5]),
            uconvert(u"kN*m", rxn[6])
        )
        
        support = Support(v_idx, v_idx; forces=forces, moments=moments, foundation_type=:spread)
        push!(struc.supports, support)
    end
    
    @debug "Initialized $(length(struc.supports)) supports from skeleton"
    return struc
end

"""
    support_demands(struc::BuildingStructure; load_factor=1.0)

Convert support reactions to FoundationDemand objects.

# Arguments
- `load_factor`: Factor to apply (use 1.0 if reactions are already factored)

# Returns
Vector of FoundationDemand, one per support.
"""
function support_demands(struc::BuildingStructure; load_factor::Real=1.0)
    isempty(struc.supports) && throw(ArgumentError("No supports. Call initialize_supports!() first."))
    
    demands = StructuralSizer.FoundationDemand[]
    
    for (i, supp) in enumerate(struc.supports)
        # Extract forces and moments
        Fx = supp.forces[1] * load_factor
        Fy = supp.forces[2] * load_factor
        Fz = supp.forces[3] * load_factor
        Mx = supp.moments[1] * load_factor
        My = supp.moments[2] * load_factor
        Mz = supp.moments[3] * load_factor
        
        # Convention: ASAP reaction is force FROM support TO structure
        # For gravity loads: structure pushes down, support pushes up → Fz is positive
        # For footing: Pu (compression) = magnitude of vertical reaction
        Pu = abs(Fz)  # Compression is always positive for footing design
        
        # Horizontal shears
        Vux = Fx
        Vuy = Fy
        
        # Moments about horizontal axes
        Mux = Mx
        Muy = My
        
        # Service load (unfactored) - approximate as factored/1.4
        Ps = Pu / 1.4
        
        demand = StructuralSizer.FoundationDemand(i; 
            Pu=Pu, Mux=Mux, Muy=Muy, Vux=Vux, Vuy=Vuy, Ps=Ps)
        push!(demands, demand)
    end
    
    return demands
end

"""
    initialize_foundations!(struc::BuildingStructure; groupings=nothing)

Create Foundation objects for supports.

# Arguments
- `groupings`: Optional vector of support index vectors for combined foundations.
  If `nothing`, creates 1:1 mapping (one spread footing per support).

# Example
```julia
# One footing per column (default)
initialize_foundations!(struc)

# Combined footing for supports 1 & 2
initialize_foundations!(struc; groupings=[[1, 2], [3], [4]])
```
"""
function initialize_foundations!(struc::BuildingStructure{T}; 
                                  groupings::Union{Nothing, Vector{Vector{Int}}}=nothing) where T
    isempty(struc.supports) && throw(ArgumentError("No supports. Call initialize_supports!() first."))
    
    empty!(struc.foundations)
    
    if isnothing(groupings)
        # Default: one foundation per support
        for (i, _) in enumerate(struc.supports)
            # Placeholder result - will be filled by size_foundations!
            placeholder = _placeholder_foundation_result(T)
            fnd = Foundation([i], placeholder; foundation_type=:spread)
            push!(struc.foundations, fnd)
        end
    else
        # Explicit groupings
        for supp_indices in groupings
            ftype = length(supp_indices) > 1 ? :combined : :spread
            placeholder = _placeholder_foundation_result(T)
            fnd = Foundation(supp_indices, placeholder; foundation_type=ftype)
            push!(struc.foundations, fnd)
        end
    end
    
    @debug "Initialized $(length(struc.foundations)) foundations"
    return struc
end

# Placeholder result for undesigned foundations
function _placeholder_foundation_result(::Type{T}) where T
    L = typeof(1.0u"m")
    V = typeof(1.0u"m^3")
    F = typeof(1.0u"kN")
    StructuralSizer.SpreadFootingResult{L, V, F}(
        0.0u"m", 0.0u"m", 0.0u"m", 0.0u"m",
        0.0u"mm^2/m", 0, 0.0u"m",
        0.0u"m^3", 0.0u"m^3", 0.0
    )
end

"""
    size_foundations!(struc::BuildingStructure; soil, concrete, rebar, demands=nothing, kwargs...)

Size all foundations based on support reactions.

# Arguments
- `soil::Soil`: Geotechnical parameters
- `concrete::Concrete`: Concrete material for footings
- `rebar::Metal`: Reinforcement material
- `demands`: Optional precomputed `support_demands(struc)` to avoid recomputation

# Keyword Arguments
Passed to `design_spread_footing`:
- `pier_width`: Column width (default 0.3m)
- `rebar_dia`: Rebar diameter (default 16mm)
- `cover`: Concrete cover (default 75mm)
- `min_depth`: Minimum footing depth (default 0.3m)
"""
function size_foundations!(
    struc::BuildingStructure;
    soil::StructuralSizer.Soil,
    concrete::StructuralSizer.Concrete=StructuralSizer.NWC_4000,
    rebar::StructuralSizer.Metal=StructuralSizer.Rebar_60,
    pier_width=0.3u"m",
    demands::Union{Nothing, Vector{StructuralSizer.FoundationDemand}}=nothing,
    kwargs...
)
    isempty(struc.foundations) && throw(ArgumentError("No foundations. Call initialize_foundations!() first."))
    
    # Use provided demands or compute (avoids recomputation if caller provides)
    demands = isnothing(demands) ? support_demands(struc) : demands
    
    for (f_idx, fnd) in enumerate(struc.foundations)
        if fnd.foundation_type == :spread && length(fnd.support_indices) == 1
            # Single spread footing
            supp_idx = fnd.support_indices[1]
            demand = demands[supp_idx]
            
            result = StructuralSizer.design_spread_footing(
                demand, soil, concrete, rebar;
                pier_width=pier_width, kwargs...
            )
            
            # Update foundation with result and volumes
            volumes = _compute_foundation_volumes(result, concrete, rebar)
            struc.foundations[f_idx] = Foundation(
                fnd.support_indices, result;
                foundation_type=:spread, group_id=fnd.group_id, volumes=volumes
            )
            
        elseif fnd.foundation_type == :combined || length(fnd.support_indices) > 1
            # Combined footing - sum demands and design as larger spread for now
            # TODO: Implement proper combined footing design
            total_Pu = sum(demands[i].Pu for i in fnd.support_indices)
            
            # Create combined demand
            combined_demand = StructuralSizer.FoundationDemand(f_idx; 
                Pu=total_Pu, Ps=total_Pu/1.4)
            
            result = StructuralSizer.design_spread_footing(
                combined_demand, soil, concrete, rebar;
                pier_width=pier_width, kwargs...
            )
            
            volumes = _compute_foundation_volumes(result, concrete, rebar)
            struc.foundations[f_idx] = Foundation(
                fnd.support_indices, result;
                foundation_type=:combined, group_id=fnd.group_id, volumes=volumes
            )
            
            @warn "Combined footing designed as equivalent spread footing (simplified)"
        else
            @warn "Foundation type $(fnd.foundation_type) not implemented, skipping"
        end
    end
    
    # Summary
    total_concrete = sum(StructuralSizer.concrete_volume(f.result) for f in struc.foundations)
    total_steel = sum(StructuralSizer.steel_volume(f.result) for f in struc.foundations)
    
    @info "Sized $(length(struc.foundations)) foundations" total_concrete total_steel
    
    return struc
end

"""Compute material volumes for a foundation from its result."""
function _compute_foundation_volumes(result::R, concrete, rebar) where R<:AbstractFoundationResult
    MaterialVolumes(
        concrete => StructuralSizer.concrete_volume(result),
        rebar => StructuralSizer.steel_volume(result)
    )
end

"""
    foundation_summary(struc::BuildingStructure)

Print a summary of all foundations in the structure.
"""
function foundation_summary(struc::BuildingStructure)
    isempty(struc.foundations) && return println("No foundations designed.")
    
    println("\n=== Foundation Summary ===")
    println("─" ^ 60)
    
    total_concrete = 0.0u"m^3"
    total_steel = 0.0u"m^3"
    total_area = 0.0u"m^2"
    
    for (i, fnd) in enumerate(struc.foundations)
        r = fnd.result
        supp_str = join(fnd.support_indices, ", ")
        
        println("Foundation $i ($(fnd.foundation_type), supports: [$supp_str])")
        println("  Size: $(round(u"m", r.B, digits=2)) × $(round(u"m", r.L_ftg, digits=2)) × $(round(u"m", r.D, digits=2))")
        println("  Rebar: $(r.rebar_count) × $(round(u"mm", r.rebar_dia, digits=0)) each way")
        println("  Concrete: $(round(u"m^3", r.concrete_volume, digits=3))")
        println("  Steel: $(round(u"m^3", r.steel_volume, digits=5))")
        println("  Utilization: $(round(r.utilization * 100, digits=1))%")
        println()
        
        total_concrete += r.concrete_volume
        total_steel += r.steel_volume
        total_area += StructuralSizer.footprint_area(r)
    end
    
    println("─" ^ 60)
    println("TOTALS:")
    println("  Foundations: $(length(struc.foundations))")
    println("  Footprint area: $(round(u"m^2", total_area, digits=2))")
    println("  Concrete volume: $(round(u"m^3", total_concrete, digits=2))")
    println("  Steel volume: $(round(u"m^3", total_steel, digits=4))")
    println("  Steel weight: $(round(u"kg", total_steel * 7850u"kg/m^3", digits=1))")
end

"""
    build_foundation_groups!(struc::BuildingStructure)

Populate `struc.foundation_groups` from `struc.foundations` using `Foundation.group_id`.
"""
function build_foundation_groups!(struc::BuildingStructure)
    empty!(struc.foundation_groups)
    
    for (f_idx, f) in enumerate(struc.foundations)
        gid = f.group_id === nothing ? UInt64(hash((:singleton_foundation_group, f_idx))) : f.group_id
        f.group_id = gid
        
        fg = get!(struc.foundation_groups, gid) do
            FoundationGroup(gid)
        end
        push!(fg.foundation_indices, f_idx)
    end
    
    return struc.foundation_groups
end

# =============================================================================
# Automatic Grouping by Reaction Similarity
# =============================================================================

"""
    group_foundations_by_reaction!(struc::BuildingStructure; 
                                    tolerance=0.15, 
                                    n_support_bins=true,
                                    demands=nothing)

Automatically assign `group_id` to foundations with similar reaction magnitudes.

# Arguments
- `tolerance`: Relative tolerance for grouping (0.15 = 15% difference allowed)
- `n_support_bins`: If true, also separate by number of supports (single vs combined)
- `demands`: Optional precomputed `support_demands(struc)` to avoid recomputation

# Returns
Number of unique groups created.

# Example
```julia
initialize_supports!(struc)
initialize_foundations!(struc)
demands = support_demands(struc)  # Compute once
n_groups = group_foundations_by_reaction!(struc; tolerance=0.0, demands=demands)
size_foundations_grouped!(struc; soil=MEDIUM_SAND, demands=demands)
```
"""
function group_foundations_by_reaction!(struc::BuildingStructure; 
                                         tolerance::Real=0.0,
                                         n_support_bins::Bool=true,
                                         demands::Union{Nothing, Vector{StructuralSizer.FoundationDemand}}=nothing)
    isempty(struc.foundations) && throw(ArgumentError("No foundations. Call initialize_foundations!() first."))
    
    demands = isnothing(demands) ? support_demands(struc) : demands
    
    # Compute governing Pu for each foundation
    foundation_loads = Float64[]
    for fnd in struc.foundations
        if length(fnd.support_indices) == 1
            Pu = ustrip(u"kN", demands[fnd.support_indices[1]].Pu)
        else
            # Combined: sum of loads
            Pu = sum(ustrip(u"kN", demands[i].Pu) for i in fnd.support_indices)
        end
        push!(foundation_loads, Pu)
    end
    
    # Cluster into groups by similarity
    # Simple greedy clustering: assign to existing group if within tolerance, else create new
    groups = Dict{UInt64, Vector{Int}}()
    group_loads = Dict{UInt64, Float64}()  # Representative load for each group
    
    for (f_idx, load) in enumerate(foundation_loads)
        fnd = struc.foundations[f_idx]
        n_supports = length(fnd.support_indices)
        
        # Find compatible group
        assigned = false
        for (gid, rep_load) in group_loads
            # Check tolerance
            if rep_load > 0 && abs(load - rep_load) / rep_load <= tolerance
                # Check n_supports constraint
                if !n_support_bins || _group_n_supports(struc, groups[gid]) == n_supports
                    push!(groups[gid], f_idx)
                    # Update representative to max (conservative)
                    group_loads[gid] = max(rep_load, load)
                    assigned = true
                    break
                end
            end
        end
        
        if !assigned
            # Create new group
            gid = UInt64(hash((:foundation_reaction_group, length(groups) + 1, n_supports)))
            groups[gid] = [f_idx]
            group_loads[gid] = load
        end
    end
    
    # Assign group_ids to foundations
    for (gid, f_indices) in groups
        for f_idx in f_indices
            struc.foundations[f_idx].group_id = gid
        end
    end
    
    # Build the groups dict
    build_foundation_groups!(struc)
    
    n_groups = length(groups)
    @info "Grouped $(length(struc.foundations)) foundations into $n_groups groups (tolerance=$(tolerance*100)%)"
    
    return n_groups
end

# Helper: get number of supports for foundations in a group
function _group_n_supports(struc, f_indices)
    isempty(f_indices) && return 0
    return length(struc.foundations[f_indices[1]].support_indices)
end

"""
    size_foundations_grouped!(struc::BuildingStructure; soil, concrete, rebar, demands=nothing, kwargs...)

Size foundations at the group level: design for governing load, apply to all in group.

This is more efficient than individual sizing and ensures constructability
(same footing size for similar columns).

# Arguments
Same as `size_foundations!`, plus:
- `demands`: Optional precomputed `support_demands(struc)` to avoid recomputation
"""
function size_foundations_grouped!(
    struc::BuildingStructure;
    soil::StructuralSizer.Soil,
    concrete::StructuralSizer.Concrete=StructuralSizer.NWC_4000,
    rebar::StructuralSizer.Metal=StructuralSizer.Rebar_60,
    pier_width=0.3u"m",
    demands::Union{Nothing, Vector{StructuralSizer.FoundationDemand}}=nothing,
    kwargs...
)
    isempty(struc.foundations) && throw(ArgumentError("No foundations. Call initialize_foundations!() first."))
    
    # Build groups if not already done
    isempty(struc.foundation_groups) && build_foundation_groups!(struc)
    
    demands = isnothing(demands) ? support_demands(struc) : demands
    
    # Design once per group using governing demand
    group_results = Dict{UInt64, StructuralSizer.AbstractFoundationResult}()
    
    for (gid, fg) in struc.foundation_groups
        f_indices = fg.foundation_indices
        isempty(f_indices) && continue
        
        # Find governing demand in group
        gov_Pu = 0.0u"kN"
        gov_Mux = 0.0u"kN*m"
        gov_Muy = 0.0u"kN*m"
        gov_Vux = 0.0u"kN"
        gov_Vuy = 0.0u"kN"
        
        for f_idx in f_indices
            fnd = struc.foundations[f_idx]
            
            if length(fnd.support_indices) == 1
                d = demands[fnd.support_indices[1]]
                gov_Pu = max(gov_Pu, d.Pu)
                gov_Mux = max(gov_Mux, abs(d.Mux))
                gov_Muy = max(gov_Muy, abs(d.Muy))
                gov_Vux = max(gov_Vux, abs(d.Vux))
                gov_Vuy = max(gov_Vuy, abs(d.Vuy))
            else
                # Combined footing
                total_Pu = sum(demands[i].Pu for i in fnd.support_indices)
                gov_Pu = max(gov_Pu, total_Pu)
            end
        end
        
        gov_Ps = gov_Pu / 1.4
        
        # Design for governing
        gov_demand = StructuralSizer.FoundationDemand(1;
            Pu=gov_Pu, Mux=gov_Mux, Muy=gov_Muy, 
            Vux=gov_Vux, Vuy=gov_Vuy, Ps=gov_Ps)
        
        result = StructuralSizer.design_spread_footing(
            gov_demand, soil, concrete, rebar;
            pier_width=pier_width, kwargs...
        )
        
        group_results[gid] = result
    end
    
    # Apply group result to all foundations in each group (with volumes)
    for (f_idx, fnd) in enumerate(struc.foundations)
        gid = fnd.group_id
        gid === nothing && continue
        
        result = group_results[gid]
        volumes = _compute_foundation_volumes(result, concrete, rebar)
        struc.foundations[f_idx] = Foundation(
            fnd.support_indices, result;
            foundation_type=fnd.foundation_type, group_id=gid, volumes=volumes
        )
    end
    
    # Summary
    n_groups = length(struc.foundation_groups)
    total_concrete = sum(StructuralSizer.concrete_volume(f.result) for f in struc.foundations)
    total_steel = sum(StructuralSizer.steel_volume(f.result) for f in struc.foundations)
    
    @info "Sized $n_groups foundation groups ($(length(struc.foundations)) total foundations)" total_concrete total_steel
    
    return struc
end

"""
    foundation_group_summary(struc::BuildingStructure; demands=nothing)

Print a summary organized by foundation groups.

# Arguments
- `demands`: Optional precomputed `support_demands(struc)` to avoid recomputation
"""
function foundation_group_summary(struc::BuildingStructure; 
                                   demands::Union{Nothing, Vector{StructuralSizer.FoundationDemand}}=nothing)
    isempty(struc.foundation_groups) && return println("No foundation groups. Call build_foundation_groups!() first.")
    
    demands = isnothing(demands) ? support_demands(struc) : demands
    
    println("\n=== Foundation Group Summary ===")
    println("─" ^ 70)
    
    total_concrete = 0.0u"m^3"
    total_steel = 0.0u"m^3"
    
    for (g_idx, (gid, fg)) in enumerate(struc.foundation_groups)
        f_indices = fg.foundation_indices
        n_ftg = length(f_indices)
        
        # Get representative foundation
        fnd = struc.foundations[f_indices[1]]
        r = fnd.result
        
        # Load range in group
        loads = Float64[]
        for f_idx in f_indices
            f = struc.foundations[f_idx]
            if length(f.support_indices) == 1
                push!(loads, ustrip(u"kN", demands[f.support_indices[1]].Pu))
            else
                push!(loads, sum(ustrip(u"kN", demands[i].Pu) for i in f.support_indices))
            end
        end
        
        load_min = minimum(loads)
        load_max = maximum(loads)
        
        println("Group $g_idx: $n_ftg foundations")
        println("  Load range: $(round(load_min, digits=1)) - $(round(load_max, digits=1)) kN")
        println("  Size: $(round(u"m", r.B, digits=2)) × $(round(u"m", r.L_ftg, digits=2)) × $(round(u"m", r.D, digits=2))")
        println("  Rebar: $(r.rebar_count) × $(round(u"mm", r.rebar_dia, digits=0)) each way")
        println("  Concrete/footing: $(round(u"m^3", r.concrete_volume, digits=3))")
        println("  Group total concrete: $(round(u"m^3", r.concrete_volume * n_ftg, digits=2))")
        println()
        
        total_concrete += r.concrete_volume * n_ftg
        total_steel += r.steel_volume * n_ftg
    end
    
    println("─" ^ 70)
    println("TOTALS:")
    println("  Groups: $(length(struc.foundation_groups))")
    println("  Foundations: $(length(struc.foundations))")
    println("  Concrete volume: $(round(u"m^3", total_concrete, digits=2))")
    println("  Steel volume: $(round(u"m^3", total_steel, digits=4))")
    println("  Steel weight: $(round(u"kg", total_steel * 7850u"kg/m^3", digits=1))")
end
