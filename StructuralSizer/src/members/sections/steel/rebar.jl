"""Standard deformed reinforcing bar per ASTM A615."""
struct Rebar{L, W, A} <: AbstractSection
    size::Int
    material::Metal
    diameter::L     # Length (e.g., inch)
    weight::W       # Linear mass (e.g., lb/ft)
    A::A            # Area (e.g., inch²)
end

"""Moment of inertia about any axis for a solid circular bar (in⁴)."""
compute_Ix(r::Rebar) = π * r.diameter^4 / 64
"""Moment of inertia about any axis (= `compute_Ix`, symmetric) (in⁴)."""
compute_Iy(r::Rebar) = compute_Ix(r)
"""Polar moment of inertia `J = πd⁴/32` for a solid circular bar (in⁴)."""
compute_J(r::Rebar)  = π * r.diameter^4 / 32
"""Radius of gyration `r = d/4` for a solid circular bar (in)."""
compute_r(r::Rebar)  = r.diameter / 4

"""Return bar geometry as a single-element tuple `(diameter,)`."""
geometry(r::Rebar) = (r.diameter,)
"""Return 2D circular outline coordinates for the rebar cross-section."""
get_coords(r::Rebar) = get_circle_coords(r.diameter / 2)

"""Nominal cross-sectional area (in²)."""
section_area(r::Rebar) = r.A
"""Bar diameter (in)."""
section_depth(r::Rebar) = r.diameter
"""Bar diameter (in) — circular section, same as depth."""
section_width(r::Rebar) = r.diameter

"""Generate `n+1` equally-spaced 2D points on a circle of given `radius` for plotting."""
function get_circle_coords(radius, n=32)
    θ = range(0, 2π, length=n+1)
    return [[radius * cos(t), radius * sin(t)] for t in θ]
end

"""Global catalog of standard rebar sizes, keyed by bar number (e.g., 3 for #3)."""
const REBAR_CATALOG = Dict{Int, Any}()

"""Populate `REBAR_CATALOG` with ASTM A615 Grade 60 standard bar sizes (#3–#18)."""
function load_rebar_catalog!()
    data = [
        (3,  0.375, 0.376, 0.11),
        (4,  0.500, 0.668, 0.20),
        (5,  0.625, 1.043, 0.31),
        (6,  0.750, 1.502, 0.44),
        (7,  0.875, 2.044, 0.60),
        (8,  1.000, 2.670, 0.79),
        (9,  1.128, 3.400, 1.00),
        (10, 1.270, 4.303, 1.27),
        (11, 1.410, 5.313, 1.56),
        (14, 1.693, 7.650, 2.25),
        (18, 2.257, 13.600, 4.00),
    ]
    for (sz, d, w, a) in data
        REBAR_CATALOG[sz] = Rebar(sz, Rebar_60, d * u"inch", w * u"lb/ft", a * u"inch^2")
    end
    nothing
end

"""Get rebar by size (e.g., `rebar(4)` for #4 bar)."""
function rebar(size::Int; material=Rebar_60)
    isempty(REBAR_CATALOG) && load_rebar_catalog!()
    haskey(REBAR_CATALOG, size) || error("Rebar #$size not found")
    r = REBAR_CATALOG[size]
    material === Rebar_60 ? r : Rebar(r.size, material, r.diameter, r.weight, r.A)
end

"""Return a sorted vector of available rebar size numbers (e.g., `[3, 4, 5, …, 18]`)."""
rebar_sizes() = (isempty(REBAR_CATALOG) && load_rebar_catalog!(); sort(collect(keys(REBAR_CATALOG))))
"""Return a vector of all `Rebar` objects in the catalog."""
all_rebar() = (isempty(REBAR_CATALOG) && load_rebar_catalog!(); collect(values(REBAR_CATALOG)))
