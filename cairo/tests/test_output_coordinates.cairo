/// Diagnostic test to output decompressed Weierstrass coordinates
/// Run this test and capture output to regenerate hints in Python

#[cfg(test)]
mod output_coordinates_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;
    use core::debug::print_felt252;

    const ED25519_CURVE_INDEX: u32 = 4;

    // Test vector constants (from test_e2e_dleq.cairo - MUST MATCH EXACTLY)
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0x448c18dcf34127e112ff945a65defbfc,
        high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
    };

    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xdcad2173817c163b5405cec7698eb4b8,
        high: 0x742bb3c44b13553c8ddff66565b44cac,
    };

    #[test]
    #[available_gas(99999999999999999)]
    fn output_adaptor_point_coordinates() {
        // Decompress adaptor point (T)
        let adaptor_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        
        if adaptor_result.is_none() {
            assert(false, 'Adaptor decompress failed');
        }
        
        let adaptor = adaptor_result.unwrap();
        adaptor.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Output u384 limbs for x and y coordinates
        // Format: [limb0, limb1, limb2, limb3] for each coordinate
        // These values can be used to regenerate hints in Python
        
        // X coordinate limbs
        let x0: felt252 = adaptor.x.limb0.into();
        let x1: felt252 = adaptor.x.limb1.into();
        let x2: felt252 = adaptor.x.limb2.into();
        let x3: felt252 = adaptor.x.limb3.into();
        
        // Y coordinate limbs
        let y0: felt252 = adaptor.y.limb0.into();
        let y1: felt252 = adaptor.y.limb1.into();
        let y2: felt252 = adaptor.y.limb2.into();
        let y3: felt252 = adaptor.y.limb3.into();
        
        // Print coordinates (for Python hint regeneration)
        print_felt252('T_x_limb0');
        print_felt252(x0);
        print_felt252('T_x_limb1');
        print_felt252(x1);
        print_felt252('T_x_limb2');
        print_felt252(x2);
        print_felt252('T_x_limb3');
        print_felt252(x3);
        
        print_felt252('T_y_limb0');
        print_felt252(y0);
        print_felt252('T_y_limb1');
        print_felt252(y1);
        print_felt252('T_y_limb2');
        print_felt252(y2);
        print_felt252('T_y_limb3');
        print_felt252(y3);
        
        assert(true, 'Output coords');
    }
    
    #[test]
    #[available_gas(99999999999999999)]
    fn output_second_point_coordinates() {
        // Decompress second point (U)
        let second_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        
        if second_result.is_none() {
            assert(false, 'Second decompress failed');
        }
        
        let second = second_result.unwrap();
        second.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Output u384 limbs for x and y coordinates
        let x0: felt252 = second.x.limb0.into();
        let x1: felt252 = second.x.limb1.into();
        let x2: felt252 = second.x.limb2.into();
        let x3: felt252 = second.x.limb3.into();
        
        let y0: felt252 = second.y.limb0.into();
        let y1: felt252 = second.y.limb1.into();
        let y2: felt252 = second.y.limb2.into();
        let y3: felt252 = second.y.limb3.into();
        
        // Print coordinates (for Python hint regeneration)
        print_felt252('U_x_limb0');
        print_felt252(x0);
        print_felt252('U_x_limb1');
        print_felt252(x1);
        print_felt252('U_x_limb2');
        print_felt252(x2);
        print_felt252('U_x_limb3');
        print_felt252(x3);
        
        print_felt252('U_y_limb0');
        print_felt252(y0);
        print_felt252('U_y_limb1');
        print_felt252(y1);
        print_felt252('U_y_limb2');
        print_felt252(y2);
        print_felt252('U_y_limb3');
        print_felt252(y3);
        
        assert(true, 'Output coords');
    }
}

