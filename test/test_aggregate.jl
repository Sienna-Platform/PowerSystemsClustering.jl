_variable(t) = PSY.get_variable_operation_cost(PSIP.get_operation_costs(t, IS.NU))
_slope(t) = IS.get_proportional_term(IS.get_value_curve(_variable(t)))

@testset "Merge technology fields" begin
    unit_fields = [
        (
            name = "a",
            capacity_limits = (min = 0.0, max = 100.0),
            time_limits = (up = 60.0, down = 0.0),
        ),
        (
            name = "b",
            capacity_limits = (min = 0.0, max = 300.0),
            time_limits = (up = 240.0, down = 30.0),
        ),
    ]
    rules = (capacity_limits = PSC.total, time_limits = PSC.largest)
    merged = PSC.merge_fields(unit_fields, [100.0, 300.0], rules)
    # Fields without a rule come from the first unit.
    @test merged == (
        name = "a",
        capacity_limits = (min = 0.0, max = 400.0),
        time_limits = (up = 240.0, down = 30.0),
    )
end

@testset "Aggregate a cluster of thermal units" begin
    # RTS-GMLC area 3 gas CTs: k-means with 2 clusters puts the five efficient 55 MW units
    # (315_CT_6/7/8, 322_CT_5/6) together.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.ThermalDevice, sys), PSY.Area)
    group = groups[(
        region = "3",
        type = PSY.ThermalStandard,
        prime_mover = PSY.PrimeMovers.CT,
        fuel = PSY.ThermalFuels.NATURAL_GAS,
        available = true,
    )]
    cluster = group[PSC.cluster_group(group, 2) .== 2]
    @test PSY.get_name.(cluster) ==
          ["315_CT_6", "315_CT_7", "315_CT_8", "322_CT_5", "322_CT_6"]

    portfolio = new_portfolio(sys, PSY.Area)
    technology = PSC.add_aggregated_technology!(
        portfolio,
        cluster,
        "3_CT_NATURAL_GAS_2",
        TECHNOLOGY_FINANCIAL_DATA,
    )
    @test PSIP.get_name(technology) == "3_CT_NATURAL_GAS_2"
    @test PSIP.get_region(technology) == [PSY.get_area(PSY.get_bus(first(cluster)))]
    existing = only(IS.get_supplemental_attributes(PSIP.ExistingDevices, technology))
    @test PSIP.get_existing_devices(existing) == PSY.get_name.(cluster)
    # Capacity is the units' total, and PSIP's existing capacity agrees.
    @test PSIP.get_capacity_limits(technology, IS.NU) == (min = 0.0, max = 275.0)
    @test PSIP.get_existing_capacity_mw(portfolio, technology) == 275.0

    # Compare with the units converted one to one.
    units = [
        PSC.make_technology(device, PSY.Area, TECHNOLOGY_FINANCIAL_DATA) for
        device in cluster
    ]
    # Fuel at full output is exact: 275 MW at the merged heat rate equals the units' total.
    @test _slope(technology) * 275.0 ≈ sum(_slope(unit) * 55.0 for unit in units)
    @test IS.get_fuel_cost(_variable(technology)) ≈
          IS.get_fuel_cost(_variable(first(units)))
    @test PSIP.get_min_generation_fraction(technology) ≈ 0.4
    @test technology.time_limits == (
        up = maximum(unit.time_limits.up for unit in units),
        down = maximum(unit.time_limits.down for unit in units),
    )
end

@testset "Aggregate thermal units of different sizes" begin
    # RTS-GMLC area 1 coal steam units range from 76 to 350 MW.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.ThermalDevice, sys), PSY.Area)
    group = groups[(
        region = "1",
        type = PSY.ThermalStandard,
        prime_mover = PSY.PrimeMovers.ST,
        fuel = PSY.ThermalFuels.COAL,
        available = true,
    )]
    capacities = [PSY.get_max_active_power(device, u"MW") for device in group]
    portfolio = new_portfolio(sys, PSY.Area)
    technology =
        PSC.add_aggregated_technology!(
            portfolio,
            group,
            "1_ST_COAL",
            TECHNOLOGY_FINANCIAL_DATA,
        )
    units = [
        PSC.make_technology(device, PSY.Area, TECHNOLOGY_FINANCIAL_DATA) for
        device in group
    ]

    @test PSIP.get_existing_capacity_mw(portfolio, technology) ≈ sum(capacities)
    # Totals over the cluster are kept: fuel at full output, minimum output, start-up costs.
    @test _slope(technology) * sum(capacities) ≈ sum(_slope.(units) .* capacities)
    @test PSIP.get_min_generation_fraction(technology) * sum(capacities) ≈
          sum(PSIP.get_min_generation_fraction.(units) .* capacities)
    start_up(t) = PSY.get_start_up(PSIP.get_operation_costs(t, IS.NU))
    @test start_up(technology) * sum(capacities) ≈ sum(start_up.(units) .* capacities)

    # A rule can be replaced: capacity-weighted instead of the largest minimum up time.
    portfolio = new_portfolio(sys, PSY.Area)
    weighted = PSC.add_aggregated_technology!(
        portfolio,
        group,
        "1_ST_COAL",
        TECHNOLOGY_FINANCIAL_DATA;
        rules = merge(PSC.THERMAL_RULES, (time_limits = PSC.capacity_weighted,)),
    )
    @test weighted.time_limits.up ≈
          PSC.capacity_weighted([unit.time_limits.up for unit in units], capacities)
    @test weighted.time_limits.up < technology.time_limits.up
