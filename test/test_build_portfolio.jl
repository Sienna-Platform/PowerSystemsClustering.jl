@testset "Build a portfolio from a small system" begin
    # c_sys5_re: 5 thermal units, 3 wind units and 3 loads, all converted.
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    logs, (portfolio, devices) = Test.collect_test_logs() do
        build_portfolio(
            sys,
            PSY.ACBus;
            technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
            FINANCIAL_DATA...,
        )
    end
    # Nothing skipped (PSIP's own validation warnings aside).
    @test !any(log -> occursin("Skipped", string(log.message)), logs)
    count(T) = length(PSIP.get_technologies(T, portfolio))
    @test count(PSIP.SupplyTechnology{PSY.ThermalStandard}) == 5
    @test count(PSIP.SupplyTechnology{PSY.RenewableDispatch}) == 3
    @test count(PSIP.DemandRequirement{PSY.PowerLoad}) == 3
    @test all(!PSIP.is_new, PSIP.get_technologies(PSIP.Technology, portfolio))
    # One row per converted device, each its own technology.
    @test DataFrames.nrow(devices) == 11
    @test devices.technology == devices.device
end

@testset "Build a portfolio at a level the system lacks" begin
    # c_sys5_re has no areas: the first device has no region at that level.
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    @test_throws ArgumentError build_portfolio(
        sys,
        PSY.Area;
        technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
        FINANCIAL_DATA...,
    )
end

@testset "Build a portfolio with build options" begin
    # 115_STEAM_1: cold start-up 703.76 over 12 MW, nonzero incremental no-load cost.
    sys = build_system(PSITestSystems, "c_sys5_pglib"; skip_serialization = true)
    portfolio, _ = build_portfolio(
        sys,
        PSY.ACBus;
        technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
        linearization = IncrementalRate(),
        start_up_stage = :cold,
        FINANCIAL_DATA...,
    )
    steam = PSIP.get_technology(
        PSIP.SupplyTechnology{PSY.ThermalMultiStart},
        portfolio,
        "115_STEAM_1",
    )
    costs = PSIP.get_operation_costs(steam, IS.NU)
    @test PSY.get_start_up(costs) ≈ 703.76 / 12.0
    @test IS.get_constant_term(IS.get_value_curve(PSY.get_variable_operation_cost(costs))) >
          0.0
end

@testset "Build a portfolio skipping unconverted devices" begin
    # RTS-GMLC: 187 devices converted, 19 HydroTurbine and 19 HydroReservoir skipped.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    portfolio, _ =
        @test_logs (:warn, r"19 HydroReservoir, 19 HydroTurbine") match_mode = :any build_portfolio(
            sys,
            PSY.Area;
            technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
            FINANCIAL_DATA...,
        )
    @test length(PSIP.get_technologies(PSIP.Technology, portfolio)) == 187
    @test isempty(PSIP.get_technologies(PSIP.SupplyTechnology{PSY.HydroTurbine}, portfolio))
end

@testset "Build a portfolio with aggregated thermal units" begin
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    build(n_clusters) = build_portfolio(
        sys,
        PSY.Area;
        technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
        n_clusters = n_clusters,
        FINANCIAL_DATA...,
    )
    reference, _ = build(Dict())
    thermal(p) = PSIP.get_technologies(PSIP.SupplyTechnology{PSY.ThermalStandard}, p)
    capacity(p) = sum(PSIP.get_existing_capacity_mw(p, t) for t in thermal(p))

    # Area 3's 26 units in 5 groups become 7 technologies: 2 each for gas CC and gas CT, 1 for
    # the single coal unit and 1 each for the identical oil CT and oil ST units.
    portfolio, devices = build(Dict(("3", PSY.ThermalStandard) => 2))
    @test length(thermal(portfolio)) == 73 - 26 + 7
    @test capacity(portfolio) ≈ capacity(reference)
    @test DataFrames.nrow(devices) == 187
    area_3 = filter(row -> startswith(row.technology, "3_ThermalStandard"), devices)
    @test DataFrames.nrow(area_3) == 26
    @test length(unique(area_3.technology)) == 7
    @test "3_ThermalStandard_ST_COAL_1" in area_3.technology

    # A group key overrides its region and type: 3 clusters for area 3's gas CTs.
    gas_ct = ("3", PSY.ThermalStandard, PSY.PrimeMovers.CT, PSY.ThermalFuels.NATURAL_GAS)
    portfolio, _ = build(Dict(("3", PSY.ThermalStandard) => 2, gas_ct => 3))
    @test length(thermal(portfolio)) == 73 - 26 + 8

    # Renewables aggregate the same way; total capacity is unchanged.
    renewable(p) = PSIP.get_technologies(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p)
    renewable_capacity(p) = sum(PSIP.get_existing_capacity_mw(p, t) for t in renewable(p))
    portfolio, _ =
        build(Dict((area, PSY.RenewableDispatch) => 1 for area in ("1", "2", "3")))
    @test length(renewable(portfolio)) < length(renewable(reference))
    @test renewable_capacity(portfolio) ≈ renewable_capacity(reference)
end
