"""
How a cost or fuel curve is linearized. Choose the one matching the PSIN operation formulation.
"""
abstract type CurveLinearization end

"""
For dispatch formulations (default): slope = average rate at maximum output, no constant term.
Exact at full output.
"""
struct AverageRate <: CurveLinearization end

"""
For commitment formulations: slope = incremental rate between minimum and maximum output,
constant = input at zero output per MW of maximum output (no-load input per MW committed).
Exact at minimum and maximum output.
"""
struct IncrementalRate <: CurveLinearization end

"""
Linearize `curve` over the output limits `limits` (MW) with `method`, after adding
`online_cost`, an input per hour while online (PowerSystems' `fixed` cost).
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

# Input per hour at an output in MW, including the online cost.
function _input_function(curve::IS.ValueCurve, online_cost::Float64)
    function_data = IS.get_function_data(_input_output_curve(curve))
    return output -> function_data(output) + online_cost
end

_input_output_curve(curve::IS.InputOutputCurve) = curve
_input_output_curve(curve::IS.ValueCurve) = IS.InputOutputCurve(curve)

# Linearize a variable cost curve in MW, keeping its kind, fuel price and VOM. The online cost
# `fixed` joins a cost curve; it cannot join a fuel curve.
function _linear_variable_cost(
    curve::IS.CostCurve{<:IS.ValueCurve, PSY.NaturalUnit},
    linearization::CurveLinearization,
    limits::PSY.MinMax,
    fixed::Float64,
    ::PSY.StaticInjection,
)
    linear =
        linearize(IS.get_value_curve(curve), linearization, limits; online_cost = fixed)
    return IS.CostCurve(linear, PSY.NaturalUnit(), IS.get_vom_cost(curve))
end

function _linear_variable_cost(
    curve::IS.FuelCurve{<:IS.ValueCurve, PSY.NaturalUnit},
    linearization::CurveLinearization,
    limits::PSY.MinMax,
    fixed::Float64,
    device::PSY.StaticInjection,
)
    if !iszero(fixed)
        throw(
            ArgumentError(
                "$(PSY.get_name(device)): a fixed cost cannot be added to a fuel curve.",
            ),
        )
    end
    start_up_fuel = IS.get_proportional_term(IS.get_startup_fuel_offtake(curve))
    return IS.FuelCurve(
        linearize(IS.get_value_curve(curve), linearization, limits),
        PSY.NaturalUnit(),
        IS.get_fuel_units(curve),
        IS.get_fuel_cost(curve),
        IS.LinearCurve(start_up_fuel / limits.max),
        IS.get_vom_cost(curve),
    )
end
