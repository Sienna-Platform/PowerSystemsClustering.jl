"""
Region of `device` at the level `aggregation`: its bus, or its bus's load zone or area.
"""
get_device_region(::Type{PSY.ACBus}, device::PSY.StaticInjection) = PSY.get_bus(device)

function get_device_region(
    aggregation::Type{<:PSY.AggregationTopology},
    device::PSY.StaticInjection,
)
    bus = PSY.get_bus(device)
    region = _bus_region(aggregation, bus)
    if isnothing(region)
        throw(
            ArgumentError(
                "$(PSY.get_name(device)) is at bus $(PSY.get_name(bus)), which has no " *
                "$(nameof(aggregation)).",
            ),
        )
    end
    return region
end

_bus_region(::Type{PSY.LoadZone}, bus::PSY.ACBus) = PSY.get_load_zone(bus)
_bus_region(::Type{PSY.Area}, bus::PSY.ACBus) = PSY.get_area(bus)
