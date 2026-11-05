@testset "Build a portfolio from a small system" begin
    # c_sys5_re: 5 thermal units, 3 wind units and 3 loads, all converted.
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    logs, portfolio = Test.collect_test_logs() do
        build_portfolio(
            sys,
            PSY.ACBus;
            technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
            FINANCIAL_DATA...,
        )
    end
    # Nothing skipped. (PSIP itself warns that its validation file lacks technology structs.)
    @test !any(log -> occursin("Skipped", string(log.message)), logs)
    count(T) = length(PSIP.get_technologies(T, portfolio))
    @test count(PSIP.SupplyTechnology{PSY.ThermalStandard}) == 5
    @test count(PSIP.SupplyTechnology{PSY.RenewableDispatch}) == 3
    @test count(PSIP.DemandRequirement{PSY.PowerLoad}) == 3
    @test all(!PSIP.is_new, PSIP.get_technologies(PSIP.Technology, portfolio))
end

@testset "Build a portfolio with build options" begin
    # The thermal options reach the converter: c_sys5_pglib's 115_STEAM_1 has a cold start-up
    # cost of 703.76 over 12 MW and a nonzero incremental no-load cost.
    sys = build_system(PSITestSystems, "c_sys5_pglib"; skip_serialization = true)
    portfolio = build_portfolio(
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
    # RTS-GMLC: 73 thermal, 61 renewable, 1 HydroDispatch, 1 storage and 51 loads converted; its
    # 19 HydroTurbine and 19 HydroReservoir devices are skipped with one warning.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    portfolio =
        @test_logs (:warn, r"19 HydroReservoir, 19 HydroTurbine") match_mode = :any build_portfolio(
            sys,
            PSY.Area;
            technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
            FINANCIAL_DATA...,
        )
    @test length(PSIP.get_technologies(PSIP.Technology, portfolio)) == 187
    @test isempty(PSIP.get_technologies(PSIP.SupplyTechnology{PSY.HydroTurbine}, portfolio))
end
