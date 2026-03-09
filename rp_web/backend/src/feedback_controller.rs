use serde::{Deserialize, Serialize};

/// Feedback controller configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedbackConfig {
    /// Global enable (bit 0)
    pub global_enable: bool,
    /// Reset PID (bit 1, active high)
    pub rst_pid: bool,
    /// Mode: false=Open Loop, true=Closed Loop (bit 2)
    pub closed_loop: bool,
    /// CIC Enable: false=Bypass, true=Enable (bit 3)
    pub cic_enable: bool,
    /// PID proportional gain (Q16.16 format, -2147483648 to 2147483647)
    pub kp: i32,
    /// PID integral gain (Q16.16 format, -2147483648 to 2147483647)
    pub ki: i32,
    /// Setpoint (14-bit, -8191 to +8191)
    pub setpoint: i16,
    /// Signal generator 1 gain (0.5Hz drift, Q16.16 format, -2147483648 to 2147483647)
    pub sig_gen_1: i32,
    /// Signal generator 2 gain (330Hz vibration, Q16.16 format, -2147483648 to 2147483647)
    pub sig_gen_2: i32,
    /// Signal generator 3 gain (1200Hz acoustic, Q16.16 format, -2147483648 to 2147483647)
    pub sig_gen_3: i32,
    /// Output MUX CH1 selection (0-5)
    /// 0: ADC Channel A, 1: ADC Channel B, 2: Disturbance,
    /// 3: Feedback/PID, 4: DAC Output, 5: CIC Filtered
    pub output_mux_ch1: u8,
    /// Output MUX CH2 selection (0-5)
    /// 0: ADC Channel A, 1: ADC Channel B, 2: Disturbance,
    /// 3: Feedback/PID, 4: DAC Output, 5: CIC Filtered
    pub output_mux_ch2: u8,
}

impl Default for FeedbackConfig {
    fn default() -> Self {
        Self {
            global_enable: false,
            rst_pid: false,
            closed_loop: false,
            cic_enable: false,
            kp: 0,
            ki: 0,
            setpoint: 0,
            // Signal Gen Gains (Q16.16: float * 65536)
            // Sum = 0.65 → peak disturbance ~5324 counts, well under ±8192 saturation
            sig_gen_1: 32768,  // 0.50 → 0x00008000
            sig_gen_2: 6554,   // 0.10 → 0x0000199A
            sig_gen_3: 3277,   // 0.05 → 0x00000CCD
            output_mux_ch1: 5, // Default to CIC filtered
            output_mux_ch2: 3, // Default to Feedback/PID
        }
    }
}

impl FeedbackConfig {
    /// Convert configuration to reg_control value
    pub fn to_control_reg(&self) -> u32 {
        let mut ctrl: u32 = 0;
        if self.global_enable {
            ctrl |= 1 << 0;
        }
        if self.rst_pid {
            ctrl |= 1 << 1;
        }
        if self.closed_loop {
            ctrl |= 1 << 2;
        }
        if self.cic_enable {
            ctrl |= 1 << 3;
        }
        ctrl
    }

    /// Parse reg_control value into configuration
    pub fn from_control_reg(&mut self, ctrl: u32) {
        self.global_enable = (ctrl & (1 << 0)) != 0;
        self.rst_pid = (ctrl & (1 << 1)) != 0;
        self.closed_loop = (ctrl & (1 << 2)) != 0;
        self.cic_enable = (ctrl & (1 << 3)) != 0;
    }
}

/// Preset modes matching the shell script
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ControlMode {
    /// Open Loop + CIC enabled, show CIC filtered output
    Open,
    /// Closed Loop + CIC + PID
    Closed,
    /// Open Loop, NO CIC, show raw disturbance
    Raw,
    /// Open Loop, NO CIC, show DAC output
    Bypass,
}

impl ControlMode {
    pub fn to_config(&self) -> FeedbackConfig {
        let mut cfg = FeedbackConfig::default();

        match self {
            ControlMode::Open => {
                cfg.global_enable = true;
                cfg.cic_enable = true;
                cfg.closed_loop = false;
                cfg.kp = 0;
                cfg.ki = 0;
                cfg.output_mux_ch1 = 5; // CIC filtered
                cfg.output_mux_ch2 = 3; // Feedback/PID
            }
            ControlMode::Closed => {
                cfg.global_enable = true;
                cfg.cic_enable = true;
                cfg.closed_loop = true;
                // Kp = 0.01 → 655 (Q16.16)
                cfg.kp = 655;
                // Ki must be tiny: at 1MHz CIC rate, Ki=1 takes ~8s to wind up
                // (1 * mean_error_counts / 65536) * 8e6 ≈ 8192 if mean_error≈67)
                // Ki=10 would wind up 10× faster (~54s for 1-count DC bias → definitely saturates)
                cfg.ki = 1;
                cfg.output_mux_ch1 = 5; // CIC filtered
                cfg.output_mux_ch2 = 3; // Feedback/PID
            }
            ControlMode::Raw => {
                cfg.global_enable = true;
                cfg.cic_enable = false;
                cfg.closed_loop = false;
                cfg.kp = 0;
                cfg.ki = 0;
                cfg.output_mux_ch1 = 2; // Disturbance
                cfg.output_mux_ch2 = 3; // Feedback/PID
            }
            ControlMode::Bypass => {
                cfg.global_enable = true;
                cfg.cic_enable = false;
                cfg.closed_loop = false;
                cfg.kp = 0;
                cfg.ki = 0;
                cfg.output_mux_ch1 = 4; // DAC Output
                cfg.output_mux_ch2 = 3; // Feedback/PID
            }
        }

        cfg
    }
}

/// Trait for feedback controller hardware access
pub trait FeedbackController: Send + Sync {
    /// Set configuration
    fn set_config(&self, config: &FeedbackConfig) -> Result<(), String>;

    /// Get current configuration
    fn get_config(&self) -> Result<FeedbackConfig, String>;

    /// Read test register (should return 0x12345678)
    fn read_test_register(&self) -> Result<u32, String>;

    /// Apply a preset mode
    fn set_mode(&self, mode: ControlMode) -> Result<(), String> {
        let config = mode.to_config();
        self.set_config(&config)
    }
}
