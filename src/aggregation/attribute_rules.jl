# Rules combining an attribute's values across the units of a cluster into the value of the
# aggregated technology (decision 17). Each takes the units' values and their capacities, so a
# rule can be swapped for another with the same signature. A `NamedTuple` value (e.g. ramp
# limits `(up, down)`) is combined field by field.

"""
Capacity-weighted average of `values`, the rule for per-MW and fractional attributes (average
rates, minimum generation fraction, ramp rates, start-up costs per MW, efficiencies).

It is exact for the cluster: weighting each unit's per-MW value by its capacity gives the
cluster's total over its total capacity, e.g. heat rates weighted by capacity give the
cluster's fuel use per MWh at full output.
"""
capacity_weighted(values::AbstractVector{Float64}, capacities::AbstractVector{Float64}) =
    sum(values .* capacities) / sum(capacities)

"""
Largest of `values`, the rule for minimum up and down times: the aggregated technology is as
restrictive as its most restrictive unit.
"""
largest(values::AbstractVector{Float64}, ::AbstractVector{Float64}) = maximum(values)

capacity_weighted(
    values::AbstractVector{<:NamedTuple},
    capacities::AbstractVector{Float64},
) =
    _by_field(capacity_weighted, values, capacities)
largest(values::AbstractVector{<:NamedTuple}, capacities::AbstractVector{Float64}) =
    _by_field(largest, values, capacities)

# Apply `rule` to each field of the units' named tuples.
function _by_field(
    rule::Function,
    values::AbstractVector{<:NamedTuple{K}},
    capacities::AbstractVector{Float64},
) where {K}
    return NamedTuple{K}(Tuple(rule([value[k] for value in values], capacities) for k in K))
end
