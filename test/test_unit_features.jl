@testset "Thermal unit features" begin
    # RTS-GMLC 322_CT_6: 22-55 MW, ramps 3.7 MW/min, heat rate curve from 265.408 MMBtu/h at
    # 22 MW with incremental rates 6.003, 6.817 and 7.176 MMBtu/MWh over 11 MW segments.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    device = PSY.get_component(PSY.ThermalStandard, sys, "322_CT_6")
    features = PSC.unit_features(device)
    @test features.average_rate ≈ (265.408 + 11.0 * (6.003 + 6.817 + 7.176)) / 55.0
    @test features.capacity == 55.0
    @test features.min_generation_fraction ≈ 22.0 / 55.0
    @test features.ramp_rate ≈ 60.0 * 3.7 / 55.0

    # One column per device in a group, in device order.
    area_1_gas_cc = [
        PSY.get_component(PSY.ThermalStandard, sys, name) for
        name in ("107_CC_1", "118_CC_1")
    ]
    matrix, names = PSC.feature_matrix(area_1_gas_cc)
    @test names == [:average_rate, :capacity, :min_generation_fraction, :ramp_rate]
    @test size(matrix) == (4, 2)
    @test matrix[:, 2] == collect(values(PSC.unit_features(area_1_gas_cc[2])))
end

@testset "Thermal unit features include the online cost" begin
    # c_sys5_pglib 115_STEAM_1: cost curve 0 to 894.1 $/h at 5-12 MW plus 897.29 $/h online.
    sys = build_system(PSITestSystems, "c_sys5_pglib"; skip_serialization = true)
    device = PSY.get_component(PSY.ThermalMultiStart, sys, "115_STEAM_1")
    @test PSC.unit_features(device).average_rate ≈ (894.1 + 897.29) / 12.0
end

@testset "Hydro and storage unit features" begin
    hydro_sys = build_system(PSITestSystems, "c_sys5_hy"; skip_serialization = true)
    hydro = only(PSY.get_components(PSY.HydroDispatch, hydro_sys))
    @test PSC.unit_features(hydro) == (capacity = 600.0,)

    # c_sys5_bat: 200 MW, 400 MWh, efficiency 0.8 in and 0.9 out.
    storage_sys = build_system(PSITestSystems, "c_sys5_bat"; skip_serialization = true)
    storage = only(PSY.get_components(PSY.EnergyReservoirStorage, storage_sys))
    features = PSC.unit_features(storage)
    @test features.power_capacity == 200.0
    @test features.duration == 2.0
    @test features.round_trip_efficiency ≈ 0.72
end

@testset "Renewable profile features" begin
    # Every RTS-GMLC renewable group: one column per unit, one row per hour of 2020.
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys_noForecast"; skip_serialization = true)
    groups = PSC.group_devices(PSY.get_components(PSC.RenewableDevice, sys), PSY.Area)
    for (key, devices) in groups
        matrix, time_stamps = PSC.feature_matrix(devices)
        @test size(matrix) == (8784, length(devices))
        @test first(time_stamps) == DateTime(2020, 1, 1)
        # Per unit of capacity, except 212_CSP_1's, which reaches 1.96.
        @test all(matrix .>= 0.0)
        profile = PSY.get_time_series_values(
            PSY.SingleTimeSeries,
            last(devices),
            "max_active_power",
        )
        @test matrix[:, end] == profile
    end
end
