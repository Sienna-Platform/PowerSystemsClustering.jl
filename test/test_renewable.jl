@testset "Existing renewable units to supply technologies" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.ACBus; FINANCIAL_DATA...)
    for device in PSY.get_components(PSY.RenewableDispatch, sys)
        technology =
            PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
        max_mw = PSY.get_max_active_power(device, u"MW")
        @test technology isa PSIP.SupplyTechnology{PSY.RenewableDispatch}
        @test PSIP.get_power_systems_type(technology) == "RenewableDispatch"
        @test PSIP.get_region(technology) == [PSY.get_bus(device)]
        @test PSIP.get_prime_mover_type(technology) == PSY.get_prime_mover_type(device)
        @test PSIP.get_capacity_limits(technology, IS.NU) == (min = 0.0, max = max_mw)
        @test PSIP.get_existing_capacity_mw(portfolio, technology) == max_mw
        @test technology.time_limits == (up = 0.0, down = 0.0)
        # c_sys5_re renewables cost 0.22 $/MWh.
        costs = PSIP.get_operation_costs(technology, IS.NU)
        curve = IS.get_value_curve(PSY.get_variable_operation_cost(costs))
        @test IS.get_proportional_term(curve) ≈ 0.22
        @test IS.get_constant_term(curve) == 0.0
        # PSIN reads curtailment costs as linear cost curves.
        @test PSY.get_curtailment_cost(costs) isa IS.CostCurve{IS.LinearCurve}
    end
end

@testset "Existing RenewableNonDispatch units" begin
    # RTS-GMLC has rooftop PV as RenewableNonDispatch, which has no operating cost.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.Area; FINANCIAL_DATA...)
    for device in PSY.get_components(PSC.RenewableDevice, sys)
        technology =
            PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
        @test PSIP.get_existing_capacity_mw(portfolio, technology) ==
              PSY.get_max_active_power(device, u"MW")
        @test PSIP.get_region(technology) == [PSY.get_area(PSY.get_bus(device))]
    end
    @test length(PSIP.get_technologies(PSIP.SupplyTechnology, portfolio)) == 61

    rooftop = PSIP.get_technology(
        PSIP.SupplyTechnology{PSY.RenewableNonDispatch},
        portfolio,
        "313_RTPV_1",
    )
    costs = PSIP.get_operation_costs(rooftop, IS.NU)
    @test IS.get_proportional_term(
        IS.get_value_curve(PSY.get_variable_operation_cost(costs)),
    ) == 0.0
end
