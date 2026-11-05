"""
Create an empty `PSIP.Portfolio` whose base system is `sys`.

Regions are not copied into the portfolio: PSIP reads them from the base system's topology
components of type `aggregation` (`PSY.ACBus`, `PSY.LoadZone` or `PSY.Area`). The system is
referenced, not copied.

# Arguments

  - `sys::PSY.System`: system holding the existing devices and their time series
  - `aggregation`: topology type that defines the portfolio's regions
  - `base_year::Int`: year that PSIN discounts costs to
  - `discount_rate::Float64`, `inflation_rate::Float64`, `interest_rate::Float64`: portfolio
    financial data used by PSIN

Throws `ArgumentError` if `sys` has no components of type `aggregation`.
"""
function initialize_portfolio(
    sys::PSY.System,
    aggregation::Type{<:Union{PSY.ACBus, PSY.AggregationTopology}};
    base_year::Int,
    discount_rate::Float64,
    inflation_rate::Float64,
    interest_rate::Float64,
)
    if isempty(PSY.get_components(aggregation, sys))
        throw(
            ArgumentError(
                "The system has no $(nameof(aggregation)) components, so it has no regions at " *
                "that aggregation level. Choose another aggregation level or add " *
                "$(nameof(aggregation)) components to the system.",
            ),
        )
    end
    return PSIP.Portfolio(
        aggregation,
        sys,
        base_year,
        discount_rate,
        inflation_rate,
        interest_rate,
    )
end
