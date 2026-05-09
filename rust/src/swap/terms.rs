//! Product-facing swap terms shared by quote, relayer, and UI code.
//!
//! The protocol always settles through the Starknet `AtomicLock`, but the user
//! journey can run in either direction. Keep the direction explicit so API and
//! frontend code do not infer roles from token names or amounts.

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::str::FromStr;
use thiserror::Error;

pub const MIN_LOCK_DURATION_SECS: u64 = 3 * 60 * 60;
pub const DEFAULT_MONERO_CONFIRMATIONS: u64 = 10;

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

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Chain {
    Monero,
    Starknet,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MoneroNetwork {
    Mainnet,
    Stagenet,
    Testnet,
}

impl FromStr for MoneroNetwork {
    type Err = SwapTermParseError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match normalized(value).as_str() {
            "mainnet" => Ok(Self::Mainnet),
            "stagenet" => Ok(Self::Stagenet),
            "testnet" => Ok(Self::Testnet),
            _ => Err(SwapTermParseError::InvalidMoneroNetwork(value.to_string())),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StarknetReceiveMode {
    PublicAddress,
    PrivacyOpenNote,
}

impl Default for StarknetReceiveMode {
    fn default() -> Self {
        Self::PublicAddress
    }
}

impl FromStr for StarknetReceiveMode {
    type Err = SwapTermParseError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match normalized(value).as_str() {
            "public_address" | "public" => Ok(Self::PublicAddress),
            "privacy_open_note" | "private" | "privacy" => Ok(Self::PrivacyOpenNote),
            _ => Err(SwapTermParseError::InvalidStarknetReceiveMode(
                value.to_string(),
            )),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SwapDirection {
    /// User sends XMR and receives a Starknet token claim.
    XmrToStarknet,
    /// User locks a Starknet token and receives XMR.
    StarknetToXmr,
}

impl FromStr for SwapDirection {
    type Err = SwapTermParseError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match normalized(value).as_str() {
            "xmr_to_starknet" | "monero_to_starknet" => Ok(Self::XmrToStarknet),
            "starknet_to_xmr" | "starknet_to_monero" => Ok(Self::StarknetToXmr),
            _ => Err(SwapTermParseError::InvalidDirection(value.to_string())),
        }
    }
}

impl SwapDirection {
    pub fn user_sends(self) -> Chain {
        match self {
            Self::XmrToStarknet => Chain::Monero,
            Self::StarknetToXmr => Chain::Starknet,
        }
    }

    pub fn user_receives(self) -> Chain {
        match self {
            Self::XmrToStarknet => Chain::Starknet,
            Self::StarknetToXmr => Chain::Monero,
        }
    }

    pub fn user_receives_starknet_claim(self) -> bool {
        matches!(self, Self::XmrToStarknet)
    }

    pub fn user_receives_monero_claim(self) -> bool {
        matches!(self, Self::StarknetToXmr)
    }
}

fn normalized(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('-', "_")
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SwapTerms {
    pub swap_id: String,
    pub direction: SwapDirection,
    pub monero_network: MoneroNetwork,
    pub monero_amount_piconero: u64,
    #[serde(
        serialize_with = "serialize_u128_as_string",
        deserialize_with = "deserialize_u128_from_string"
    )]
    pub starknet_amount: u128,
    pub starknet_token: String,
    pub lock_duration_secs: u64,
    pub monero_confirmations: u64,
    #[serde(default)]
    pub starknet_receive_mode: StarknetReceiveMode,
}

impl SwapTerms {
    pub fn validate(&self) -> Result<(), SwapTermsError> {
        if self.swap_id.trim().is_empty() {
            return Err(SwapTermsError::MissingSwapId);
        }
        if self.monero_amount_piconero == 0 {
            return Err(SwapTermsError::ZeroMoneroAmount);
        }
        if self.starknet_amount == 0 {
            return Err(SwapTermsError::ZeroStarknetAmount);
        }
        if self.lock_duration_secs < MIN_LOCK_DURATION_SECS {
            return Err(SwapTermsError::LockDurationTooShort {
                actual: self.lock_duration_secs,
                minimum: MIN_LOCK_DURATION_SECS,
            });
        }
        if self.monero_confirmations < DEFAULT_MONERO_CONFIRMATIONS {
            return Err(SwapTermsError::InsufficientMoneroConfirmations {
                actual: self.monero_confirmations,
                minimum: DEFAULT_MONERO_CONFIRMATIONS,
            });
        }
        if !self.starknet_token.starts_with("0x") || self.starknet_token.len() <= 2 {
            return Err(SwapTermsError::InvalidStarknetToken);
        }
        Ok(())
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SwapTermParseError {
    #[error("invalid swap direction: {0}")]
    InvalidDirection(String),
    #[error("invalid monero network: {0}")]
    InvalidMoneroNetwork(String),
    #[error("invalid starknet receive mode: {0}")]
    InvalidStarknetReceiveMode(String),
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SwapTermsError {
    #[error("swap_id is required")]
    MissingSwapId,
    #[error("monero amount must be non-zero")]
    ZeroMoneroAmount,
    #[error("starknet amount must be non-zero")]
    ZeroStarknetAmount,
    #[error("lock duration {actual}s is shorter than minimum {minimum}s")]
    LockDurationTooShort { actual: u64, minimum: u64 },
    #[error("monero confirmations {actual} is lower than minimum {minimum}")]
    InsufficientMoneroConfirmations { actual: u64, minimum: u64 },
    #[error("starknet token must be a non-empty 0x-prefixed address")]
    InvalidStarknetToken,
}
