@testset "Existing HydroDispatch unit from a cost curve" begin
    # c_sys5_hy: one 600 MW unit with a zero linear cost curve and no ramp or time limits.
    sys = build_system(PSITestSystems, "c_sys5_hy"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.ACBus; FINANCIAL_DATA...)
    device = only(PSY.get_components(PSY.HydroDispatch, sys))
    technology = PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)

    @test technology isa PSIP.SupplyTechnology{PSY.HydroDispatch}
    @test PSIP.get_power_systems_type(technology) == "HydroDispatch"
    @test PSIP.get_region(technology) == [PSY.get_bus(device)]
    @test PSIP.get_existing_capacity_mw(portfolio, technology) == 600.0
    @test PSIP.get_capacity_limits(technology, IS.NU) == (min = 0.0, max = 600.0)
    @test technology.ramp_limits == (up = 1.0, down = 1.0)
    @test technology.time_limits == (up = 0.0, down = 0.0)
    costs = PSIP.get_operation_costs(technology, IS.NU)
    @test costs isa PSY.HydroGenerationCost
    @test IS.get_proportional_term(
        IS.get_value_curve(PSY.get_variable_operation_cost(costs)),
    ) == 0.0
end

@testset "Existing HydroDispatch unit from a fuel curve" begin
    # RTS-GMLC 201_HYDRO_4: 0-50 MW, ramps 50 MW/min, fuel curve of 3.412 MMBtu/MWh at a zero
    # fuel price.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.Area; FINANCIAL_DATA...)
    device = PSY.get_component(PSY.HydroDispatch, sys, "201_HYDRO_4")
    technology = PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)

    @test PSIP.get_existing_capacity_mw(portfolio, technology) == 50.0
    @test technology.ramp_limits == (up = 60.0, down = 60.0)
    # Priced into a cost curve: 3.412 MMBtu/MWh at 0 $/MMBtu.
    variable = PSY.get_variable_operation_cost(PSIP.get_operation_costs(technology, IS.NU))
    @test variable isa IS.CostCurve{IS.LinearCurve}
    @test IS.get_proportional_term(IS.get_value_curve(variable)) == 0.0
end

@testset "HydroTurbine and HydroReservoir are skipped" begin
    sys =
        build_system(PSITestSystems, "c_sys5_hy_turbine_energy"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.ACBus; FINANCIAL_DATA...)
    for device in PSY.get_components(Union{PSY.HydroTurbine, PSY.HydroReservoir}, sys)
        @test_logs (:warn, r"Skipping") PSC.add_existing_technology!(
            portfolio,
            device,
            TECHNOLOGY_FINANCIAL_DATA,
        )
    end
    @test isempty(PSIP.get_technologies(PSIP.Technology, portfolio))
end
