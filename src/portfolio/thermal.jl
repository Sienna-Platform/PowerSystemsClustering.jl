# Thermal device types converted to `PSIP.SupplyTechnology`.
const ThermalDevice = Union{PSY.ThermalStandard, PSY.ThermalMultiStart}

function technology_fields(
    device::ThermalDevice,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData;
    linearization::CurveLinearization = AverageRate(),
    start_up_stage::Symbol = :hot,
)
    return (
        _existing_generator_fields(device, aggregation, financial_data)...,
        _operating_limits(device)...,
        fuel = [PSY.get_fuel(device)],
        operation_costs = thermal_operation_costs(device, linearization, start_up_stage),
        start_fuel_mmbtu_per_mw = _start_fuel_per_mw(
            PSY.get_variable_operation_cost(PSY.get_operation_cost(device)),
            PSY.get_max_active_power(device, u"MW"),
        ),
    )
end

# Start-up fuel per MW; only fuel curves have it.
_start_fuel_per_mw(curve::IS.FuelCurve, max_mw::Float64) =
    IS.get_proportional_term(IS.get_startup_fuel_offtake(curve)) / max_mw
_start_fuel_per_mw(::IS.ProductionVariableCostCurve, ::Float64) = 0.0

"""
Operating costs of the thermal unit `device`: its curve linearized by `linearization` with
PowerSystems' `fixed` cost added, start-up costs by stage reduced to `start_up_stage` (`:hot`,
`:warm` or `:cold`), and start-up and shut-down costs per MW. The result's `fixed` is zero
because PSIN reads that field as fixed O&M.
"""
function thermal_operation_costs(
    device::ThermalDevice,
    linearization::CurveLinearization,
    start_up_stage::Symbol,
)
    op_cost = PSY.get_operation_cost(device)
    limits = PSY.get_active_power_limits(device, u"MW")
    variable_cost = _linear_variable_cost(
        PSY.get_variable_operation_cost(op_cost),
        linearization,
        limits,
        PSY.get_fixed(op_cost),
        device,
    )
    start_up = _single_start_up_cost(PSY.get_start_up(op_cost), start_up_stage, device)
    return PSY.ThermalGenerationCost(;
        variable_operation_cost = variable_cost,
        fixed = 0.0,
        start_up = start_up / limits.max,
        shut_down = PSY.get_shut_down(op_cost) / limits.max,
    )
end

_single_start_up_cost(start_up::Float64, ::Symbol, ::ThermalDevice) = start_up

function _single_start_up_cost(
    start_up::PSY.StartUpStages,
    stage::Symbol,
    device::ThermalDevice,
)
    stage_index = findfirst(==(stage), keys(start_up))
    if isnothing(stage_index)
        throw(ArgumentError("start_up_stage must be :hot, :warm or :cold, got :$(stage)."))
    end
    return start_up[min(stage_index, _start_types(device))]
end

# Start-up stages a unit uses; unused stages hold placeholder costs.
_start_types(::PSY.ThermalStandard) = 3
_start_types(device::PSY.ThermalMultiStart) = PSY.get_start_types(device)
