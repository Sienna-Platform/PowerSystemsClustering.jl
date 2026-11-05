"""
Create an empty `PSIP.Portfolio` with base system `sys` and regions at the aggregation level
`aggregation` (`PSY.ACBus`, `PSY.LoadZone` or `PSY.Area`). PSIP reads the regions from the base
system, which is referenced, not copied. The financial keywords are the portfolio data PSIN
discounts costs with.

Throws `ArgumentError` if `sys` has no `aggregation` components.
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
        throw(ArgumentError("The system has no $(nameof(aggregation)) components."))
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
