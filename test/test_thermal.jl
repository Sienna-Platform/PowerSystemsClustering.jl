@testset "Existing thermal unit to one supply technology" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    portfolio = new_portfolio(sys, PSY.ACBus)

    for device in PSY.get_components(PSY.ThermalStandard, sys)
        technology =
            PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
        name = PSY.get_name(device)

        @test technology isa PSIP.SupplyTechnology{PSY.ThermalStandard}
        @test PSIP.get_name(technology) == name
        @test PSIP.get_power_systems_type(technology) == "ThermalStandard"
        @test PSIP.get_region(technology) == [PSY.get_bus(device)]
        @test PSIP.get_available(technology) == PSY.get_available(device)
        @test PSIP.get_prime_mover_type(technology) == PSY.get_prime_mover_type(device)
        @test PSIP.get_fuel(technology) == [PSY.get_fuel(device)]
        @test PSIP.get_financial_data(technology) === TECHNOLOGY_FINANCIAL_DATA

        # Existing unit, no new builds.
        @test !PSIP.is_new(technology)
        existing = only(IS.get_supplemental_attributes(PSIP.ExistingDevices, technology))
        @test PSIP.get_existing_devices(existing) == [name]
        max_active_power = PSY.get_active_power_limits(device, u"MW").max
        @test PSIP.get_existing_capacity_mw(portfolio, technology) == max_active_power
        @test PSIP.get_capacity_limits(technology, IS.NU) ==
              (min = 0.0, max = max_active_power)
        # c_sys5_re units have no minimum output.
        @test PSIP.get_min_generation_fraction(technology) == 0.0
        # Read from the fields: PSIP's unit-aware ramp getter assumes MW/min.
        ramp_mw_per_minute = PSY.get_ramp_limits(device, u"MW/minute")
        time_limits = PSY.get_time_limits(device)
        if isnothing(ramp_mw_per_minute)
            # Alta has neither ramp nor time limits.
            @test technology.ramp_limits == (up = 1.0, down = 1.0)
            @test technology.time_limits == (up = 0.0, down = 0.0)
        else
            @test technology.ramp_limits.up ≈
                  60.0 * ramp_mw_per_minute.up / max_active_power
            @test technology.ramp_limits.down ≈
                  60.0 * ramp_mw_per_minute.down / max_active_power
            @test technology.time_limits == time_limits
        end
    end
    @test length(PSIP.get_technologies(PSIP.SupplyTechnology, portfolio)) ==
          length(PSY.get_components(PSY.ThermalStandard, sys))
end

@testset "Thermal operating costs from a cost curve" begin
    # c_sys5_re units have linear cost curves in $/MWh.
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    device = PSY.get_component(PSY.ThermalStandard, sys, "Solitude")
    source = PSY.get_operation_cost(device)
    max_mw = PSY.get_active_power_limits(device, u"MW").max

    costs = PSC.thermal_operation_costs(device, PSC.AverageRate(), :hot)
    variable = PSY.get_variable_operation_cost(costs)
    @test variable isa IS.CostCurve{IS.LinearCurve, PSY.NaturalUnit}
    # Solitude's curve is 30 $/MWh with no constant term.
    @test IS.get_proportional_term(IS.get_value_curve(variable)) ≈ 30.0
    @test IS.get_constant_term(IS.get_value_curve(variable)) == 0.0
    @test IS.get_vom_cost(variable) ==
          IS.get_vom_cost(PSY.get_variable_operation_cost(source))
    @test PSY.get_start_up(costs) ≈ PSY.get_start_up(source) / max_mw
    @test PSY.get_shut_down(costs) ≈ PSY.get_shut_down(source) / max_mw
    @test PSY.get_fixed(costs) == 0.0

    # The technology carries the converted costs.
    portfolio = new_portfolio(sys, PSY.ACBus)
    technology =
        PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
    stored = PSY.get_variable_operation_cost(PSIP.get_operation_costs(technology, IS.NU))
    @test IS.get_proportional_term(IS.get_value_curve(stored)) ≈
          IS.get_proportional_term(IS.get_value_curve(variable))
end

