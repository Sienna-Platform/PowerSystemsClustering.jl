@testset "A built portfolio runs in PSIN" begin
    # RTS-GMLC, two hand-picked days re-stamped to 2030, one investment period, single region.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    portfolio = build_portfolio(
        sys,
        PSY.Area;
        technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
        FINANCIAL_DATA...,
    )
    days = [Date(2020, 1, 15), Date(2020, 7, 15)]
    add_day_series!(portfolio, sys, days, 2030)
    hours(day) = collect(DateTime(2030, month(day), Dates.day(day)) .+ Hour.(0:23))
    template = PSIN.InvestmentModelTemplate(
        PSIN.DiscountedCashFlow(0.07, Year(2025), [(Date(2030, 1, 1), Date(2030, 12, 31))]),
        PSIN.OperationalRepresentativeDays(hours.(days), [182.5, 182.5]),
        PSIN.RepresentativePeriods(Vector{Vector{DateTime}}()),
        PSIN.TransportModel(PSIN.SingleRegionBalanceModel; use_slacks = true),
    )
    supply_types = (
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIP.SupplyTechnology{PSY.HydroDispatch},
    )
    storage_type = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
    demand_type = PSIP.DemandRequirement{PSY.PowerLoad}
    # Rooftop PV (RenewableNonDispatch) is left out: PSIN `jp/capex_psy6` has no formulation
    # for it (inconsistency 10).
    for (T, investment, operation) in (
        ((T, PSIN.ContinuousInvestment, PSIN.BasicDispatch) for T in supply_types)...,
        (storage_type, PSIN.ContinuousInvestment, PSIN.CyclicalStorageDispatch),
        (demand_type, PSIN.StaticLoadInvestment, PSIN.BasicDispatch),
    )
        names = PSIP.get_name.(PSIP.get_technologies(T, portfolio))
        PSIN.set_technology_model!(
            template,
            names,
            T,
            investment,
            operation,
            PSIN.BasicDispatchFeasibility,
        )
    end
    model = PSIN.InvestmentModel(
        template,
        PSIN.SingleInstanceSolve,
        portfolio;
        optimizer = HiGHS.Optimizer,
        portfolio_to_file = false,
    )
    @test PSIN.build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IS.Optimization.ModelBuildStatus.BUILT
    @test PSIN.solve!(model) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    container = PSIN.get_optimization_container(model)
    total(variable, T, formulation) = sum(
        JuMP.value,
        PSIN.get_variable(container, variable, T, string(formulation));
        init = 0.0,
    )
    # Every technology is capped at its existing capacity, so nothing is built.
    for T in supply_types
        @test total(PSIN.BuildCapacity(), T, PSIN.ContinuousInvestment) ≈ 0.0 atol = 1e-6
    end
    @test total(PSIN.BuildPowerCapacity(), storage_type, PSIN.ContinuousInvestment) ≈ 0.0 atol =
        1e-6
    # Generation plus net storage discharge equals demand on the two days.
    generation =
        sum(total(PSIN.ActivePowerVariable(), T, PSIN.BasicDispatch) for T in supply_types)
    net_storage =
        total(PSIN.ActiveOutPowerVariable(), storage_type, PSIN.CyclicalStorageDispatch) -
        total(PSIN.ActiveInPowerVariable(), storage_type, PSIN.CyclicalStorageDispatch)
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
        t in PSIP.get_technologies(demand_type, portfolio), rep_day in 1:2
    )
    @test generation + net_storage ≈ demand rtol = 1e-6
end
