# ============================================================================
# Axis Style Functions
# ============================================================================

"""
    graystyle!(axis::Axis; backgroundcolor = :lightgray, backgroundalpha = 0.15, grid = true, gridcolor = :white)

Apply a gray background style to an Axis.
"""
function graystyle!(axis::Axis;
    backgroundcolor = :lightgray,
    backgroundalpha = 0.15,
    grid = true,
    gridcolor = :white
)
    axis.backgroundcolor = (backgroundcolor, backgroundalpha)
    axis.xticksvisible = axis.yticksvisible = false
    axis.rightspinevisible = axis.topspinevisible = false
    if grid
        axis.xgridvisible = axis.ygridvisible = true
        axis.xgridcolor = axis.ygridcolor = gridcolor
    end
end

"""
    graystyle!(axis::Axis3; backgroundcolor = :lightgray, backgroundalpha = 0.15)

Apply a gray background style to an Axis3.
"""
function graystyle!(axis::Axis3;
    backgroundcolor = :lightgray,
    backgroundalpha = 0.15
)
    axis.xzpanelcolor = axis.yzpanelcolor = axis.xypanelcolor = (backgroundcolor, backgroundalpha)
    axis.xticksvisible = axis.yticksvisible = axis.zticksvisible = false
    simplifyspines!(axis)
    axis.xgridvisible = axis.ygridvisible = axis.zgridvisible = false
end

"""
    structurestyle!(axis::Axis; ground = false, groundcolor = :black, groundwidth = 2)

Apply a clean structural visualization style.
"""
function structurestyle!(axis::Axis;
    ground = false,
    groundcolor = :black,
    groundwidth = 2
)
    hidedecorations!(axis)
    hidespines!(axis)
    if ground
        axis.bottomspinevisible = true
        axis.spinewidth = groundwidth
        axis.bottomspinecolor = groundcolor
    end
end

"""
    cleanstyle!(axis::Axis3; ground = false, groundcolor = :lightgray, groundalpha = 0.5)

Apply a clean minimal style to Axis3.
"""
function cleanstyle!(axis::Axis3;
    ground = false,
    groundcolor = :lightgray,
    groundalpha = 0.5
)
    hidedecorations!(axis)
    hidespines!(axis)
    if ground
        axis.xypanelcolor = (groundcolor, groundalpha)
    end
end

"""
    asapstyle!(axis::Axis; ground = false, groundcolor = :black, groundwidth = 2)

Apply the ASAP structural visualization style to Axis.
"""
function asapstyle!(axis::Axis;
    ground = false,
    groundcolor = :black,
    groundwidth = 2
)
    hidedecorations!(axis)
    hidespines!(axis)
    axis.aspect = DataAspect()
    if ground
        axis.bottomspinevisible = true
        axis.spinewidth = groundwidth
        axis.bottomspinecolor = groundcolor
    end
end

"""
    asapstyle!(axis::Axis3; ground = false, groundcolor = :lightgray, groundalpha = 0.5)

Apply the ASAP structural visualization style to Axis3.
"""
function asapstyle!(axis::Axis3;
    ground = false,
    groundcolor = :lightgray,
    groundalpha = 0.5
)
    hidedecorations!(axis)
    hidespines!(axis)
    axis.aspect = :data
    if ground
        axis.xypanelcolor = (groundcolor, groundalpha)
    end
end

"""
    blueprintstyle!(axis::Axis; gridcolor = sp_skyblue, gridalpha = 0.3)

Apply a blueprint-style visualization (blue grid on dark background).
"""
function blueprintstyle!(axis::Axis;
    gridcolor = sp_skyblue,
    gridalpha = 0.3
)
    axis.backgroundcolor = (sp_darkpurple, 0.95)
    axis.xgridvisible = axis.ygridvisible = true
    axis.xgridcolor = axis.ygridcolor = (gridcolor, gridalpha)
    axis.xticksvisible = axis.yticksvisible = false
    axis.leftspinecolor = axis.bottomspinecolor = :white
    axis.rightspinecolor = axis.topspinecolor = :transparent
end
