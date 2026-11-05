# Thermal device types converted to `PSIP.SupplyTechnology`.
const ThermalDevice = Union{PSY.ThermalStandard, PSY.ThermalMultiStart}

"""
Make a `PSIP.SupplyTechnology` for the existing thermal unit `device`, in its region at the
aggregation level `aggregation`, with its operating limits and the costs from
[`thermal_operation_costs`](@ref).
"""
function make_technology(
    device::T,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData;
    linearization::CurveLinearization = AverageRate(),
    start_up_stage::Symbol = :hot,
) where {T <: ThermalDevice}
    return PSIP.SupplyTechnology{T}(;
        _existing_generator_fields(device, aggregation, financial_data)...,
        _operating_limits(device)...,
        fuel = [PSY.get_fuel(device)],
        operation_costs = thermal_operation_costs(device, linearization, start_up_stage),
    )
end

"""
Operating costs of the thermal unit `device` as PSIN reads them:

  - the cost or fuel curve linearized over the active power limits by `linearization`
    ([`AverageRate`](@ref) for dispatch, [`IncrementalRate`](@ref) for commitment), keeping
    its fuel price and VOM;
  - PowerSystems' `fixed` cost, paid per hour online, added to a cost curve. The result's
    `fixed` is zero because PSIN reads that field as fixed O&M;
  - start-up costs by stage reduced to `start_up_stage` (`:hot`, `:warm` or `:cold`), or to
    the costliest stage the unit uses;
  - start-up and shut-down costs and start-up fuel per MW of maximum active power.

Throws `ArgumentError` for curves not in MW, time series fuel prices, and a nonzero `fixed`
cost with a fuel curve.
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

# Start-up stages a unit uses; the unused stages of a ThermalMultiStart hold placeholders.
_start_types(::PSY.ThermalStandard) = 3
_start_types(device::PSY.ThermalMultiStart) = PSY.get_start_types(device)
