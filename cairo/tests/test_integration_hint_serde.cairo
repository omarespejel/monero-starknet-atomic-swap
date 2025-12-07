#[cfg(test)]
mod hint_serde_tests {
    use core::array::ArrayTrait;
    use core::serde::Serde;

    #[test]
    fn test_hint_serde_roundtrip() {
        // Exact hint from get_real_msm_hints()
        let original: Array<felt252> = array![
            0xd21de05d0b4fe220a6fcca9b,
            0xa8e827ce9b59e1a5770bd9a,
            0x4e14ea0d8a7581a1,
            0x0,
            0x8cfb1d3e412e174d0ad03ad4,
            0x4417fe7cc6824de3b328f2a0,
            0x13f6f393b443ac08,
            0x0,
            0x1fd0f994a4c11a4543d86f4578e7b9ed,
            0x39099b31d1013f73ec51ebd61fdfe2ab
        ];
        let original_span = original.span();

        // Serialize (as constructor receives)
        let mut calldata: Array<felt252> = ArrayTrait::new();
        Serde::serialize(@original_span, ref calldata);

        // Deserialize (as constructor does)
        let mut calldata_span = calldata.span();
        let deserialized: Span<felt252> = Serde::deserialize(ref calldata_span).unwrap();

        // Verify all 10 values match
        assert(deserialized.len() == 10, 'Length mismatch');
        assert(*deserialized.at(0) == *original_span.at(0), 'Value 0');
        assert(*deserialized.at(1) == *original_span.at(1), 'Value 1');
        assert(*deserialized.at(8) == *original_span.at(8), 'Value 8 (s1)');
        assert(*deserialized.at(9) == *original_span.at(9), 'Value 9 (s2)');
    }
}

