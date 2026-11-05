@testset "Existing PowerLoad units to demand requirements" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.ACBus; FINANCIAL_DATA...)
    for device in PSY.get_components(PSY.PowerLoad, sys)
        technology =
            PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
        @test technology isa PSIP.DemandRequirement{PSY.PowerLoad}
        @test PSIP.get_power_systems_type(technology) == "PowerLoad"
        @test PSIP.get_region(technology) == [PSY.get_bus(device)]
        @test PSIP.get_conformity(technology) == PSY.get_conformity(device)
        @test !PSIP.is_new(technology)
        @test PSIP.get_peak_demand_mw(portfolio, technology) ==
              PSY.get_max_active_power(device, u"MW")
    end
end

@testset "Existing StandardLoad units to demand requirements" begin
    # tamu_ACTIVSg2000 has StandardLoads; check a sample at the area level.
    sys = build_system(PSYTestSystems, "tamu_ACTIVSg2000_sys"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.Area; FINANCIAL_DATA...)
    for device in first(collect(PSY.get_components(PSY.StandardLoad, sys)), 20)
        technology =
            PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
        @test technology isa PSIP.DemandRequirement{PSY.StandardLoad}
        @test PSIP.get_region(technology) == [PSY.get_area(PSY.get_bus(device))]
        @test PSIP.get_peak_demand_mw(portfolio, technology) ≈
              PSY.get_max_active_power(device, u"MW")
    end
end
