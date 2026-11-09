# Financial inputs for the tests; any valid values work.
const FINANCIAL_DATA =
    (base_year = 2025, discount_rate = 0.07, inflation_rate = 0.02, interest_rate = 0.05)

const TECHNOLOGY_FINANCIAL_DATA = PSIP.TechnologyFinancialData(;
    capital_recovery_period = 30,
    technology_base_year = 2025,
    debt_fraction = 0.5,
    debt_rate = 0.05,
    return_on_equity = 0.1,
    tax_rate = 0.25,
)

# Empty portfolio with base system `sys` and regions at the `aggregation` level.
new_portfolio(sys::PSY.System, aggregation) =
    PSIP.Portfolio(aggregation, sys, values(FINANCIAL_DATA)...)
