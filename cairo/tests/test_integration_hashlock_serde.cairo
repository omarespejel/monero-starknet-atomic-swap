/// Test to verify hashlock serialization/deserialization round-trip
/// This helps diagnose if Serde is corrupting the hashlock during calldata transmission

#[cfg(test)]
mod hashlock_serde_tests {
    use core::array::ArrayTrait;
    use core::serde::Serde;

    #[test]
    fn test_hashlock_serde_roundtrip() {
        // Original hashlock from test_vectors.json (Big-Endian u32 words from SHA-256)
        let original = array![
            0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
            0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32
        ].span();
        
        // Serialize (as constructor receives via calldata)
        let mut calldata = ArrayTrait::new();
        original.serialize(ref calldata);
        
        // Deserialize (as constructor does)
        let mut calldata_span = calldata.span();
        let deserialized: Span<u32> = Serde::deserialize(ref calldata_span).unwrap();
        
        // Verify all 8 words match exactly
        assert(deserialized.len() == 8, 'Length mismatch');
        assert(*deserialized.at(0) == *original.at(0), 'Word 0 mismatch');
        assert(*deserialized.at(1) == *original.at(1), 'Word 1 mismatch');
        assert(*deserialized.at(2) == *original.at(2), 'Word 2 mismatch');
        assert(*deserialized.at(3) == *original.at(3), 'Word 3 mismatch');
        assert(*deserialized.at(4) == *original.at(4), 'Word 4 mismatch');
        assert(*deserialized.at(5) == *original.at(5), 'Word 5 mismatch');
        assert(*deserialized.at(6) == *original.at(6), 'Word 6 mismatch');
        assert(*deserialized.at(7) == *original.at(7), 'Word 7 mismatch');
    }
}

