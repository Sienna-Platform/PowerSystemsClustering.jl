# Thermal device types converted to `PSIP.SupplyTechnology`.
const ThermalDevice = Union{PSY.ThermalStandard, PSY.ThermalMultiStart}

"""
Make a `PSIP.SupplyTechnology` for the thermal unit `device`, in its region at the aggregation
level `aggregation`.

Capacity is the device's maximum active power, so the technology is the existing unit with no
new builds. Minimum generation is a fraction of that capacity, ramp limits are fractions of it
per hour (`(1.0, 1.0)` if the device has none), and minimum up and down times are in minutes
(`(0.0, 0.0)` if none). Costs come from [`thermal_operation_costs`](@ref).
"""
function make_technology(
    device::T,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData;
    linearization::CurveLinearization = AverageRate(),
    start_up_stage::Symbol = :hot,
) where {T <: ThermalDevice}
    limits = PSY.get_active_power_limits(device, u"MW")
    return PSIP.SupplyTechnology{T}(;
        name = PSY.get_name(device),
        power_systems_type = string(nameof(T)),
        region = PSY.Topology[get_device_region(aggregation, device)],
        available = PSY.get_available(device),
        prime_mover_type = PSY.get_prime_mover_type(device),
        fuel = [PSY.get_fuel(device)],
        operation_costs = thermal_operation_costs(device, linearization, start_up_stage),
        capacity_limits = (min = 0.0, max = limits.max),
        min_generation_fraction = limits.min / limits.max,
        ramp_limits = _ramp_fraction_per_hour(
            PSY.get_ramp_limits(device, u"MW/minute"),
            limits.max,
        ),
        time_limits = _time_limits(PSY.get_time_limits(device)),
        financial_data = financial_data,
    )
end

_ramp_fraction_per_hour(ramp::PSY.UpDown, max_mw::Float64) =
    (up = 60.0 * ramp.up / max_mw, down = 60.0 * ramp.down / max_mw)
_ramp_fraction_per_hour(::Nothing, ::Float64) = (up = 1.0, down = 1.0)

_time_limits(time_limits::PSY.UpDown) = time_limits
_time_limits(::Nothing) = (up = 0.0, down = 0.0)

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

function _linear_variable_cost(
    curve::IS.CostCurve{<:IS.ValueCurve, PSY.NaturalUnit},
    linearization::CurveLinearization,
    limits::PSY.MinMax,
    fixed::Float64,
    ::ThermalDevice,
)
    linear =
        linearize(IS.get_value_curve(curve), linearization, limits; online_cost = fixed)
    return IS.CostCurve(linear, PSY.NaturalUnit(), IS.get_vom_cost(curve))
end

function _linear_variable_cost(
    curve::IS.FuelCurve{<:IS.ValueCurve, PSY.NaturalUnit},
    linearization::CurveLinearization,
    limits::PSY.MinMax,
    fixed::Float64,
    device::ThermalDevice,
)
    name = PSY.get_name(device)
    if !iszero(fixed)
        throw(ArgumentError("$(name): a fixed cost cannot be added to a fuel curve."))
    end
    fuel_price = IS.get_fuel_cost(curve)
    if isnothing(fuel_price)
        throw(ArgumentError("$(name): time series fuel prices are not supported."))
    end
    start_up_fuel = IS.get_proportional_term(IS.get_startup_fuel_offtake(curve))
    return IS.FuelCurve(
        linearize(IS.get_value_curve(curve), linearization, limits),
        PSY.NaturalUnit(),
        IS.get_fuel_units(curve),
        fuel_price,
        IS.LinearCurve(start_up_fuel / limits.max),
        IS.get_vom_cost(curve),
    )
end

function _linear_variable_cost(
    ::IS.ProductionVariableCostCurve,
    ::CurveLinearization,
    ::PSY.MinMax,
    ::Float64,
    device::ThermalDevice,
)
    throw(
        ArgumentError(
            "$(PSY.get_name(device)): only cost and fuel curves in natural units (MW) are " *
            "supported.",
        ),
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
