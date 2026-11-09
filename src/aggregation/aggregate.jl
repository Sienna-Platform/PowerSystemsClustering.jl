"""
Add one technology `name` for the cluster `devices` to `portfolio`, listing every unit in
`PSIP.ExistingDevices`. The units' fields are merged with `rules` (see [`THERMAL_RULES`](@ref)).
Returns the technology.
"""
function add_aggregated_technology!(
    portfolio::PSIP.Portfolio,
    devices::AbstractVector{<:ThermalDevice},
    name::String,
    financial_data::PSIP.TechnologyFinancialData;
    rules::NamedTuple = THERMAL_RULES,
    kwargs...,
)
    unit_fields = [
        technology_fields(device, portfolio.aggregation, financial_data; kwargs...) for
        device in devices
    ]
    capacities = [PSY.get_max_active_power(device, u"MW") for device in devices]
    fields = merge_fields(unit_fields, capacities, rules)
    technology = PSIP.SupplyTechnology{typeof(first(devices))}(; fields..., name = name)
    PSIP.add_technology!(portfolio, technology)
    existing = PSIP.ExistingDevices(; existing_devices = PSY.get_name.(devices))
    PSIP.add_supplemental_attribute!(portfolio, technology, existing)
    return technology
end

"""
Merge the units' `unit_fields` with `rules[field]`, field by field for `NamedTuple` values.
Fields without a rule take the first unit's value.
"""
function merge_fields(
    unit_fields::AbstractVector{<:NamedTuple{K}},
    capacities::AbstractVector{Float64},
    rules::NamedTuple,
) where {K}
    merged = (
        _merge_field(
            get(rules, field, nothing),
            [f[field] for f in unit_fields],
            capacities,
        )
        for field in K
    )
    return NamedTuple{K}(Tuple(merged))
end

_merge_field(rule::Function, values::AbstractVector, capacities::AbstractVector{Float64}) =
    rule(values, capacities)
_merge_field(
    rule::Function,
    values::AbstractVector{<:NamedTuple{K}},
    capacities::AbstractVector{Float64},
) where {K} =
    NamedTuple{K}(Tuple(rule([value[k] for value in values], capacities) for k in K))
_merge_field(::Nothing, values::AbstractVector, ::AbstractVector{Float64}) = first(values)

"""
Cluster the group `key`'s `devices` into at most `n_clusters` and add one technology per
cluster. Returns each unit's cluster number.
"""
function aggregate_group!(
    portfolio::PSIP.Portfolio,
    key::NamedTuple,
    devices::AbstractVector{<:ThermalDevice},
    n_clusters::Int,
    financial_data::PSIP.TechnologyFinancialData;
    seed::Int = 1,
    kwargs...,
)
    clusters = cluster_group(devices, n_clusters; seed)
    for cluster in 1:maximum(clusters)
        add_aggregated_technology!(
            portfolio,
            devices[clusters .== cluster],
            cluster_name(key, cluster),
            financial_data;
            kwargs...,
        )
    end
    return clusters
end

"""
Name of a group's cluster, e.g. `3_ThermalStandard_CT_NATURAL_GAS_2`.
"""
function cluster_name(key::NamedTuple, cluster::Int)
    parts = (key.region, nameof(key.type), key.prime_mover, key.fuel)
    return join(string.(filter(!isnothing, parts)), "_") * "_$(cluster)"
end
