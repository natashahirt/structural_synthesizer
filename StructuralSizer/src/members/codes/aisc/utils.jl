# ==============================================================================
# AISC Utilities (shared helpers across shapes)
# ==============================================================================

@inline function _linear_interp(x, x0, x1, y0, y1)
    x <= x0 && return y0
    x >= x1 && return y1
    y0 + (y1 - y0) * ((x - x0) / (x1 - x0))
end

@inline function _Fe_euler(E, L, r)
    KL_r = L / r
    return π^2 * E / KL_r^2
end

@inline function _Fcr_column(Fe, Fy)
    ratio = Fy / Fe
    if ratio <= 2.25
        return (0.658^ratio) * Fy
    else
        return 0.877 * Fe
    end
end
