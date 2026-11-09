"""
Make a `PSIP.SupplyTechnology` for the existing hydro unit `device`.
"""
function make_technology(
    device::PSY.HydroDispatch,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData,
)
    return PSIP.SupplyTechnology{PSY.HydroDispatch}(;
        _existing_generator_fields(device, aggregation, financial_data)...,
        _operating_limits(device)...,
        operation_costs = hydro_operation_costs(device),
    )
end

"""
Operating costs of the hydro unit `device`: its curve linearized at maximum output. A fuel
curve is priced into a cost curve (heat rate × fuel price), since PSIP only converts fuel
curves in thermal costs.
"""
function hydro_operation_costs(device::PSY.HydroDispatch)
    op_cost = PSY.get_operation_cost(device)
    variable_cost = _linear_variable_cost(
        PSY.get_variable_operation_cost(op_cost),
        AverageRate(),
        PSY.get_active_power_limits(device, u"MW"),
        PSY.get_fixed(op_cost),
        device,
    )
    return PSY.HydroGenerationCost(;
        variable_operation_cost = _priced_cost_curve(variable_cost),
        fixed = 0.0,
    )
end

_priced_cost_curve(curve::IS.CostCurve) = curve

function _priced_cost_curve(curve::IS.FuelCurve)
    fuel_curve = IS.get_value_curve(curve)
    fuel_price = IS.get_fuel_cost(curve)
    priced = IS.LinearCurve(
        IS.get_proportional_term(fuel_curve) * fuel_price,
        IS.get_constant_term(fuel_curve) * fuel_price,
    )
    return IS.CostCurve(priced, PSY.NaturalUnit(), IS.get_vom_cost(curve))
end
