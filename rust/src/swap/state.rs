use serde::{Deserialize, Deserializer, Serialize, Serializer};

// Custom serializer for u128 (serde_json doesn't support u128 natively)
fn serialize_u128_as_string<S>(value: &u128, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_str(&value.to_string())
}

fn deserialize_u128_from_string<'de, D>(deserializer: D) -> Result<u128, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    s.parse::<u128>().map_err(serde::de::Error::custom)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum SwapState {
    Created {
        swap_id: String,
        lock_duration_secs: u64,
        #[serde(serialize_with = "serialize_u128_as_string", deserialize_with = "deserialize_u128_from_string")]
        amount: u128,
        expected_monero_amount: u64, // Expected XMR amount in piconero (for validation)
        hashlock: [u32; 8],
        monero_restore_height: Option<u64>, // Monero block height when swap was initiated (for optimized sync)
    },
    StarknetLocked {
        swap_id: String,
        contract_address: String,
        lock_until: u64,
        expected_monero_amount: u64, // Expected XMR amount in piconero (for validation)
        hashlock: [u32; 8],
        monero_restore_height: Option<u64>, // Monero block height when swap was initiated (for optimized sync)
    },
    XmrSent {
        swap_id: String,
        contract_address: String,
        lock_until: u64,
        monero_txid: String,
        monero_amount: u64,
    },
    XmrConfirmed {
        swap_id: String,
        contract_address: String,
        lock_until: u64,
        monero_txid: String,
    },
    SecretRevealed {
        swap_id: String,
        contract_address: String,
        reveal_timestamp: u64,
        monero_restore_height: Option<u64>, // Monero block height when swap was initiated (for optimized sync)
        partial_spend_key: Option<[u8; 32]>, // Partial spend key (x_partial) for claiming Monero
        claim_destination: Option<String>, // Monero address to claim funds to
    },
    Completed {
        swap_id: String,
        starknet_tx: String,
        monero_txid: String,
    },
    Refunded {
        swap_id: String,
        reason: String,
        refund_tx: Option<String>,
    },
}

impl SwapState {
    pub fn swap_id(&self) -> &str {
        match self {
            Self::Created { swap_id, .. }
            | Self::StarknetLocked { swap_id, .. }
            | Self::XmrSent { swap_id, .. }
            | Self::XmrConfirmed { swap_id, .. }
            | Self::SecretRevealed { swap_id, .. }
            | Self::Completed { swap_id, .. }
            | Self::Refunded { swap_id, .. } => swap_id,
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Completed { .. } | Self::Refunded { .. })
    }
}

