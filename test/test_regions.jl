@testset "Device region at each aggregation level" begin
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    # c_sys5_re has no areas or load zones; put every bus in one of each.
    area = PSY.Area("area_1")
    load_zone = PSY.LoadZone("zone_1", 0.0, 0.0)
    PSY.add_component!(sys, area)
    PSY.add_component!(sys, load_zone)
    for bus in PSY.get_components(PSY.ACBus, sys)
        PSY.set_area!(bus, area)
        PSY.set_load_zone!(bus, load_zone)
    end

    for device in PSY.get_components(PSY.StaticInjection, sys)
        @test PSC.get_device_region(PSY.ACBus, device) === PSY.get_bus(device)
        @test PSC.get_device_region(PSY.Area, device) === area
        @test PSC.get_device_region(PSY.LoadZone, device) === load_zone
    end
end

@testset "Device region missing at the aggregation level" begin
    # No bus in c_sys5_re has an area or a load zone.
    sys = build_system(PSITestSystems, "c_sys5_re"; skip_serialization = true)
    device = first(PSY.get_components(PSY.ThermalStandard, sys))
    @test_throws ArgumentError PSC.get_device_region(PSY.Area, device)
    @test_throws ArgumentError PSC.get_device_region(PSY.LoadZone, device)
end
