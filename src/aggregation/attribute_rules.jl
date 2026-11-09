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

"""
Merge storage operating costs: every term weighted by discharge power, start-up costs per mode
when given per mode.
"""
function merge_costs(
    costs::AbstractVector{PSY.StorageCost},
    capacities::AbstractVector{Float64},
)
    weighted(getter) = _merge_field(capacity_weighted, getter.(costs), capacities)
    return PSY.StorageCost(;
        charge_variable_cost = _merge_curves(
            PSY.get_charge_variable_cost.(costs),
            capacities,
        ),
        discharge_variable_cost = _merge_curves(
            PSY.get_discharge_variable_cost.(costs),
            capacities,
        ),
        start_up = weighted(PSY.get_start_up),
        shut_down = weighted(PSY.get_shut_down),
        energy_shortage_cost = weighted(PSY.get_energy_shortage_cost),
        energy_surplus_cost = weighted(PSY.get_energy_surplus_cost),
    )
end

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

# Weights for storage rules, from a unit's fields.
_charge_mw(fields::NamedTuple) = fields.capacity_limits_charge.max
_discharge_mw(fields::NamedTuple) = fields.capacity_limits_discharge.max
_energy_mwh(fields::NamedTuple) = fields.capacity_limits_energy.max

"""
Rules for merging storage technology fields, weighted by discharge power except charge
efficiency (by charge power) and losses (by energy capacity).
"""
const STORAGE_RULES = (
    capacity_limits_charge = total,
    capacity_limits_discharge = total,
    capacity_limits_energy = total,
    min_discharge_fraction = capacity_weighted,
    efficiency = capacity_weighted => (in = _charge_mw, out = _discharge_mw),
    losses = capacity_weighted => _energy_mwh,
    operation_costs = merge_costs,
)

default_rules(::ThermalDevice) = THERMAL_RULES
default_rules(::PSY.HydroDispatch) = HYDRO_RULES
default_rules(::RenewableDevice) = RENEWABLE_RULES
default_rules(::PSY.EnergyReservoirStorage) = STORAGE_RULES
