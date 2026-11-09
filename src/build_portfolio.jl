"""
Build a `PSIP.Portfolio` from `sys` with regions at the level `aggregation`: one technology
per device, or per cluster for thermal groups listed in `n_clusters`. Devices of unsupported
types (e.g. `HydroTurbine`) are skipped with a warning.

Returns the portfolio and its [`device_table`](@ref).

# Arguments

  - `technology_financial_data`: given to every technology
  - `linearization`: [`AverageRate`](@ref) (default) or [`IncrementalRate`](@ref)
  - `start_up_stage`: `:hot` (default), `:warm` or `:cold`
  - `n_clusters`: clusters per `(region, type)`, e.g. `Dict(("3", PSY.ThermalStandard) => 2)`,
    capped at each group's size; a `(region, type, prime_mover, fuel)` key overrides one group
  - `seed`: random seed for the clustering
  - `base_year`, `discount_rate`, `inflation_rate`, `interest_rate`: portfolio financial data
"""
function build_portfolio(
    sys::PSY.System,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}};
    technology_financial_data::PSIP.TechnologyFinancialData,
    linearization::CurveLinearization = AverageRate(),
    start_up_stage::Symbol = :hot,
    n_clusters::Dict = Dict(),
    seed::Int = 1,
    base_year::Int,
    discount_rate::Float64,
    inflation_rate::Float64,
    interest_rate::Float64,
)
    portfolio = PSIP.Portfolio(
        aggregation,
        sys,
        base_year,
        discount_rate,
        inflation_rate,
        interest_rate,
    )
    thermal_options = (; linearization, start_up_stage)
    groups = group_devices(PSY.get_components(ThermalDevice, sys), aggregation)
    for (key, devices) in groups
        clusters = _requested_clusters(n_clusters, key)
        if isnothing(clusters)
            for device in devices
                add_existing_technology!(
                    portfolio,
                    device,
                    technology_financial_data;
                    thermal_options...,
                )
            end
        else
            aggregate_group!(
                portfolio,
                key,
                devices,
                min(clusters, length(devices)),
                technology_financial_data;
                seed,
                thermal_options...,
            )
        end
    end
    for device in PSY.get_components(OtherConvertedDevice, sys)
        add_existing_technology!(portfolio, device, technology_financial_data)
    end
    _warn_skipped_devices(sys)
    return portfolio, device_table(portfolio)
end

"""
`DataFrame` of the devices each technology of `portfolio` represents (`device`, `type`,
`technology`).
"""
function device_table(portfolio::PSIP.Portfolio)
    rows = [
        (
            device = device,
            type = PSIP.get_power_systems_type(technology),
            technology = PSIP.get_name(technology),
        ) for technology in PSIP.get_technologies(PSIP.Technology, portfolio) for
        device in PSIP.get_existing_devices(
            only(IS.get_supplemental_attributes(PSIP.ExistingDevices, technology)),
        )
    ]
    return sort!(DataFrames.DataFrame(rows), [:type, :technology, :device])
end

# A group's own entry, else its `(region, type)` entry, else `nothing`.
function _requested_clusters(n_clusters::Dict, key::NamedTuple)
    entry = get(n_clusters, (key.region, key.type, key.prime_mover, key.fuel), nothing)
    if isnothing(entry)
        entry = get(n_clusters, (key.region, key.type), nothing)
    end
    return entry
end

# Converted types other than thermal.
const OtherConvertedDevice =
    Union{RenewableDevice, PSY.HydroDispatch, PSY.EnergyReservoirStorage, LoadDevice}

_is_converted(::Union{ThermalDevice, OtherConvertedDevice}) = true
_is_converted(::PSY.Device) = false

function _warn_skipped_devices(sys::PSY.System)
    skipped = PSY.get_components(
        !_is_converted,
        Union{PSY.StaticInjection, PSY.HydroReservoir},
        sys,
    )
    type_names = [string(nameof(typeof(device))) for device in skipped]
    if !isempty(type_names)
        counts = ("$(count(==(t), type_names)) $(t)" for t in sort!(unique(type_names)))
        @warn "Skipped devices of types PSC does not convert: $(join(counts, ", "))."
    end
    return
end
