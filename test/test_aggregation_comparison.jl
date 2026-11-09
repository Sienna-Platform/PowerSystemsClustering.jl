# Aggregated portfolios solved in PSIN against the one-to-one portfolio, on four RTS-GMLC days
# (one per season). Tolerances are set from observed results (2026-11-09).
const COMPARISON_DAYS =
    [Date(2020, 1, 15), Date(2020, 4, 15), Date(2020, 7, 15), Date(2020, 10, 15)]

const AGGREGATED_TYPES =
    (
        PSY.ThermalStandard,
        PSY.RenewableDispatch,
        PSY.HydroDispatch,
        PSY.EnergyReservoirStorage,
    )

function solve_aggregated(sys::PSY.System, n_clusters::Dict)
    portfolio, _ = build_portfolio(
        sys,
        PSY.Area;
        technology_financial_data = TECHNOLOGY_FINANCIAL_DATA,
        n_clusters = n_clusters,
        FINANCIAL_DATA...,
    )
    return solve_psin(portfolio, sys, COMPARISON_DAYS)
end

generation_by_type(model) = [
    variable_total(model, PSIN.ActivePowerVariable(), T, PSIN.BasicDispatch) for
    T in SUPPLY_TYPES
]

@testset "Aggregated dispatch compared with one to one" begin
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    per_area(k, types) = Dict((area, T) => k for area in ("1", "2", "3"), T in types)
    reference = solve_aggregated(sys, Dict())

    # Merged thermal units dispatch at a common fraction of capacity, a dispatch the one-to-one
    # model could also choose at the same cost, so the objective can only rise; it rises as
    # clusters get coarser. Observed: +0.035 %, +0.17 % and +1.09 % for k = 3, 2, 1. Generation
    # by type is unchanged: renewables and hydro run at their limits and thermal fills the rest.
    built(model, T) =
        variable_total(model, PSIN.BuildCapacity(), T, PSIN.ContinuousInvestment)
    objectives = Float64[]
    for k in (3, 2, 1)
        model = solve_aggregated(sys, per_area(k, AGGREGATED_TYPES))
        push!(objectives, objective_value(model))
        @test generation_by_type(model) ≈ generation_by_type(reference) rtol = 1e-6
        @test all(T -> isapprox(built(model, T), 0.0; atol = 1e-6), SUPPLY_TYPES)
    end
    relative_change = objectives ./ objective_value(reference) .- 1.0
    @test all(>=(-1e-9), relative_change)
    @test issorted(relative_change)
    @test all(relative_change .< [0.001, 0.005, 0.02])

    # Merged renewables reproduce their units' combined profile, so nothing changes.
    model = solve_aggregated(sys, per_area(1, (PSY.RenewableDispatch,)))
    @test objective_value(model) ≈ objective_value(reference) rtol = 1e-9
end

@testset "Aggregated storage dispatch compared with one to one" begin
    # RTS-GMLC's 50 MW / 150 MWh lossless battery and a second 100 MW / 400 MWh battery with
    # 95 % efficiency each way. Averaged efficiencies are slightly optimistic, so the merged
    # battery can lower the objective; observed -0.009 %.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    battery = PSY.get_component(PSY.EnergyReservoirStorage, sys, "313_STORAGE_1")
    add_battery!(
        sys,
        "313_STORAGE_2",
        PSY.get_bus(battery);
        charge_mw = 100.0,
        discharge_mw = 100.0,
        energy_mwh = 400.0,
        efficiency = (in = 0.95, out = 0.95),
        self_discharge = 0.0005,
    )
    reference = solve_aggregated(sys, Dict())
    model = solve_aggregated(sys, Dict(("3", PSY.EnergyReservoirStorage) => 1))
    @test objective_value(model) ≈ objective_value(reference) rtol = 0.001
end
