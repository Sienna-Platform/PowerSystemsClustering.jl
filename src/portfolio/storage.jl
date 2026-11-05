"""
Make a `PSIP.StorageTechnology` for the existing storage unit `device`, in its region at the
aggregation level `aggregation`.

Charge, discharge and energy capacities are the device's maximum input and output active power
and its storage capacity (MWh), so the technology is the existing unit with no new builds. The
minimum discharge is a fraction of the maximum output, self-discharge per minute becomes losses
per hour, and the charge and discharge cost curves are linearized at maximum power. The
`fixed` cost is not carried over (PSIN reads it as fixed O&M).
"""
function make_technology(
    device::PSY.EnergyReservoirStorage,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData,
)
    input = PSY.get_input_active_power_limits(device, u"MW")
    output = PSY.get_output_active_power_limits(device, u"MW")
    return PSIP.StorageTechnology{PSY.EnergyReservoirStorage}(;
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
Charge and discharge costs of the storage unit `device` as PSIN reads them: each cost curve
linearized at maximum input or output power.

Throws `ArgumentError` for curves not in MW.
"""
function storage_operation_costs(device::PSY.EnergyReservoirStorage)
    op_cost = PSY.get_operation_cost(device)
    linear(curve, limits) =
        _linear_variable_cost(
            curve,
            AverageRate(),
            (min = 0.0, max = limits.max),
            0.0,
            device,
        )
    return PSY.StorageCost(;
        charge_variable_cost = linear(
            PSY.get_charge_variable_cost(op_cost),
            PSY.get_input_active_power_limits(device, u"MW"),
        ),
        discharge_variable_cost = linear(
            PSY.get_discharge_variable_cost(op_cost),
            PSY.get_output_active_power_limits(device, u"MW"),
        ),
    )
end
