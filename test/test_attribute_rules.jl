@testset "Capacity-weighted attributes" begin
    # Two units of 100 and 300 MW with heat rates of 8 and 12 MMBtu/MWh burn
    # 800 + 3600 = 4400 MMBtu/h at full output, 11 MMBtu/MWh over their 400 MW.
    capacities = [100.0, 300.0]
    @test PSC.capacity_weighted([8.0, 12.0], capacities) ≈ 11.0
    # Minimum outputs of 40 % and 20 % are 40 + 60 = 100 MW, 25 % of 400 MW.
    @test PSC.capacity_weighted([0.4, 0.2], capacities) ≈ 0.25
end

@testset "Largest and total attributes" begin
    capacities = [100.0, 300.0]
    @test PSC.largest([60.0, 240.0], capacities) == 240.0
    @test PSC.total([100.0, 300.0], capacities) == 400.0
end
