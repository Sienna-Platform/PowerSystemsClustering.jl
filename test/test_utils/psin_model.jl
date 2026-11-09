const SUPPLY_TYPES = (
    PSIP.SupplyTechnology{PSY.ThermalStandard},
    PSIP.SupplyTechnology{PSY.RenewableDispatch},
    PSIP.SupplyTechnology{PSY.HydroDispatch},
)
const STORAGE_TYPE = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
const DEMAND_TYPE = PSIP.DemandRequirement{PSY.PowerLoad}

# Build and solve a single-region PSIN model of `portfolio` over the hand-picked `days` of
# `sys`, re-stamped to 2030 and weighted equally over one investment period. Returns the model.
function solve_psin(portfolio::PSIP.Portfolio, sys::PSY.System, days::Vector{Date})
    add_day_series!(portfolio, sys, days, 2030)
    hours(day) = collect(DateTime(2030, month(day), Dates.day(day)) .+ Hour.(0:23))
    template = PSIN.InvestmentModelTemplate(
        PSIN.DiscountedCashFlow(0.07, Year(2025), [(Date(2030, 1, 1), Date(2030, 12, 31))]),
        PSIN.OperationalRepresentativeDays(
            hours.(days),
            fill(365 / length(days), length(days)),
        ),
        PSIN.RepresentativePeriods(Vector{Vector{DateTime}}()),
        PSIN.TransportModel(PSIN.SingleRegionBalanceModel; use_slacks = true),
    )
    # Rooftop PV (RenewableNonDispatch) is left out: this PSIN has no formulation for it.
    for (T, investment, operation) in (
        ((T, PSIN.ContinuousInvestment, PSIN.BasicDispatch) for T in SUPPLY_TYPES)...,
        (STORAGE_TYPE, PSIN.ContinuousInvestment, PSIN.CyclicalStorageDispatch),
        (DEMAND_TYPE, PSIN.StaticLoadInvestment, PSIN.BasicDispatch),
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
    return model
end

# Sum of a solved `variable` over every technology of type `T` and every time step.
function variable_total(model, variable, T, formulation)
    container = PSIN.get_optimization_container(model)
    return sum(
        JuMP.value,
        PSIN.get_variable(container, variable, T, string(formulation));
        init = 0.0,
    )
end

objective_value(model) = JuMP.objective_value(PSIN.get_jump_model(model))
