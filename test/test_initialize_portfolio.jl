@testset "Initialize a portfolio from a system" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    portfolio = PSC.initialize_portfolio(sys, PSY.ACBus; FINANCIAL_DATA...)

    @test portfolio.base_system === sys
    @test portfolio.aggregation === PSY.ACBus
    @test PSIP.get_base_year(portfolio) == 2025
    @test PSIP.get_discount_rate(portfolio) == 0.07
    @test PSIP.get_inflation_rate(portfolio) == 0.02
    @test PSIP.get_interest_rate(portfolio) == 0.05
    # Regions come from the base system; nothing else is added yet.
    @test length(PSIP.get_regions(PSY.ACBus, portfolio)) ==
          length(PSY.get_components(PSY.ACBus, sys))
    @test isempty(PSIP.get_technologies(PSIP.SupplyTechnology, portfolio))
end

@testset "Initialize a portfolio at an aggregation level the system lacks" begin
    # c_sys5_re has buses but no areas.
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    @test_throws ArgumentError PSC.initialize_portfolio(sys, PSY.Area; FINANCIAL_DATA...)
end
