#[cfg(test)]
mod hint_serde_tests {
    use core::array::ArrayTrait;
    use core::serde::Serde;

    #[test]
    fn test_hint_serde_roundtrip() {
        // Exact hint from get_real_msm_hints()
        let original: Array<felt252> = array![
            0x52f522935135e7c5474d3b99,
            0x7ff7e65231c434008a0c02f8,
            0x41a3962ca5bba9db,
            0x0,
            0xa144206dc24b7180d05200e0,
            0xe8a798301a354777473cd98e,
            0x7ca5add375ea088,
            0x0,
            0x1e741f8fec4161ea41b23ce6d007ba12,
            0x100000000000000000000000000000001
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

