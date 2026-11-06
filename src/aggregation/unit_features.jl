"""
Features that unit aggregation clusters `device` on, as a `NamedTuple` of `Float64` (decision
15):

  - thermal: full-output average rate (heat rate for a fuel curve, cost per MWh for a cost
    curve, PowerSystems' `fixed` cost included), capacity (MW), minimum generation fraction
    and ramp-up rate (fraction of capacity per hour)
  - `HydroDispatch`: capacity (MW)
  - storage: power capacity (MW), duration (h) and round-trip efficiency
"""
function unit_features(device::ThermalDevice)
    limits = PSY.get_active_power_limits(device, u"MW")
    op_cost = PSY.get_operation_cost(device)
    linear = _linear_variable_cost(
        PSY.get_variable_operation_cost(op_cost),
        AverageRate(),
        limits,
        PSY.get_fixed(op_cost),
        device,
    )
    operating_limits = _operating_limits(device)
    return (
        average_rate = IS.get_proportional_term(IS.get_value_curve(linear)),
        capacity = limits.max,
        min_generation_fraction = operating_limits.min_generation_fraction,
        ramp_rate = operating_limits.ramp_limits.up,
    )
end

unit_features(device::PSY.HydroDispatch) =
    (capacity = PSY.get_max_active_power(device, u"MW"),)

function unit_features(device::PSY.EnergyReservoirStorage)
    power = PSY.get_output_active_power_limits(device, u"MW").max
    efficiency = PSY.get_efficiency(device)
    return (
        power_capacity = power,
        duration = PSY.get_storage_capacity(device, u"MW") / power,
        round_trip_efficiency = efficiency.in * efficiency.out,
    )
end

"""
Features of the devices in one group as a matrix with one column per device, and the names of
its rows. All devices must have the same type, as devices in one group do.

  - Renewables: the `max_active_power` profile (per unit of capacity), one row per time step,
    named by its time stamps. Throws `ArgumentError` if the profiles' time stamps differ.
  - Other devices: their [`unit_features`](@ref), named by feature.
"""
feature_matrix(devices::AbstractVector{<:PSY.StaticInjection}) =
    _feature_matrix(first(devices), devices)

function _scalar_feature_matrix(devices)
    features = unit_features.(devices)
    return reduce(hcat, collect.(values.(features))), collect(keys(first(features)))
end

function _feature_matrix(::ThermalDevice, devices)
    # The average rate is a heat rate for fuel curves and a cost for cost curves, so a group
    # mixing the two cannot be compared on it.
    curve_kinds = unique(
        nameof(typeof(PSY.get_variable_operation_cost(PSY.get_operation_cost(device))))
        for
        device in devices
    )
    if length(curve_kinds) > 1
        throw(
            ArgumentError(
                "A group mixes thermal units with $(join(curve_kinds, " and ")) costs, " *
                "whose average rates cannot be compared.",
            ),
        )
    end
    return _scalar_feature_matrix(devices)
end

_feature_matrix(::PSY.StaticInjection, devices) = _scalar_feature_matrix(devices)

function _feature_matrix(::RenewableDevice, devices)
    profiles = [
        PSY.get_time_series_array(PSY.SingleTimeSeries, device, "max_active_power") for
        device in devices
    ]
    time_stamps = TimeSeries.timestamp(first(profiles))
    if any(profile -> TimeSeries.timestamp(profile) != time_stamps, profiles)
        throw(
            ArgumentError("The renewable profiles of a group have different time stamps."),
        )
    end
    return reduce(hcat, TimeSeries.values.(profiles)), time_stamps
end
