use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScopeConfig {
    pub decimation: u32,
    pub trigger_level: f32,
    pub trigger_source: u8, // 0: Auto, 1: CH1, 2: CH2
}

#[async_trait]
pub trait Oscilloscope: Send + Sync {
    /// Initialize or update configuration
    fn set_config(&self, config: ScopeConfig) -> Result<(), String>;
    
    /// Get current configuration
    fn get_config(&self) -> ScopeConfig;
    
    /// Acquire a snapshot of data (blocking or async)
    /// Returns raw binary data: [CH1_float32... | CH2_float32...]
    async fn acquire(&self) -> Result<Vec<u8>, String>;
}
