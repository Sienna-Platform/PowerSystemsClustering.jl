# Add a battery named `name` at `bus`. PSCB systems have at most one battery, so tests that
# aggregate storage add more.
function add_battery!(
    sys::PSY.System,
    name::String,
    bus::PSY.ACBus;
    charge_mw::Float64,
    discharge_mw::Float64,
    energy_mwh::Float64,
    efficiency::NamedTuple{(:in, :out), Tuple{Float64, Float64}},
    self_discharge::Float64 = 0.0,
    operation_cost::PSY.StorageCost = PSY.StorageCost(),
)
    battery = PSY.EnergyReservoirStorage(;
        name = name,
        available = true,
        bus = bus,
        prime_mover_type = PSY.PrimeMovers.BA,
        storage_technology_type = PSY.StorageTech.OTHER_CHEM,
        storage_capacity = energy_mwh,
        storage_level_limits = (min = 0.0, max = 1.0),
        initial_storage_capacity_level = 0.5,
        rating = max(charge_mw, discharge_mw),
        active_power = 0.0,
        input_active_power_limits = (min = 0.0, max = charge_mw),
        output_active_power_limits = (min = 0.0, max = discharge_mw),
        efficiency = efficiency,
        reactive_power = 0.0,
        reactive_power_limits = nothing,
        base_power = 100.0,
        operation_cost = operation_cost,
        self_discharge = self_discharge,
        input_basis = u"NU",
    )
    PSY.add_component!(sys, battery)
    return battery
end
