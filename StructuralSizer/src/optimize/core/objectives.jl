# Objective Functions
# Each defines a scalar value to minimize during optimization.

abstract type AbstractObjective end

"""Minimize total member weight: A × L × ρ"""
struct MinWeight <: AbstractObjective end

"""Minimize total member volume: A × L"""
struct MinVolume <: AbstractObjective end

"""
Minimize total cost.

- `MinCost()` — uses `material.cost` [\$/kg] (errors if cost=NaN)
- `MinCost(c::Real)` — explicit unit cost [\$/kg]
- `MinCost(f::Function)` — custom cost function `f(section, material) -> cost_per_length`
"""
struct MinCost{T} <: AbstractObjective
    unit_cost::T
end
MinCost(c::Real) = MinCost{typeof(c)}(c)
MinCost() = MinCost(NaN)  # Sentinel: use material.cost at evaluation time

"""Minimize embodied carbon: A × L × ρ × ecc"""
struct MinCarbon <: AbstractObjective end

# Objective value computation
function objective_value end

function objective_value(::MinWeight, s::AbstractSection, mat::AbstractMaterial, L)
    section_area(s) * L * mat.ρ
end

function objective_value(::MinVolume, s::AbstractSection, L)
    section_area(s) * L
end
objective_value(::MinVolume, s::AbstractSection, ::AbstractMaterial, L) = objective_value(MinVolume(), s, L)

function objective_value(obj::MinCost{<:Real}, s::AbstractSection, mat::AbstractMaterial, L)
    # If unit_cost is NaN (from MinCost()), use material.cost
    cost = isnan(obj.unit_cost) ? mat.cost : obj.unit_cost
    isnan(cost) && error("MinCost requires material.cost to be set (material has cost=NaN). " *
                         "Either set cost on your material or use MinCost(unit_cost_per_kg).")
    section_area(s) * L * mat.ρ * cost
end

function objective_value(obj::MinCost{<:Function}, s::AbstractSection, mat::AbstractMaterial, L)
    obj.unit_cost(s, mat) * L
end

function objective_value(::MinCarbon, s::AbstractSection, mat::AbstractMaterial, L)
    section_area(s) * L * mat.ρ * mat.ecc
end

# Batch computation
function total_objective(obj::AbstractObjective, sections, materials, lengths)
    sum(objective_value(obj, s, m, L) for (s, m, L) in zip(sections, materials, lengths))
end

function total_objective(obj::AbstractObjective, sections, mat::AbstractMaterial, lengths)
    sum(objective_value(obj, s, mat, L) for (s, L) in zip(sections, lengths))
end
