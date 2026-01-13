# Simplified L/h thickness rules
# Quick estimates for preliminary design; not code-compliant for final design.

"""
Simplified minimum thickness using L/28 rule.
Applies to one-way and two-way slabs as a rough estimate.
"""
function min_thickness(::Union{OneWay, TwoWay}, span_short::Real, ::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT)
    # L/28 is roughly ACI Table 7.3.1.1 for both ends continuous
    # Adjust for support condition
    divisor = support == SIMPLE ? 20.0 :
              support == ONE_END_CONT ? 24.0 :
              support == BOTH_ENDS_CONT ? 28.0 :
              support == CANTILEVER ? 10.0 : 28.0
    
    h = span_short / divisor
    return max(MIN_SLAB_THICKNESS, h)
end

"""Flat plate: use shorter span / 33 (ACI approximation)."""
function min_thickness(::FlatPlate, span_short::Real, ::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT)
    divisor = support == SIMPLE ? 28.0 :
              support == BOTH_ENDS_CONT ? 33.0 : 30.0
    h = span_short / divisor
    return max(MIN_SLAB_THICKNESS, h)
end

"""Flat slab with drop panels: use shorter span / 36."""
function min_thickness(::FlatSlab, span_short::Real, ::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT)
    divisor = support == SIMPLE ? 31.0 :
              support == BOTH_ENDS_CONT ? 36.0 : 33.0
    h = span_short / divisor
    return max(MIN_SLAB_THICKNESS, h)
end

"""PT banded slab: typically L/45 for preliminary."""
function min_thickness(::PTBanded, span_short::Real, ::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT)
    h = span_short / 45.0
    return max(MIN_SLAB_THICKNESS, h)
end

"""Waffle slab: similar to two-way, L/28-30."""
function min_thickness(::Waffle, span_short::Real, ::Concrete;
                       support::SupportCondition=BOTH_ENDS_CONT)
    h = span_short / 28.0
    return max(MIN_SLAB_THICKNESS, h)
end

# Unitful overloads
for SlabT in (OneWay, TwoWay, FlatPlate, FlatSlab, PTBanded, Waffle)
    @eval function min_thickness(st::$SlabT, span_short::Unitful.Length, mat::Concrete; kwargs...)
        h_m = min_thickness(st, ustrip(u"m", span_short), mat; kwargs...)
        return h_m * u"m"
    end
end
