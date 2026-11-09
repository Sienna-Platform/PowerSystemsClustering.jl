# Renewable device types converted to `PSIP.SupplyTechnology`.
const RenewableDevice = Union{PSY.RenewableDispatch, PSY.RenewableNonDispatch}

"""
Make a `PSIP.SupplyTechnology` for the existing renewable unit `device`. Capacity is rating ×
power factor.
"""
function make_technology(
    device::T,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData,
) where {T <: RenewableDevice}
    return PSIP.SupplyTechnology{T}(;
        _existing_generator_fields(device, aggregation, financial_data)...,
        time_limits = (up = 0.0, down = 0.0),
        operation_costs = renewable_operation_costs(device),
    )
end

"""
Operating costs of the renewable unit `device`: variable and curtailment costs linearized at
maximum output. A `RenewableNonDispatch` has none.
"""
function renewable_operation_costs(device::PSY.RenewableDispatch)
    op_cost = PSY.get_operation_cost(device)
    limits = (min = 0.0, max = PSY.get_max_active_power(device, u"MW"))
    linear(curve, fixed) =
        _linear_variable_cost(curve, AverageRate(), limits, fixed, device)
    return PSY.RenewableGenerationCost(;
        variable_operation_cost = linear(
            PSY.get_variable_operation_cost(op_cost),
            PSY.get_fixed(op_cost),
        ),
        curtailment_cost = linear(PSY.get_curtailment_cost(op_cost), 0.0),
    )
end

renewable_operation_costs(::PSY.RenewableNonDispatch) =
    PSY.RenewableGenerationCost(; variable_operation_cost = zero(IS.CostCurve))
