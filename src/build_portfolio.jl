"""
Build a `PSIP.Portfolio` from the system `sys`, with one existing technology per device and
regions at the aggregation level `aggregation` (`PSY.ACBus`, `PSY.LoadZone` or `PSY.Area`).

Thermal, renewable, `HydroDispatch`, `EnergyReservoirStorage` and load devices are converted.
Devices of any other type (e.g. `HydroTurbine` and `HydroReservoir`, which PSIN does not model
yet) are skipped with one warning listing the skipped types.

# Arguments

  - `technology_financial_data::PSIP.TechnologyFinancialData`: given to every technology
  - `linearization::CurveLinearization`: how thermal cost and fuel curves are linearized,
    [`AverageRate`](@ref) (default) for dispatch formulations or [`IncrementalRate`](@ref)
    for commitment formulations
  - `start_up_stage::Symbol`: start-up cost stage used for units with costs by stage, `:hot`
    (default), `:warm` or `:cold`
  - `base_year`, `discount_rate`, `inflation_rate`, `interest_rate`: portfolio financial data
"""
function build_portfolio(
    sys::PSY.System,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}};
    technology_financial_data::PSIP.TechnologyFinancialData,
    linearization::CurveLinearization = AverageRate(),
    start_up_stage::Symbol = :hot,
    base_year::Int,
    discount_rate::Float64,
    inflation_rate::Float64,
    interest_rate::Float64,
)
    portfolio = initialize_portfolio(
        sys,
        aggregation;
        base_year,
        discount_rate,
        inflation_rate,
        interest_rate,
    )
    for device in PSY.get_components(ThermalDevice, sys)
        add_existing_technology!(
            portfolio,
            device,
            technology_financial_data;
            linearization,
            start_up_stage,
        )
    end
    for device in PSY.get_components(OtherConvertedDevice, sys)
        add_existing_technology!(portfolio, device, technology_financial_data)
    end
    _warn_skipped_devices(sys)
    return portfolio
end

# Converted device types besides thermal, which takes the build options.
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
    counts = Dict{String, Int}()
    for device in skipped
        type_name = string(nameof(typeof(device)))
        counts[type_name] = get(counts, type_name, 0) + 1
    end
    if !isempty(counts)
        listed = join(("$(n) $(t)" for (t, n) in sort!(collect(counts))), ", ")
        @warn "Skipped devices of types PSC does not convert: $(listed)."
    end
    return
end
