# Load types converted to `PSIP.DemandRequirement`.
const LoadDevice = Union{PSY.PowerLoad, PSY.StandardLoad}

# PSIP derives the peak demand from the device; loads carry no financial data.
function technology_fields(
    device::T,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    ::PSIP.TechnologyFinancialData;
    kwargs...,
) where {T <: LoadDevice}
    return (;
        name = PSY.get_name(device),
        power_systems_type = string(nameof(T)),
        region = PSY.Topology[get_device_region(aggregation, device)],
        available = PSY.get_available(device),
        conformity = PSY.get_conformity(device),
    )
end
