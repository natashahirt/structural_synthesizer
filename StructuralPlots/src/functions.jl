# ============================================================================
# Utility Functions
# ============================================================================

"""
    discretize(n::Integer; colormap = :viridis)

Discretize a color gradient into `n` discrete colours.
Returns a vector of colors that can be indexed from 1 to `n`.
"""
function discretize(n::Integer; colormap = :viridis)
    return [cgrad(colormap, [0.0, 1.0])[z] for z ∈ range(0.0, 1.0, length = n)]
end

"""
    labelize!(axis::Axis3)

Toggle visibility of title and all axis labels/tick labels for Axis3.
"""
function labelize!(axis::Axis3)
    axis.titlevisible        = !axis.titlevisible[]
    axis.xlabelvisible       = !axis.xlabelvisible[]
    axis.xticklabelsvisible  = !axis.xticklabelsvisible[]
    axis.ylabelvisible       = !axis.ylabelvisible[]
    axis.yticklabelsvisible  = !axis.yticklabelsvisible[]
    axis.zlabelvisible       = !axis.zlabelvisible[]
    axis.zticklabelsvisible  = !axis.zticklabelsvisible[]
end

"""
    labelize!(axis::Axis)

Toggle visibility of title and all axis labels/tick labels for Axis.
"""
function labelize!(axis::Axis)
    axis.titlevisible        = !axis.titlevisible[]
    axis.xgridvisible        = !axis.xgridvisible[]
    axis.xlabelvisible       = !axis.xlabelvisible[]
    axis.xticklabelsvisible  = !axis.xticklabelsvisible[]
    axis.xticksvisible       = !axis.xticksvisible[]
    axis.ygridvisible        = !axis.ygridvisible[]
    axis.ylabelvisible       = !axis.ylabelvisible[]
    axis.yticklabelsvisible  = !axis.yticklabelsvisible[]
    axis.yticksvisible       = !axis.yticksvisible[]
end

"""
    labelscale!(axis::Axis, factor::Real)

Scale the font size of the title and labels by `factor`.
"""
function labelscale!(axis::Axis, factor::Real)
    axis.xlabelsize     = labelFontSize * factor
    axis.ylabelsize     = labelFontSize * factor
    axis.xticklabelsize = tickFontSize * factor
    axis.yticklabelsize = tickFontSize * factor
    axis.titlesize      = titleFontSize * factor
end

"""
    labelscale!(axis::Axis3, factor::Real)

Scale the font size of the title and labels by `factor`.
"""
function labelscale!(axis::Axis3, factor::Real)
    axis.titlesize      = titleFontSize * factor
    axis.xlabelsize     = labelFontSize * factor
    axis.ylabelsize     = labelFontSize * factor
    axis.zlabelsize     = labelFontSize * factor
    axis.xticklabelsize = tickFontSize * factor
    axis.yticklabelsize = tickFontSize * factor
    axis.zticklabelsize = tickFontSize * factor
end

"""
    resetlabelscale!(axis::Axis)

Reset the font size to default values.
"""
function resetlabelscale!(axis::Axis)
    axis.xlabelsize     = labelFontSize
    axis.ylabelsize     = labelFontSize
    axis.xticklabelsize = tickFontSize
    axis.yticklabelsize = tickFontSize
    axis.titlesize      = titleFontSize
end

"""
    resetlabelscale!(axis::Axis3)

Reset the font size to default values.
"""
function resetlabelscale!(axis::Axis3)
    axis.titlesize      = titleFontSize
    axis.xlabelsize     = labelFontSize
    axis.ylabelsize     = labelFontSize
    axis.zlabelsize     = labelFontSize
    axis.xticklabelsize = tickFontSize
    axis.yticklabelsize = tickFontSize
    axis.zticklabelsize = tickFontSize
end

"""
    changefont!(axis::Axis, font::String)

Change the font for all text elements in the axis.
"""
function changefont!(axis::Axis, font::String)
    axis.titlefont      = font
    axis.xlabelfont     = font
    axis.ylabelfont     = font
    axis.xticklabelfont = font
    axis.yticklabelfont = font
end

"""
    changefont!(axis::Axis3, font::String)

Change the font for all text elements in the 3D axis.
"""
function changefont!(axis::Axis3, font::String)
    axis.titlefont      = font
    axis.xlabelfont     = font
    axis.ylabelfont     = font
    axis.zlabelfont     = font
    axis.xticklabelfont = font
    axis.yticklabelfont = font
    axis.zticklabelfont = font
end

