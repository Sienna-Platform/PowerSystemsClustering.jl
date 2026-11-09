# Load types converted to `PSIP.DemandRequirement`.
const LoadDevice = Union{PSY.PowerLoad, PSY.StandardLoad}

"""
Make a `PSIP.DemandRequirement` for the existing load `device`. PSIP derives its peak demand
from the device. `financial_data` is unused.
"""
function make_technology(
    device::T,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    ::PSIP.TechnologyFinancialData,
) where {T <: LoadDevice}
    return PSIP.DemandRequirement{T}(;
        name = PSY.get_name(device),
        power_systems_type = string(nameof(T)),
        region = PSY.Topology[get_device_region(aggregation, device)],
        available = PSY.get_available(device),
        conformity = PSY.get_conformity(device),
    )
end
