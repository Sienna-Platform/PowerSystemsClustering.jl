@testset "Cluster a thermal group" begin
    # RTS-GMLC area 3 gas CTs: 11 units of 55 MW that differ only in heat rate (MMBtu/MWh):
    # 10.458 (301_CT_3/4), 11.859 (302_CT_3/4), 10.105 (307_CT_1/2), 8.518 (315_CT_6/7/8) and
    # 8.825 (322_CT_5/6).
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.ThermalDevice, sys), PSY.Area)
    devices = groups[(
        region = "3",
        type = PSY.ThermalStandard,
        prime_mover = PSY.PrimeMovers.CT,
        fuel = PSY.ThermalFuels.NATURAL_GAS,
        available = true,
    )]
    # Two clusters split efficient from less efficient units; a third separates the least
    # efficient pair.
    @test PSC.cluster_group(devices, 2) == [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2]
    @test PSC.cluster_group(devices, 3) == [1, 1, 2, 2, 1, 1, 3, 3, 3, 3, 3]
    # One cluster merges the group; one per unit keeps every unit.
    @test PSC.cluster_group(devices, 1) == fill(1, 11)
    @test PSC.cluster_group(devices, 11) == collect(1:11)
end

@testset "Cluster a renewable group on profiles" begin
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.RenewableDevice, sys), PSY.Area)
    devices = argmax(length, values(groups))
    clusters = PSC.cluster_group(devices, 2)
    @test sort(unique(clusters)) == [1, 2]
    @test first(clusters) == 1
    @test PSC.cluster_group(devices, 2; seed = 1) == clusters
end

@testset "Scale features" begin
    # Rows of scalar features become z-scores; a constant row becomes zero.
    matrix = [1.0 2.0 3.0; 5.0 5.0 5.0]
    scaled = PSC._scale_features(matrix, [:a, :b])
    @test scaled[1, :] ≈ [-1.0, 0.0, 1.0] ./ sqrt(2.0 / 3.0)
    @test scaled[2, :] == [0.0, 0.0, 0.0]
    # Profiles are left as they are.
    stamps = [DateTime(2020, 1, 1), DateTime(2020, 1, 1, 1)]
    @test PSC._scale_features(matrix, stamps) === matrix
end
