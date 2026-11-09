@testset "Existing storage unit to a storage technology" begin
    # c_sys5_bat: charges and discharges at up to 200 MW, stores 400 MWh, efficiency 0.8 in and
    # 0.9 out.
    sys = build_system(PSITestSystems, "c_sys5_bat"; skip_serialization = true)
    portfolio = new_portfolio(sys, PSY.ACBus)
    device = only(PSY.get_components(PSY.EnergyReservoirStorage, sys))
    technology = PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)

    @test technology isa PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
    @test PSIP.get_power_systems_type(technology) == "EnergyReservoirStorage"
    @test PSIP.get_region(technology) == [PSY.get_bus(device)]
    @test PSIP.get_storage_tech(technology) == PSY.get_storage_technology_type(device)
    @test !PSIP.is_new(technology)
    @test PSIP.get_existing_capacity_mw(portfolio, technology) == 200.0
    @test PSIP.get_existing_capacity_mwh(portfolio, technology) == 400.0
    @test PSIP.get_capacity_limits_charge(technology, IS.NU) == (min = 0.0, max = 200.0)
    @test PSIP.get_capacity_limits_discharge(technology, IS.NU) == (min = 0.0, max = 200.0)
    @test PSIP.get_capacity_limits_energy(technology, IS.NU) == (min = 0.0, max = 400.0)
    @test PSIP.get_efficiency(technology) == (in = 0.8, out = 0.9)
    @test PSIP.get_min_discharge_fraction(technology) == 0.0
    @test PSIP.get_losses(technology) == 0.0
    costs = PSIP.get_operation_costs(technology, IS.NU)
    @test PSY.get_charge_variable_cost(costs) isa IS.CostCurve{IS.LinearCurve}
    @test PSY.get_discharge_variable_cost(costs) isa IS.CostCurve{IS.LinearCurve}
end

@testset "Existing storage with different charge and discharge limits" begin
    # RTS-GMLC 313_STORAGE_1 charges at up to 100 MW, discharges at up to 50 MW, stores 150 MWh.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    portfolio = new_portfolio(sys, PSY.Area)
    device = PSY.get_component(PSY.EnergyReservoirStorage, sys, "313_STORAGE_1")
    technology = PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
    @test PSIP.get_capacity_limits_charge(technology, IS.NU).max == 100.0
    @test PSIP.get_capacity_limits_discharge(technology, IS.NU).max == 50.0
    @test PSIP.get_capacity_limits_energy(technology, IS.NU).max == 150.0
end

@testset "Storage operating costs" begin
    # c_sys5_bat (200 MW output) with start-up, shut-down, shortage and surplus costs set.
    sys = build_system(PSITestSystems, "c_sys5_bat"; skip_serialization = true)
    device = only(PSY.get_components(PSY.EnergyReservoirStorage, sys))
    PSY.set_operation_cost!(
        device,
        PSY.StorageCost(;
            discharge_variable_cost = IS.CostCurve(IS.LinearCurve(2.0)),
            start_up = (charge = 40.0, discharge = 20.0),
            shut_down = 10.0,
            energy_shortage_cost = 500.0,
            energy_surplus_cost = 5.0,
        ),
    )
    costs = PSC.storage_operation_costs(device)
    @test IS.get_proportional_term(
        IS.get_value_curve(PSY.get_discharge_variable_cost(costs)),
    ) ≈ 2.0
    @test PSY.get_start_up(costs) == (charge = 0.2, discharge = 0.1)
    @test PSY.get_shut_down(costs) ≈ 0.05
    @test PSY.get_energy_shortage_cost(costs) == 500.0
    @test PSY.get_energy_surplus_cost(costs) == 5.0
    @test PSY.get_fixed(costs) == 0.0
end
