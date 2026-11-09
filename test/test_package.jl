@testset "Package aliases" begin
    # PSC must use the same packages as the caller.
    @test PSC.PSY === PSY
    @test PSC.PSIP === PSIP
    @test PSC.PSIN === PSIN
end
