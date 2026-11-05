@testset "Package aliases" begin
    # The upstream packages PSC builds on must be the ones the test environment loads, so
    # portfolios and time mappings PSC creates are usable by the caller's PSIN.
    @test PSC.PSY === PSY
    @test PSC.PSIP === PSIP
    @test PSC.PSIN === PSIN
end
