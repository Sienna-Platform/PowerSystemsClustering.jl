"""
Return the region that `device` belongs to at the portfolio aggregation level `aggregation`:
its bus for `PSY.ACBus`, its bus's load zone for `PSY.LoadZone`, or its bus's area for
`PSY.Area`.

Throws `ArgumentError` if the device's bus has no load zone or area assigned.
"""
get_device_region(::Type{PSY.ACBus}, device::PSY.StaticInjection) = PSY.get_bus(device)

function get_device_region(::Type{PSY.LoadZone}, device::PSY.StaticInjection)
    region = PSY.get_load_zone(PSY.get_bus(device))
    return _check_device_region(region, PSY.LoadZone, device)
end

function get_device_region(::Type{PSY.Area}, device::PSY.StaticInjection)
    region = PSY.get_area(PSY.get_bus(device))
    return _check_device_region(region, PSY.Area, device)
end

_check_device_region(region::PSY.Topology, ::Type, ::PSY.StaticInjection) = region

function _check_device_region(
    ::Nothing,
    aggregation::Type{<:PSY.AggregationTopology},
    device::PSY.StaticInjection,
)
    bus = PSY.get_bus(device)
    throw(
        ArgumentError(
            "$(nameof(typeof(device))) $(PSY.get_name(device)) is at bus " *
            "$(PSY.get_name(bus)), which has no $(nameof(aggregation)) assigned. Assign one " *
            "to the bus or choose another aggregation level.",
        ),
    )
end
