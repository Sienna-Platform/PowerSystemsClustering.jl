"""
Add a technology for the existing `device` to `portfolio`, with a `PSIP.ExistingDevices`
attribute naming the device so PSIP counts its capacity as existing. The technology comes
from the [`make_technology`](@ref) method for the device's type, which receives the keyword
arguments. Returns the technology.
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
