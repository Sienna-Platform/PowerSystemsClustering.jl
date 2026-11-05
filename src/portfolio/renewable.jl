# Renewable device types converted to `PSIP.SupplyTechnology`.
const RenewableDevice = Union{PSY.RenewableDispatch, PSY.RenewableNonDispatch}

"""
Make a `PSIP.SupplyTechnology` for the renewable unit `device`, in its region at the
aggregation level `aggregation`.

Capacity is the device's maximum active power (rating × power factor), so the technology is
the existing unit with no new builds. Costs come from [`renewable_operation_costs`](@ref). The
capacity factor profile is added to the technology with the representative periods.
"""
function make_technology(
    device::T,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData,
) where {T <: RenewableDevice}
    max_mw = PSY.get_max_active_power(device, u"MW")
    return PSIP.SupplyTechnology{T}(;
        name = PSY.get_name(device),
        power_systems_type = string(nameof(T)),
        region = PSY.Topology[get_device_region(aggregation, device)],
        available = PSY.get_available(device),
        prime_mover_type = PSY.get_prime_mover_type(device),
        operation_costs = renewable_operation_costs(device),
        capacity_limits = (min = 0.0, max = max_mw),
        financial_data = financial_data,
    )
end

"""
Operating costs of the renewable unit `device` as PSIN reads them: the variable and
curtailment cost curves linearized at maximum output, with PowerSystems' `fixed` cost (per hour
online) added to the variable cost. A `RenewableNonDispatch` has no costs.

Throws `ArgumentError` for curves not in MW.
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
