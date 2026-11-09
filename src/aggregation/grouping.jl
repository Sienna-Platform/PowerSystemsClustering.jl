"""
Group `devices` by `(region, type, prime_mover, fuel, available)`, the keys units must share
to be aggregated. Parts a type lacks are `nothing`.
"""
function group_devices(
    devices,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
)
    groups = Dict{NamedTuple, Vector{PSY.StaticInjection}}()
    for device in devices
        key = (
            region = PSY.get_name(get_device_region(aggregation, device)),
            type = typeof(device),
            prime_mover = _prime_mover(device),
            fuel = _fuel(device),
            available = PSY.get_available(device),
        )
        push!(get!(groups, key, PSY.StaticInjection[]), device)
    end
    # `identity.` narrows each vector to the group's device type.
    return Dict(
        key => sort!(identity.(group); by = PSY.get_name) for (key, group) in groups
    )
end

_prime_mover(device::Union{PSY.Generator, PSY.Storage}) = PSY.get_prime_mover_type(device)
_prime_mover(::PSY.StaticInjection) = nothing

_fuel(device::ThermalDevice) = PSY.get_fuel(device)
_fuel(::PSY.StaticInjection) = nothing
