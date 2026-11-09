# Rules merging a field across a cluster's units: `(values, capacities) -> value`.

"""
Capacity-weighted average, for per-MW and fractional values. Exact for the cluster: e.g. it
gives the cluster's fuel use per MWh at full output.
"""
capacity_weighted(values::AbstractVector{Float64}, capacities::AbstractVector{Float64}) =
    sum(values .* capacities) / sum(capacities)

"""
Sum, for capacities.
"""
total(values::AbstractVector{Float64}, ::AbstractVector{Float64}) = sum(values)

"""
Largest value, for minimum up and down times.
"""
largest(values::AbstractVector{Float64}, ::AbstractVector{Float64}) = maximum(values)

"""
Merge thermal operating costs: every per-MW term capacity-weighted, the fuel price weighted by
fuel use so the full-output fuel cost is exact.
"""
function merge_costs(
    costs::AbstractVector{PSY.ThermalGenerationCost},
    capacities::AbstractVector{Float64},
)
    return PSY.ThermalGenerationCost(;
        variable_operation_cost = _merge_curves(
            [PSY.get_variable_operation_cost(cost) for cost in costs],
            capacities,
        ),
        fixed = 0.0,
        start_up = capacity_weighted(PSY.get_start_up.(costs), capacities),
        shut_down = capacity_weighted(PSY.get_shut_down.(costs), capacities),
    )
end

"""
Merge renewable operating costs: variable and curtailment costs capacity-weighted.
"""
merge_costs(
    costs::AbstractVector{PSY.RenewableGenerationCost},
    capacities::AbstractVector{Float64},
) = PSY.RenewableGenerationCost(;
    variable_operation_cost = _merge_curves(
        PSY.get_variable_operation_cost.(costs),
        capacities,
    ),
    curtailment_cost = _merge_curves(PSY.get_curtailment_cost.(costs), capacities),
)

"""
Merge hydro operating costs: the variable cost capacity-weighted.
"""
merge_costs(
    costs::AbstractVector{PSY.HydroGenerationCost},
    capacities::AbstractVector{Float64},
) = PSY.HydroGenerationCost(;
    variable_operation_cost = _merge_curves(
        PSY.get_variable_operation_cost.(costs),
        capacities,
    ),
    fixed = 0.0,
)

function _merge_curves(
    curves::AbstractVector{<:IS.CostCurve},
    capacities::AbstractVector{Float64},
)
    return IS.CostCurve(
        _merge_linear(IS.get_value_curve.(curves), capacities),
        PSY.NaturalUnit(),
        _merge_linear(IS.get_vom_cost.(curves), capacities),
    )
end

"""
Merge renewable operating costs: variable and curtailment costs capacity-weighted.
"""
merge_costs(
    costs::AbstractVector{PSY.RenewableGenerationCost},
    capacities::AbstractVector{Float64},
) = PSY.RenewableGenerationCost(;
    variable_operation_cost = _merge_curves(
        PSY.get_variable_operation_cost.(costs),
        capacities,
    ),
    curtailment_cost = _merge_curves(PSY.get_curtailment_cost.(costs), capacities),
)

"""
Merge hydro operating costs: the variable cost capacity-weighted.
"""
merge_costs(
    costs::AbstractVector{PSY.HydroGenerationCost},
    capacities::AbstractVector{Float64},
) = PSY.HydroGenerationCost(;
    variable_operation_cost = _merge_curves(
        PSY.get_variable_operation_cost.(costs),
        capacities,
    ),
    fixed = 0.0,
)

function _merge_curves(
    curves::AbstractVector{<:IS.FuelCurve},
    capacities::AbstractVector{Float64},
)
    heat_rates = IS.get_value_curve.(curves)
    fuel_use = IS.get_proportional_term.(heat_rates) .* capacities
    return IS.FuelCurve(
        _merge_linear(heat_rates, capacities),
        PSY.NaturalUnit(),
        IS.get_fuel_units(first(curves)),
        capacity_weighted(IS.get_fuel_cost.(curves), fuel_use),
        _merge_linear(IS.get_startup_fuel_offtake.(curves), capacities),
        _merge_linear(IS.get_vom_cost.(curves), capacities),
    )
end

_merge_linear(
    curves::AbstractVector{<:IS.LinearCurve},
    capacities::AbstractVector{Float64},
) =
    IS.LinearCurve(
        capacity_weighted(IS.get_proportional_term.(curves), capacities),
        capacity_weighted(IS.get_constant_term.(curves), capacities),
    )

"""
Rules for merging thermal technology fields. Override one with
`merge(THERMAL_RULES, (time_limits = my_rule,))`.
"""
const THERMAL_RULES = (
    capacity_limits = total,
    min_generation_fraction = capacity_weighted,
    ramp_limits = capacity_weighted,
    time_limits = largest,
    start_fuel_mmbtu_per_mw = capacity_weighted,
    operation_costs = merge_costs,
)

"""
Rules for merging hydro technology fields.
"""
const HYDRO_RULES = (
    capacity_limits = total,
    min_generation_fraction = capacity_weighted,
    ramp_limits = capacity_weighted,
    time_limits = largest,
    operation_costs = merge_costs,
)

"""
Rules for merging renewable technology fields.
"""
const RENEWABLE_RULES = (capacity_limits = total, operation_costs = merge_costs)

default_rules(::ThermalDevice) = THERMAL_RULES
default_rules(::PSY.HydroDispatch) = HYDRO_RULES
default_rules(::RenewableDevice) = RENEWABLE_RULES
