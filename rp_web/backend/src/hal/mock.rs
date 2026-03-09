use async_trait::async_trait;
use crate::scope::{Oscilloscope, ScopeConfig};
use crate::feedback_controller::{FeedbackController, FeedbackConfig};
use std::sync::Mutex;
use std::f32::consts::PI;
use rand::prelude::*;

pub struct MockOscilloscope {
    config: Mutex<ScopeConfig>,
}

pub struct MockFeedbackController {
    config: Mutex<FeedbackConfig>,
}

impl MockOscilloscope {
    pub fn new() -> Self {
        Self {
            config: Mutex::new(ScopeConfig {
                decimation: 1,
                trigger_level: 0.0,
                trigger_source: 0,
            }),
        }
    }
}

#[async_trait]
impl Oscilloscope for MockOscilloscope {
    fn set_config(&self, config: ScopeConfig) -> Result<(), String> {
        let mut c = self.config.lock().unwrap();
        *c = config;
        Ok(())
    }

    fn get_config(&self) -> ScopeConfig {
        self.config.lock().unwrap().clone()
    }

    async fn acquire(&self) -> Result<Vec<u8>, String> {
        // Simulate acquisition delay first (before holding non-Send rng)
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // Simulate 16k samples for 2 channels
        const BUFFER_SIZE: usize = 16384;
        let mut data = Vec::with_capacity(BUFFER_SIZE * 2 * 4); // 2 channels, 4 bytes per float
        let mut rng = rand::rng();
        
        // Use byteorder to write floats
        use byteorder::{ByteOrder, LittleEndian};

        let decimation = self.config.lock().unwrap().decimation as f32;
        let freq1 = 100.0 / decimation; // Base freq relative to sample rate
        let freq2 = 50.0 / decimation;

        // Channel 1
        for i in 0..BUFFER_SIZE {
            let t = i as f32;
            let noise: f32 = rng.random_range(-0.1..0.1);
            let val = (2.0 * PI * freq1 * t / 1000.0).sin() + noise;
            let mut buf = [0u8; 4];
            LittleEndian::write_f32(&mut buf, val);
            data.extend_from_slice(&buf);
        }

        // Channel 2
        for i in 0..BUFFER_SIZE {
            let t = i as f32;
            let noise: f32 = rng.random_range(-0.05..0.05);
            let val = (2.0 * PI * freq2 * t / 1000.0 + PI/4.0).sin() * 0.5 + noise;
            let mut buf = [0u8; 4];
            LittleEndian::write_f32(&mut buf, val);
            data.extend_from_slice(&buf);
        }

        Ok(data)
    }
}

impl MockFeedbackController {
    pub fn new() -> Self {
        Self {
            config: Mutex::new(FeedbackConfig::default()),
        }
    }
}

impl FeedbackController for MockFeedbackController {
    fn set_config(&self, config: &FeedbackConfig) -> Result<(), String> {
        println!("Mock: Setting feedback controller config: {:?}", config);
        *self.config.lock().unwrap() = config.clone();
        Ok(())
    }
    
    fn get_config(&self) -> Result<FeedbackConfig, String> {
        Ok(self.config.lock().unwrap().clone())
    }
    
    fn read_test_register(&self) -> Result<u32, String> {
        Ok(0x12345678)
    }
}
