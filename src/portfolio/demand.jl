# Load types converted to `PSIP.DemandRequirement`.
const LoadDevice = Union{PSY.PowerLoad, PSY.StandardLoad}

"""
Make a `PSIP.DemandRequirement` for the existing load `device`, in its region at the
aggregation level `aggregation`, keeping its conformity. PSIP derives the peak demand from the
device; the demand profile is added with the representative periods. Loads carry no financial
data, so `financial_data` is unused.
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
