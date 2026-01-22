# Data visualization (charts, summaries)

"""
    get_material_color(name::String) -> Symbol

Map material category name to display color.
"""
function get_material_color(name::String)
    startswith(name, "Steel")    && return :steelblue
    startswith(name, "Rebar")    && return :hotpink
    startswith(name, "Concrete") && return :gray60
    return :slategray
end

"""
    aggregate_ec_by_material(elements) -> Dict{String, Float64}

Aggregate embodied carbon by material type for a collection of elements.
Returns dict mapping material names to total EC in kgCO₂e.
"""
function aggregate_ec_by_material(elements)
    ec_by_mat = Dict{String, Float64}()
    for elem in elements
        for (mat, vol) in elem.volumes
            mat_name = if mat isa StructuralSizer.Concrete
                "Concrete (fc'=$(round(Int, Unitful.ustrip(u"MPa", mat.fc′))) MPa)"
            elseif mat isa StructuralSizer.StructuralSteel
                "Steel (Fy=$(round(Int, Unitful.ustrip(u"MPa", mat.Fy))) MPa)"
            elseif mat isa StructuralSizer.RebarSteel
                "Rebar (Fy=$(round(Int, Unitful.ustrip(u"MPa", mat.Fy))) MPa)"
            else
                string(typeof(mat).name.name)
            end
            mass_kg = Unitful.ustrip(u"kg", vol * mat.ρ)
            ec_val = mass_kg * mat.ecc
            ec_by_mat[mat_name] = get(ec_by_mat, mat_name, 0.0) + ec_val
        end
    end
    return ec_by_mat
end

"""
    vis_embodied_carbon_summary(struc::BuildingStructure) -> Figure

Create a grouped bar chart showing embodied carbon by system (Slabs, Members, Foundations)
and material type (Steel, Rebar, Concrete).

# Example
```julia
fig = vis_embodied_carbon_summary(struc)
```
"""
function vis_embodied_carbon_summary(struc::BuildingStructure)
    # Compute EC if not already done
    ec = compute_building_ec(struc)
    
    # Aggregate by material for each system
    slab_by_mat = aggregate_ec_by_material(struc.slabs)
    member_by_mat = aggregate_ec_by_material(filter(m -> !isempty(m.volumes), struc.members))
    fdn_by_mat = aggregate_ec_by_material(filter(f -> !isempty(f.volumes), struc.foundations))
    
    # Collect all unique materials
    all_materials = unique(vcat(
        collect(keys(slab_by_mat)),
        collect(keys(member_by_mat)),
        collect(keys(fdn_by_mat))
    ))
    sort!(all_materials)
    
    systems = ["Slabs", "Members", "Foundations"]
    data_by_mat = [slab_by_mat, member_by_mat, fdn_by_mat]
    mat_colors = Dict(m => get_material_color(m) for m in all_materials)
    
    # Build figure
    fig = GLMakie.Figure(size=(900, 500))
    ax = GLMakie.Axis(fig[1, 1],
        title = "Embodied Carbon by System and Material",
        ylabel = "kgCO₂e",
        xticks = (1:3, systems)
    )
    
    # Grouped bars
    n_mats = length(all_materials)
    bar_width = 0.8 / max(n_mats, 1)
    offsets = n_mats > 1 ? range(-0.4 + bar_width/2, 0.4 - bar_width/2, length=n_mats) : [0.0]
    
    for (i, mat_name) in enumerate(all_materials)
        x_positions = [j + offsets[i] for j in 1:3]
        heights = [get(data_by_mat[j], mat_name, 0.0) for j in 1:3]
        
        GLMakie.barplot!(ax, x_positions, heights,
            width = bar_width,
            color = mat_colors[mat_name],
            label = mat_name
        )
        
        # Value labels
        for (x, h) in zip(x_positions, heights)
            h > 0 && GLMakie.text!(ax, x, h,
                text = string(round(Int, h)),
                align = (:center, :bottom),
                fontsize = 9
            )
        end
    end
    
    # Legend and totals
    GLMakie.Legend(fig[1, 2], ax, "Material", framevisible=false)
    GLMakie.Label(fig[2, :],
        "Total: $(round(Int, ec.total_ec)) kgCO₂e  |  Intensity: $(round(ec.ec_per_floor_area, digits=1)) kgCO₂e/m²",
        fontsize = 14
    )
    
    return fig
end