@testset "Thermal operating costs from a fuel curve" begin
    # RTS-GMLC units have piecewise heat rate curves with a constant fuel price.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    device = PSY.get_component(PSY.ThermalStandard, sys, "322_CT_6")
    source = PSY.get_operation_cost(device)
    source_curve = PSY.get_variable_operation_cost(source)
    limits = PSY.get_active_power_limits(device, u"MW")

    for linearization in (PSC.AverageRate(), PSC.IncrementalRate())
        costs = PSC.thermal_operation_costs(device, linearization, :hot)
        variable = PSY.get_variable_operation_cost(costs)
        @test variable isa IS.FuelCurve{IS.LinearCurve, PSY.NaturalUnit}
        @test IS.get_value_curve(variable) ==
              PSC.linearize(IS.get_value_curve(source_curve), linearization, limits)
        @test IS.get_fuel_cost(variable) == IS.get_fuel_cost(source_curve)
        @test IS.get_fuel_units(variable) == IS.get_fuel_units(source_curve)
        @test IS.get_vom_cost(variable) == IS.get_vom_cost(source_curve)
        @test IS.get_proportional_term(IS.get_startup_fuel_offtake(variable)) ≈
              IS.get_proportional_term(IS.get_startup_fuel_offtake(source_curve)) /
              limits.max
        @test PSY.get_start_up(costs) ≈ PSY.get_start_up(source) / limits.max
    end

    # RTS-GMLC units have minimum outputs: 322_CT_6 runs between 22 and 55 MW.
    portfolio_one = new_portfolio(sys, PSY.Area)
    technology =
        PSC.add_existing_technology!(portfolio_one, device, TECHNOLOGY_FINANCIAL_DATA)
    @test PSIP.get_min_generation_fraction(technology) ≈ 22.0 / 55.0
    # 3.7 MW/min over 55 MW is about 4 times its capacity per hour; 132 minutes up and down.
    @test technology.ramp_limits.up ≈ 60.0 * 3.7 / 55.0
    @test technology.time_limits == (up = 132.0, down = 132.0)

    # Every RTS-GMLC thermal unit converts, and the default keeps full-output fuel use.
    portfolio = new_portfolio(sys, PSY.Area)
    for device in PSY.get_components(PSY.ThermalStandard, sys)
        technology =
            PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
        max_mw = PSY.get_active_power_limits(device, u"MW").max
        source_curve = PSY.get_variable_operation_cost(PSY.get_operation_cost(device))
        stored =
            PSY.get_variable_operation_cost(PSIP.get_operation_costs(technology, IS.NU))
        @test IS.get_proportional_term(IS.get_value_curve(stored)) * max_mw ≈
              IS.get_function_data(IS.InputOutputCurve(IS.get_value_curve(source_curve)))(
            max_mw,
        )
    end
end

@testset "Thermal operating costs that are not supported" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    device = PSY.get_component(PSY.ThermalStandard, sys, "Solitude")

    per_unit = PSY.ThermalGenerationCost(;
        variable_operation_cost = IS.CostCurve(IS.LinearCurve(30.0), PSY.SystemBaseUnit()),
        fixed = 0.0,
        start_up = 0.0,
        shut_down = 0.0,
    )
    PSY.set_operation_cost!(device, per_unit)
    # Only curves in natural units (MW) have a conversion.
    @test_throws MethodError PSC.thermal_operation_costs(
        device,
        PSC.AverageRate(),
        :hot,
    )

    # A fixed cost while online is money, not fuel, so it cannot join a fuel curve.
    fuel_with_fixed = PSY.ThermalGenerationCost(;
        variable_operation_cost = IS.FuelCurve(
            IS.LinearCurve(10.0),
            PSIP.MMBtu,
            3.0,
        ),
        fixed = 100.0,
        start_up = 0.0,
        shut_down = 0.0,
    )
    PSY.set_operation_cost!(device, fuel_with_fixed)
    @test_throws ArgumentError PSC.thermal_operation_costs(
        device,
        PSC.AverageRate(),
        :hot,
    )

    fuel_price_series = PSY.ThermalGenerationCost(;
        variable_operation_cost = IS.FuelCurve(
            IS.LinearCurve(10.0),
            PSIP.MMBtu,
            IS.TimeSeriesKey{IS.SingleTimeSeries{Float64}}(1),
        ),
        fixed = 0.0,
        start_up = 0.0,
        shut_down = 0.0,
    )
    PSY.set_operation_cost!(device, fuel_price_series)
    # A time series fuel price cannot be carried into the linear fuel curve.
    @test_throws MethodError PSC.thermal_operation_costs(device, PSC.AverageRate(), :hot)
end

