"""
How a unit's cost or fuel curve is replaced by the linear curve PSIN reads. Choose the method
matching the PSIN operation formulation the portfolio will be run with.
"""
abstract type CurveLinearization end

"""
For dispatch formulations (the default): the slope is the average rate at maximum output and
the constant term is zero. Exact at full output.
"""
struct AverageRate <: CurveLinearization end

"""
For commitment formulations: the slope is the incremental rate between minimum and maximum
output, and the constant term is the input at zero output divided by the maximum output, the
no-load input per MW committed that PSIN's commitment formulations read. Exact at minimum and
maximum output.
"""
struct IncrementalRate <: CurveLinearization end

"""
Linear curve that `method` gives for `curve` over the output limits `limits` (MW).
`online_cost`, an input per hour paid while the unit is online (PowerSystems' thermal `fixed`
cost), is added to the curve first.

Throws `ArgumentError` if the limits lie outside a piecewise curve or, for
[`IncrementalRate`](@ref), are not `0 <= min < max`.
"""
function linearize(
    curve::IS.ValueCurve,
    ::AverageRate,
    limits::PSY.MinMax;
    online_cost::Float64 = 0.0,
)
    input = _input_function(curve, online_cost)
    return IS.LinearCurve(input(limits.max) / limits.max, 0.0)
end

function linearize(
    curve::IS.ValueCurve,
    ::IncrementalRate,
    limits::PSY.MinMax;
    online_cost::Float64 = 0.0,
)
    if !(0.0 <= limits.min < limits.max)
        throw(
            ArgumentError(
                "An incremental rate needs 0 <= min < max output, got $(limits).",
            ),
        )
    end
    input = _input_function(curve, online_cost)
    rate = (input(limits.max) - input(limits.min)) / (limits.max - limits.min)
    input_at_zero = input(limits.min) - rate * limits.min
    return IS.LinearCurve(rate, input_at_zero / limits.max)
end

# Input per hour as a function of output in MW, including the online cost.
function _input_function(curve::IS.ValueCurve, online_cost::Float64)
    function_data = IS.get_function_data(_input_output_curve(curve))
    return output -> function_data(output) + online_cost
end

_input_output_curve(curve::IS.InputOutputCurve) = curve
_input_output_curve(curve::IS.ValueCurve) = IS.InputOutputCurve(curve)
