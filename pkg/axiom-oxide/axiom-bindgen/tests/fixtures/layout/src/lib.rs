use axiom_ffi::{axiom_export, axiom_record, AxFn3};

#[axiom_record]
pub struct SatelliteTelemetryPacket {
    pub first: i64,
    pub second: i64,
    pub third: i64,
    pub fourth: i64,
    pub fifth: i64,
    pub sixth: i64,
    pub seventh: i64,
    pub eighth: i64,
    pub ninth: i64,
    pub tenth: i64,
    pub eleventh: i64,
    pub twelfth: i64,
    pub thirteenth: i64,
    pub fourteenth: i64,
    pub fifteenth: i64,
    pub weight: f64,
}

#[axiom_export]
pub fn request_satellite_telemetry(
    primary_packet: SatelliteTelemetryPacket,
    secondary_packet: SatelliteTelemetryPacket,
    received_packets: &[SatelliteTelemetryPacket],
    inspect_payload: AxFn3<'_>,
    maximum_payload_bytes: i64,
    timeout_milliseconds: i64,
) -> Result<Option<Vec<SatelliteTelemetryPacket>>, String> {
    unreachable!()
}