@testset "Existing ThermalMultiStart units" begin
    # c_sys5_pglib: two ThermalMultiStart units with the no-load cost in `fixed` and start-up
    # costs by stage.
    sys = build_system(PSITestSystems, "c_sys5_pglib"; skip_serialization = true)
    portfolio = new_portfolio(sys, PSY.ACBus)
    for device in PSY.get_components(PSY.ThermalMultiStart, sys)
        technology =
            PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
        limits = PSY.get_active_power_limits(device, u"MW")
        @test technology isa PSIP.SupplyTechnology{PSY.ThermalMultiStart}
        @test PSIP.get_power_systems_type(technology) == "ThermalMultiStart"
        @test PSIP.get_existing_capacity_mw(portfolio, technology) == limits.max
        @test PSIP.get_min_generation_fraction(technology) ≈ limits.min / limits.max
        @test technology.time_limits == PSY.get_time_limits(device)
    end

    # 115_STEAM_1: 5-12 MW, curve 0 to 894.1 $/h, 897.29 $/h online, starts 393.28 (hot),
    # 455.37 (warm), 703.76 (cold).
    steam = PSY.get_component(PSY.ThermalMultiStart, sys, "115_STEAM_1")
    average = PSC.thermal_operation_costs(steam, PSC.AverageRate(), :hot)
    average_curve = IS.get_value_curve(PSY.get_variable_operation_cost(average))
    # Cost at full output with the online cost included.
    @test IS.get_proportional_term(average_curve) ≈ (894.1 + 897.29) / 12.0
    @test IS.get_constant_term(average_curve) == 0.0
    @test PSY.get_fixed(average) == 0.0
    @test PSY.get_start_up(average) ≈ 393.28 / 12.0

    incremental = PSC.thermal_operation_costs(steam, PSC.IncrementalRate(), :hot)
    incremental_curve = IS.get_value_curve(PSY.get_variable_operation_cost(incremental))
    # Slope from 0 $/h at 5 MW to 894.1 $/h at 12 MW; the online cost is per MW committed.
    @test IS.get_proportional_term(incremental_curve) ≈ 894.1 / 7.0
    @test IS.get_constant_term(incremental_curve) ≈
          (897.29 - 894.1 / 7.0 * 5.0) / 12.0
    # Both give the full cost at full output: 12 MW dispatched and committed.
    @test IS.get_proportional_term(incremental_curve) * 12.0 +
          IS.get_constant_term(incremental_curve) * 12.0 ≈ 894.1 + 897.29

    @test PSY.get_start_up(
        PSC.thermal_operation_costs(steam, PSC.AverageRate(), :warm),
    ) ≈ 455.37 / 12.0
    @test PSY.get_start_up(
        PSC.thermal_operation_costs(steam, PSC.AverageRate(), :cold),
    ) ≈ 703.76 / 12.0

    # 101_CT_1 has one start type, so every stage gives its hot cost: 51.75 over 20 MW.
    turbine = PSY.get_component(PSY.ThermalMultiStart, sys, "101_CT_1")
    for stage in (:hot, :warm, :cold)
        costs = PSC.thermal_operation_costs(turbine, PSC.AverageRate(), stage)
        @test PSY.get_start_up(costs) ≈ 51.75 / 20.0
    end
    @test_throws ArgumentError PSC.thermal_operation_costs(steam, PSC.AverageRate(), :tepid)
end

@testset "Thermal start-up fuel" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    portfolio = new_portfolio(sys, PSY.ACBus)
    # Solitude (520 MW) with a fuel curve burning 52 MMBtu per start: 0.1 MMBtu per MW.
    device = PSY.get_component(PSY.ThermalStandard, sys, "Solitude")
    fuel_cost = PSY.ThermalGenerationCost(;
        variable_operation_cost = IS.FuelCurve(
            IS.LinearCurve(10.0),
            PSIP.MMBtu,
            3.0,
            IS.LinearCurve(52.0),
            IS.LinearCurve(0.0),
        ),
        fixed = 0.0,
        start_up = 0.0,
        shut_down = 0.0,
    )
    PSY.set_operation_cost!(device, fuel_cost)
    technology = PSC.add_existing_technology!(portfolio, device, TECHNOLOGY_FINANCIAL_DATA)
    @test PSIP.get_start_fuel_mmbtu_per_mw(technology, IS.NU) ≈ 0.1
    # Cost curves have no start-up fuel.
    other = PSY.get_component(PSY.ThermalStandard, sys, "Brighton")
    other_technology =
        PSC.add_existing_technology!(portfolio, other, TECHNOLOGY_FINANCIAL_DATA)
    @test PSIP.get_start_fuel_mmbtu_per_mw(other_technology, IS.NU) == 0.0
end
