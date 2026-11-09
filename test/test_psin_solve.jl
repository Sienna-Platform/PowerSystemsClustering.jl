@testset "A built portfolio runs in PSIN" begin
    # RTS-GMLC, two hand-picked days re-stamped to 2030, one investment period, single region.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    portfolio, _ = build_portfolio(
        sys,
        PSY.Area;
        technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
        FINANCIAL_DATA...,
    )
    model = solve_psin(portfolio, sys, [Date(2020, 1, 15), Date(2020, 7, 15)])
    total(variable, T, formulation) = variable_total(model, variable, T, formulation)

    # Every technology is capped at its existing capacity, so nothing is built.
    for T in SUPPLY_TYPES
        @test total(PSIN.BuildCapacity(), T, PSIN.ContinuousInvestment) ≈ 0.0 atol = 1e-6
    end
    @test total(PSIN.BuildPowerCapacity(), STORAGE_TYPE, PSIN.ContinuousInvestment) ≈ 0.0 atol =
        1e-6
    # Generation plus net storage discharge equals demand on the two days.
    generation =
        sum(total(PSIN.ActivePowerVariable(), T, PSIN.BasicDispatch) for T in SUPPLY_TYPES)
    net_storage =
        total(PSIN.ActiveOutPowerVariable(), STORAGE_TYPE, PSIN.CyclicalStorageDispatch) -
        total(PSIN.ActiveInPowerVariable(), STORAGE_TYPE, PSIN.CyclicalStorageDispatch)
    demand = sum(
        sum(
            TimeSeries.values(
                PSIP.get_time_series_array(
                    PSY.SingleTimeSeries,
                    t,
                    "ops_demand";
                    features = Dict("year" => "2030", "rep_day" => rep_day),
                ),
            ),
        ) for
        t in PSIP.get_technologies(DEMAND_TYPE, portfolio), rep_day in 1:2
    )
    @test generation + net_storage ≈ demand rtol = 1e-6
end