"""
    gridtoggle!(axis::Axis)

Toggle the visibility of the grid.
"""
function gridtoggle!(axis::Axis)
    axis.xgridvisible = !axis.xgridvisible[]
    axis.ygridvisible = !axis.ygridvisible[]
end

"""
    gridtoggle!(axis::Axis3)

Toggle the visibility of the grid.
"""
function gridtoggle!(axis::Axis3)
    axis.xgridvisible = !axis.xgridvisible[]
    axis.ygridvisible = !axis.ygridvisible[]
    axis.zgridvisible = !axis.zgridvisible[]
end

"""
    simplifyspines!(axis::Axis3)

Simplify spines of an Axis3 to show only one x/y/z spine.
"""
function simplifyspines!(axis::Axis3)
    if axis.xspinecolor_2 != :transparent
        axis.xspinecolor_2 = :transparent
        axis.xspinecolor_3 = :transparent
        axis.yspinecolor_2 = :transparent
        axis.yspinecolor_3 = :transparent
        axis.zspinecolor_2 = :transparent
        axis.zspinecolor_3 = :transparent
    else
        axis.xspinecolor_2 = axis.xspinecolor_1[]
        axis.xspinecolor_3 = axis.xspinecolor_1[]
        axis.yspinecolor_2 = axis.xspinecolor_1[]
        axis.yspinecolor_3 = axis.xspinecolor_1[]
        axis.zspinecolor_2 = axis.xspinecolor_1[]
        axis.zspinecolor_3 = axis.xspinecolor_1[]
    end
end

"""
    linkaxes!(parentaxis::Axis3, childaxis::Axis3)

Link the rotation of a parent Axis3 to a child Axis3.
"""
function linkaxes!(parentaxis::Axis3, childaxis::Axis3)
    on(parentaxis.azimuth) do az
        childaxis.azimuth[] = az
    end
    on(parentaxis.elevation) do el
        childaxis.elevation[] = el
    end
end

"""
    linkaxes!(parentaxis::Axis3, childaxes::Vector{Axis3})

Link the rotation of a parent Axis3 to multiple child Axis3.
"""
function linkaxes!(parentaxis::Axis3, childaxes::Vector{Axis3})
    for child in childaxes
        linkaxes!(parentaxis, child)
    end
end

"""
    linkproperties!(parentaxis, childaxis, properties::Vector{Symbol})

Link specified properties between two axes.
"""
function linkproperties!(parentaxis::Union{Axis,Axis3}, childaxis::Union{Axis,Axis3}, properties::Vector{Symbol})
    @assert typeof(parentaxis) == typeof(childaxis) "Parent and child must have same Axis type"
    for property in properties
        on(getproperty(parentaxis, property)) do val
            getproperty(childaxis, property)[] = val
        end
    end
end

"""
    mirrorticks!(axis::Axis)

Toggle mirrored ticks on the top and right spines.
"""
function mirrorticks!(axis::Axis)
    axis.xticksmirrored = !axis.xticksmirrored[]
    axis.yticksmirrored = !axis.yticksmirrored[]
end

"""
    alignticks!(axis::Axis, value::Integer)

Position of ticks: 0 for outside, 1 for inside.
"""
function alignticks!(axis::Axis, value::Integer)
    @assert value == 0 || value == 1 "Value must be 0 or 1"
    axis.xtickalign = value
    axis.ytickalign = value
end

"""
    tickstoggle!(axis::Union{Axis, Axis3})

Toggle the visibility of ticks.
"""
function tickstoggle!(axis::Union{Axis,Axis3})
    axis.xticksvisible = !axis.xticksvisible[]
    axis.yticksvisible = !axis.yticksvisible[]
    if typeof(axis) == Axis3
        axis.zticksvisible = !axis.zticksvisible[]
    end
end

"""
    fixlimits!(ax::Axis)

Fix axis limits to the current state.
"""
function fixlimits!(ax::Axis)
    lx, ly = copy(ax.finallimits[].origin)
    ux, uy = copy(ax.finallimits[].widths)
    ax.limits = (lx, lx + ux, ly, ly + uy)
end

"""
    fixlimits!(ax::Axis3)

Fix axis limits to the current state.
"""
function fixlimits!(ax::Axis3)
    lx, ly, lz = copy(ax.finallimits[].origin)
    ux, uy, uz = copy(ax.finallimits[].widths)
    ax.limits = ((lx, lx + ux), (ly, ly + uy), (lz, lz + uz))
end

"""
    getfigsize(fig::Figure)

Get the size of a figure in pts.
"""
getfigsize(fig::Figure) = fig.scene.viewport.val.widths