end

@testset "Name clusters" begin
    thermal = (
        region = "3",
        type = PSY.ThermalStandard,
        prime_mover = PSY.PrimeMovers.CT,
        fuel = PSY.ThermalFuels.NATURAL_GAS,
        available = true,
    )
    @test PSC.cluster_name(thermal, 2) == "3_ThermalStandard_CT_NATURAL_GAS_2"
    # Parts a group does not have are skipped.
    wind = (
        region = "1",
        type = PSY.RenewableDispatch,
        prime_mover = PSY.PrimeMovers.WT,
        fuel = nothing,
        available = true,
    )
    @test PSC.cluster_name(wind, 1) == "1_RenewableDispatch_WT_1"
end

@testset "Aggregate a group into clusters" begin
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.ThermalDevice, sys), PSY.Area)
    key = (
        region = "3",
        type = PSY.ThermalStandard,
        prime_mover = PSY.PrimeMovers.CT,
        fuel = PSY.ThermalFuels.NATURAL_GAS,
        available = true,
    )
    portfolio = new_portfolio(sys, PSY.Area)
    clusters =
        PSC.aggregate_group!(portfolio, key, groups[key], 2, TECHNOLOGY_FINANCIAL_DATA)
    @test clusters == [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2]

    # Two technologies named by cluster, listing their units and covering all 605 MW.
    table = PSC.device_table(portfolio)
    @test table.device == PSY.get_name.(groups[key])
    @test table.technology == PSC.cluster_name.(Ref(key), clusters)
    technologies =
        PSIP.get_technologies(PSIP.SupplyTechnology{PSY.ThermalStandard}, portfolio)
    @test sum(PSIP.get_existing_capacity_mw(portfolio, t) for t in technologies) == 605.0
end

@testset "Aggregate identical units" begin
    # RTS-GMLC area 3's 4 oil CTs are identical: asking for 2 clusters gives 1 technology.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.ThermalDevice, sys), PSY.Area)
    key = (
        region = "3",
        type = PSY.ThermalStandard,
        prime_mover = PSY.PrimeMovers.CT,
        fuel = PSY.ThermalFuels.DISTILLATE_FUEL_OIL,
        available = true,
    )
    portfolio = new_portfolio(sys, PSY.Area)
    @test PSC.aggregate_group!(portfolio, key, groups[key], 2, TECHNOLOGY_FINANCIAL_DATA) ==
          [1, 1, 1, 1]
    @test length(PSIP.get_technologies(PSIP.SupplyTechnology, portfolio)) == 1
end

@testset "Aggregate renewable units" begin
    # The largest RTS-GMLC renewable group, clustered on hourly profiles into 3 technologies.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.RenewableDevice, sys), PSY.Area)
    key, devices = argmax(kv -> length(kv[2]), collect(groups))
    portfolio = new_portfolio(sys, PSY.Area)
    clusters = PSC.aggregate_group!(portfolio, key, devices, 3, TECHNOLOGY_FINANCIAL_DATA)
    technologies = collect(PSIP.get_technologies(PSIP.SupplyTechnology, portfolio))
    @test length(technologies) == maximum(clusters)
    for technology in technologies
        existing = only(IS.get_supplemental_attributes(PSIP.ExistingDevices, technology))
        names = PSIP.get_existing_devices(existing)
        capacities = [
            PSY.get_max_active_power(PSY.get_component(key.type, sys, name), u"MW") for
            name in names
        ]
        @test PSIP.get_capacity_limits(technology, IS.NU).max ≈ sum(capacities)
        @test PSIP.get_existing_capacity_mw(portfolio, technology) ≈ sum(capacities)
        @test technology.time_limits == (up = 0.0, down = 0.0)
        costs = PSIP.get_operation_costs(technology, IS.NU)
        @test PSY.get_curtailment_cost(costs) isa IS.CostCurve{IS.LinearCurve}
    end
end

@testset "Aggregate hydro units" begin
    # c_sys5_hy's single 600 MW HydroDispatch unit, aggregated as a group of one.
    sys = build_system(PSITestSystems, "c_sys5_hy"; skip_serialization = true)
    devices = collect(PSY.get_components(PSY.HydroDispatch, sys))
    portfolio = new_portfolio(sys, PSY.ACBus)
    technology =
        PSC.add_aggregated_technology!(
            portfolio,
            devices,
            "hydro",
            TECHNOLOGY_FINANCIAL_DATA,
        )
    @test technology isa PSIP.SupplyTechnology{PSY.HydroDispatch}
    @test PSIP.get_existing_capacity_mw(portfolio, technology) == 600.0
    @test PSIP.get_operation_costs(technology, IS.NU) isa PSY.HydroGenerationCost
end
