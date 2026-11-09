# Charge, discharge and energy capacities are the maximum input power, maximum output power and
# storage capacity.
function technology_fields(
    device::PSY.EnergyReservoirStorage,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData;
    kwargs...,
)
    input = PSY.get_input_active_power_limits(device, u"MW")
    output = PSY.get_output_active_power_limits(device, u"MW")
    return (;
        _existing_device_fields(device, aggregation, financial_data)...,
        storage_tech = PSY.get_storage_technology_type(device),
        operation_costs = storage_operation_costs(device),
        min_discharge_fraction = output.min / output.max,
        capacity_limits_charge = (min = 0.0, max = input.max),
        capacity_limits_discharge = (min = 0.0, max = output.max),
        capacity_limits_energy = (min = 0.0, max = PSY.get_storage_capacity(device, u"MW")),
        efficiency = PSY.get_efficiency(device),
        losses = 60.0 * PSY.get_self_discharge(device),
    )
end

"""
Operating costs of the storage unit `device`: charge and discharge costs linearized at maximum
power, start-up and shut-down costs per MW of maximum output.
"""
function storage_operation_costs(device::PSY.EnergyReservoirStorage)
    op_cost = PSY.get_operation_cost(device)
    max_input_mw = PSY.get_input_active_power_limits(device, u"MW").max
    max_output_mw = PSY.get_output_active_power_limits(device, u"MW").max
    linear(curve, max_mw) =
        _linear_variable_cost(curve, AverageRate(), (min = 0.0, max = max_mw), 0.0, device)
    return PSY.StorageCost(;
        charge_variable_cost = linear(PSY.get_charge_variable_cost(op_cost), max_input_mw),
        discharge_variable_cost = linear(
            PSY.get_discharge_variable_cost(op_cost),
            max_output_mw,
        ),
        start_up = _per_mw(PSY.get_start_up(op_cost), max_output_mw),
        shut_down = PSY.get_shut_down(op_cost) / max_output_mw,
        energy_shortage_cost = PSY.get_energy_shortage_cost(op_cost),
        energy_surplus_cost = PSY.get_energy_surplus_cost(op_cost),
    )
end

# Start-up cost per MW, single or per mode (charge, discharge).
_per_mw(cost::Float64, mw::Float64) = cost / mw
_per_mw(cost::PSY.STORAGE_OPERATION_MODES, mw::Float64) = map(c -> c / mw, cost)
