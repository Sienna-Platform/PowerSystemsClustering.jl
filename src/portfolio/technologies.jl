"""
Add the technology [`make_technology`](@ref) makes for `device` to `portfolio`, with a
`PSIP.ExistingDevices` attribute naming the device. Returns the technology.
"""
function add_existing_technology!(
    portfolio::PSIP.Portfolio,
    device::PSY.Device,
    financial_data::PSIP.TechnologyFinancialData;
    kwargs...,
)
    technology = make_technology(device, portfolio.aggregation, financial_data; kwargs...)
    PSIP.add_technology!(portfolio, technology)
    existing = PSIP.ExistingDevices(; existing_devices = [PSY.get_name(device)])
    PSIP.add_supplemental_attribute!(portfolio, technology, existing)
    return technology
end

# Fields every technology shares.
function _existing_device_fields(
    device::T,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData,
) where {T <: PSY.StaticInjection}
    return (
        name = PSY.get_name(device),
        power_systems_type = string(nameof(T)),
        region = PSY.Topology[get_device_region(aggregation, device)],
        available = PSY.get_available(device),
        prime_mover_type = PSY.get_prime_mover_type(device),
        financial_data = financial_data,
    )
end

# Shared fields plus a capacity of the device's maximum active power (no new builds).
_existing_generator_fields(
    device::PSY.Generator,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}},
    financial_data::PSIP.TechnologyFinancialData,
) = (
    _existing_device_fields(device, aggregation, financial_data)...,
    capacity_limits = (min = 0.0, max = PSY.get_max_active_power(device, u"MW")),
)

# Minimum generation and ramp limits as fractions of capacity (ramps per hour), and minimum up
# and down times in minutes.
function _operating_limits(device::PSY.Generator)
    limits = PSY.get_active_power_limits(device, u"MW")
    return (
        min_generation_fraction = limits.min / limits.max,
        ramp_limits = _ramp_fraction_per_hour(
            PSY.get_ramp_limits(device, u"MW/minute"),
            limits.max,
        ),
        time_limits = _time_limits(PSY.get_time_limits(device)),
    )
end

_ramp_fraction_per_hour(ramp::PSY.UpDown, max_mw::Float64) =
    (up = 60.0 * ramp.up / max_mw, down = 60.0 * ramp.down / max_mw)
_ramp_fraction_per_hour(::Nothing, ::Float64) = (up = 1.0, down = 1.0)

_time_limits(time_limits::PSY.UpDown) = time_limits
_time_limits(::Nothing) = (up = 0.0, down = 0.0)
