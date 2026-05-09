use core::array::ArrayTrait;
use garaga::definitions::G1Point;

#[test]
fn test_garaga_imports() {
    let points: Array<G1Point> = array![];
    assert(points.len() == 0, 'Garaga imports work');
}

