use super::state::SwapState;
use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};

pub trait SwapDb: Send + Sync {
    fn save(&self, state: &SwapState) -> Result<()>;
    fn load(&self, swap_id: &str) -> Result<Option<SwapState>>;
}

pub struct JsonFileDb {
    base_dir: PathBuf,
}

impl JsonFileDb {
    pub fn new<P: AsRef<Path>>(base_dir: P) -> Result<Self> {
        let base_dir = base_dir.as_ref().to_path_buf();
        fs::create_dir_all(&base_dir)
            .with_context(|| format!("Failed to create directory: {:?}", base_dir))?;
        Ok(Self { base_dir })
    }

    fn swap_file_path(&self, swap_id: &str) -> PathBuf {
        self.base_dir.join(format!("{}.json", swap_id))
    }
}

impl SwapDb for JsonFileDb {
    fn save(&self, state: &SwapState) -> Result<()> {
        let path = self.swap_file_path(state.swap_id());
        let json = serde_json::to_string_pretty(state)
            .with_context(|| format!("Failed to serialize state for swap {}", state.swap_id()))?;
        fs::write(&path, json)
            .with_context(|| format!("Failed to write state file: {:?}", path))?;
        Ok(())
    }

    fn load(&self, swap_id: &str) -> Result<Option<SwapState>> {
        let path = self.swap_file_path(swap_id);
        if !path.exists() {
            return Ok(None);
        }
        let json = fs::read_to_string(&path)
            .with_context(|| format!("Failed to read state file: {:?}", path))?;
        let state: SwapState = serde_json::from_str(&json)
            .with_context(|| format!("Failed to parse state file: {:?}", path))?;
        Ok(Some(state))
    }
}
