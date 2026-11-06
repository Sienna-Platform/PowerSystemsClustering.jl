"""
Group `devices` by the fixed keys units must share to be aggregated (decision 15): region at
the aggregation level `aggregation` (by name), PSY type, prime mover and fuel. A key part the
device type does not have (fuel for non-thermal units, prime mover for loads) is `nothing`.

Returns a `Dict` from each key, a `NamedTuple` `(region, type, prime_mover, fuel)`, to its
devices sorted by name.
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
        )
        push!(get!(groups, key, PSY.StaticInjection[]), device)
    end
    foreach(group -> sort!(group; by = PSY.get_name), values(groups))
    return groups
end

_prime_mover(device::Union{PSY.Generator, PSY.Storage}) = PSY.get_prime_mover_type(device)
_prime_mover(::PSY.StaticInjection) = nothing

_fuel(device::ThermalDevice) = PSY.get_fuel(device)
_fuel(::PSY.StaticInjection) = nothing
