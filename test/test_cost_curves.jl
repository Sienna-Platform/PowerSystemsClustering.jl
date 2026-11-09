# 300 MMBtu/h at 20 MW, 600 at 50 MW: 12 MMBtu/MWh average at full output, 10 incremental,
# 100 MMBtu/h at zero output.
const POINTS = IS.PiecewisePointCurve([(x = 20.0, y = 300.0), (x = 50.0, y = 600.0)])
const LIMITS = (min = 20.0, max = 50.0)

@testset "Linearize with the average rate" begin
    linear = PSC.linearize(POINTS, PSC.AverageRate(), LIMITS)
    @test IS.get_proportional_term(linear) ≈ 12.0
    @test IS.get_constant_term(linear) == 0.0

    # Other curve types: (10 * 100 + 200) / 100 and (0.01 * 100^2 + 10 * 100 + 100) / 100.
    limits = (min = 0.0, max = 100.0)
    linear_curve = PSC.linearize(IS.LinearCurve(10.0, 200.0), PSC.AverageRate(), limits)
    @test IS.get_proportional_term(linear_curve) ≈ 12.0
    quadratic =
        PSC.linearize(IS.QuadraticCurve(0.01, 10.0, 100.0), PSC.AverageRate(), limits)
    @test IS.get_proportional_term(quadratic) ≈ 12.0

    # Shaped like the RTS-GMLC heat rate curves: fuel at minimum output, then incremental
    # heat rates per segment.
    incremental =
        IS.PiecewiseIncrementalCurve(
            265.408,
            [22.0, 33.0, 44.0, 55.0],
            [6.003, 6.817, 7.176],
        )
    linear = PSC.linearize(incremental, PSC.AverageRate(), (min = 22.0, max = 55.0))
    @test IS.get_proportional_term(linear) ≈
          (265.408 + 11.0 * (6.003 + 6.817 + 7.176)) / 55.0
end

@testset "Linearize with the incremental rate" begin
    linear = PSC.linearize(POINTS, PSC.IncrementalRate(), LIMITS)
    # 100 MMBtu/h at zero output over 50 MW: 2 MMBtu/h per MW committed.
    @test IS.get_proportional_term(linear) ≈ 10.0
    @test IS.get_constant_term(linear) ≈ 2.0
    # Exact at minimum and maximum output with the full unit committed.
    @test IS.get_proportional_term(linear) * 20.0 + IS.get_constant_term(linear) * 50.0 ≈
          300.0
    @test IS.get_proportional_term(linear) * 50.0 + IS.get_constant_term(linear) * 50.0 ≈
          600.0
end

@testset "Linearize with an online cost" begin
    # 100 per hour online over 50 MW: 2 per MWh at full output, or 2 per hour per MW committed.
    average = PSC.linearize(POINTS, PSC.AverageRate(), LIMITS; online_cost = 100.0)
    @test IS.get_proportional_term(average) ≈ 14.0
    incremental = PSC.linearize(POINTS, PSC.IncrementalRate(), LIMITS; online_cost = 100.0)
    @test IS.get_proportional_term(incremental) ≈ 10.0
    @test IS.get_constant_term(incremental) ≈ 4.0
end

@testset "Linearize errors" begin
    # No range between minimum and maximum output, or a negative minimum.
    @test_throws ArgumentError PSC.linearize(
        POINTS,
        PSC.IncrementalRate(),
        (min = 50.0, max = 50.0),
    )
    @test_throws ArgumentError PSC.linearize(
        POINTS,
        PSC.IncrementalRate(),
        (min = -1.0, max = 50.0),
    )
    # Limits outside the piecewise curve.
    @test_throws ArgumentError PSC.linearize(
        POINTS,
        PSC.AverageRate(),
        (min = 20.0, max = 60.0),
    )
    # Without the input at minimum output the total input cannot be recovered.
    no_initial_input = IS.PiecewiseIncrementalCurve(nothing, [22.0, 33.0], [6.003])
    @test_throws ArgumentError PSC.linearize(
        no_initial_input,
        PSC.AverageRate(),
        (min = 22.0, max = 33.0),
    )
end
