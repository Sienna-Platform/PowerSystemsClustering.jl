# Attach each renewable, HydroDispatch and PowerLoad technology's profile on the hand-picked
# `days`, re-stamped to `model_year`, as the per-day series PSIN reads (capacity factors per
# unit, demand in MW).
function add_day_series!(
    portfolio::PSIP.Portfolio,
    sys::PSY.System,
    days::Vector{Date},
    model_year::Int,
)
    for device_type in (PSY.RenewableDispatch, PSY.HydroDispatch, PSY.PowerLoad)
        for device in PSY.get_components(device_type, sys)
            technology = only(
                PSIP.get_technologies(
                    t -> PSIP.get_name(t) == PSY.get_name(device),
                    PSIP.Technology,
                    portfolio,
                ),
            )
            profile =
                PSY.get_time_series_array(PSY.SingleTimeSeries, device, "max_active_power")
            for (rep_day, day) in enumerate(days)
                start = DateTime(day)
                values = TimeSeries.values(
                    TimeSeries.to(TimeSeries.from(profile, start), start + Hour(23)),
                )
                stamps = DateTime(model_year, month(day), Dates.day(day)) .+ Hour.(0:23)
                series = PSY.SingleTimeSeries(
                    PSIN.get_default_time_series_names(typeof(technology)),
                    TimeSeries.TimeArray(
                        stamps,
                        values .* _profile_scale(technology, device),
                    ),
                )
                PSIP.add_time_series!(
                    portfolio,
                    technology,
                    series;
                    features = Dict("year" => string(model_year), "rep_day" => rep_day),
                )
            end
        end
    end
    return
end

_profile_scale(::PSIP.DemandRequirement, device::PSY.ElectricLoad) =
    PSY.get_max_active_power(device, u"MW")
_profile_scale(::PSIP.SupplyTechnology, ::PSY.Generator) = 1.0
