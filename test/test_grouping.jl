@testset "Group devices by region, type, prime mover and fuel" begin
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    thermal = collect(PSY.get_components(PSC.ThermalDevice, sys))
    groups = PSC.group_devices(thermal, PSY.Area)

    # RTS-GMLC's 73 thermal units fall into 15 groups across its 3 areas.
    @test length(groups) == 15
    @test sum(length, values(groups)) == length(thermal)
    area_1_gas_cc = (
        region = "1",
        type = PSY.ThermalStandard,
        prime_mover = PSY.PrimeMovers.CC,
        fuel = PSY.ThermalFuels.NATURAL_GAS,
        available = true,
    )
    @test PSY.get_name.(groups[area_1_gas_cc]) == ["107_CC_1", "118_CC_1"]

    # Every unit in a group shares the key.
    for (key, devices) in groups, device in devices
        @test PSY.get_name(PSY.get_area(PSY.get_bus(device))) == key.region
        @test typeof(device) == key.type
        @test PSY.get_prime_mover_type(device) == key.prime_mover
        @test PSY.get_fuel(device) == key.fuel
    end
end

@testset "Group devices without a fuel or prime mover" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    # Wind units have no fuel: one group per bus.
    wind_groups =
        PSC.group_devices(PSY.get_components(PSY.RenewableDispatch, sys), PSY.ACBus)
    @test all(key -> isnothing(key.fuel), keys(wind_groups))
    @test all(key -> key.prime_mover == PSY.PrimeMovers.WT, keys(wind_groups))
    # Loads have neither.
    load_groups = PSC.group_devices(PSY.get_components(PSY.PowerLoad, sys), PSY.ACBus)
    @test all(key -> isnothing(key.prime_mover) && isnothing(key.fuel), keys(load_groups))
    @test sum(length, values(load_groups)) == 3
end
