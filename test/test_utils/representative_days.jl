# Attach each renewable, HydroDispatch and PowerLoad technology's profile on the hand-picked
# `days`, re-stamped to `model_year`, as the per-day series PSIN reads: the capacity-weighted
# average of its devices' capacity factors, or their total demand in MW.
function add_day_series!(
    portfolio::PSIP.Portfolio,
    sys::PSY.System,
    days::Vector{Date},
    model_year::Int,
)
    technology_types = (
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIP.SupplyTechnology{PSY.HydroDispatch},
        PSIP.DemandRequirement{PSY.PowerLoad},
    )
    for T in technology_types, technology in PSIP.get_technologies(T, portfolio)
        existing = only(IS.get_supplemental_attributes(PSIP.ExistingDevices, technology))
        devices = [
            PSY.get_component(PSIP.get_parameter_type(T), sys, name) for
            name in PSIP.get_existing_devices(existing)
        ]
        capacities = [PSY.get_max_active_power(device, u"MW") for device in devices]
        for (rep_day, day) in enumerate(days)
            start = DateTime(day)
            profiles = [
                TimeSeries.values(
                    TimeSeries.to(
                        TimeSeries.from(
                            PSY.get_time_series_array(
                                PSY.SingleTimeSeries,
                                device,
                                "max_active_power",
                            ),
                            start,
                        ),
                        start + Hour(23),
                    ),
                ) for device in devices
            ]
            stamps = DateTime(model_year, month(day), Dates.day(day)) .+ Hour.(0:23)
            series = PSY.SingleTimeSeries(
                PSIN.get_default_time_series_names(T),
                TimeSeries.TimeArray(stamps, _combine(technology, profiles, capacities)),
            )
            PSIP.add_time_series!(
                portfolio,
                technology,
                series;
                features = Dict("year" => string(model_year), "rep_day" => rep_day),
            )
        end
    end
    return
end

_combine(::PSIP.SupplyTechnology, profiles, capacities) =
    sum(profiles .* capacities) ./ sum(capacities)
_combine(::PSIP.DemandRequirement, profiles, capacities) = sum(profiles .* capacities)
