"""
Clustering features of `device`, as a `NamedTuple`.
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
Features of a group's `devices` as a matrix (one column per device) and the row names: hourly
profiles for renewables, [`unit_features`](@ref) otherwise.
"""
function feature_matrix(devices::AbstractVector{<:PSY.StaticInjection})
    features = unit_features.(devices)
    return reduce(hcat, collect.(values.(features))), collect(keys(first(features)))
end

function feature_matrix(devices::AbstractVector{<:RenewableDevice})
    profiles = [
        PSY.get_time_series_array(PSY.SingleTimeSeries, device, "max_active_power") for
        device in devices
    ]
    return reduce(hcat, TimeSeries.values.(profiles)), TimeSeries.timestamp(first(profiles))
end
