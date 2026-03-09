use async_trait::async_trait;
use crate::scope::{Oscilloscope, ScopeConfig};
use crate::feedback_controller::{FeedbackController, FeedbackConfig};
use std::sync::Mutex;
use std::fs::OpenOptions;

use byteorder::{ByteOrder, LittleEndian};

// Red Pitaya FPGA Memory Map (from v0.94.rst)
const OSC_BASE: usize = 0x40100000;
const OSC_SIZE: usize = 0x30000; // Covers registers + both channel buffers

// Feedback Controller Memory Map
const FB_CTRL_BASE: usize = 0x40900000;
const FB_CTRL_SIZE: usize = 0x1000; // 4KB should be enough

// Oscilloscope Register Offsets
const REG_CONFIG: usize = 0x00;      // Configuration
const REG_TRIG_SRC: usize = 0x04;    // Trigger source
const REG_CHA_THR: usize = 0x08;     // Ch A threshold
#[allow(dead_code)]
const REG_CHB_THR: usize = 0x0C;     // Ch B threshold
const REG_DELAY: usize = 0x10;       // Delay after trigger CH0
    const REG_DEC: usize = 0x14;         // Data decimation CH0
    const REG_WP_CUR: usize = 0x18;      // Write pointer - current CH0
    #[allow(dead_code)]
    const REG_WP_TRIG: usize = 0x1C;     // Write pointer - trigger CH0

// Data buffer offsets
const CHA_BUF_OFFSET: usize = 0x10000;
const CHB_BUF_OFFSET: usize = 0x20000;
const BUFFER_SIZE: usize = 16384;    // 16k samples per channel

// Configuration register bits (CH0)
const CFG_ARM: u32 = 1 << 0;         // Start writing data into memory (ARM trigger)
const CFG_RST: u32 = 1 << 1;         // Reset write state machine
const CFG_TRIG: u32 = 1 << 2;        // Trigger has arrived
const CFG_ACQ_DONE: u32 = 1 << 4;    // ACQ delay has passed

// Trigger sources
#[allow(dead_code)]
const TRIG_DISABLED: u32 = 0;
const TRIG_IMMEDIATE: u32 = 1;
const TRIG_CH_A_PE: u32 = 2; // Ch A positive edge
#[allow(dead_code)]
const TRIG_CH_A_NE: u32 = 3; // Ch A negative edge
const TRIG_CH_B_PE: u32 = 4; // Ch B positive edge
#[allow(dead_code)]
const TRIG_CH_B_NE: u32 = 5; // Ch B negative edge
#[allow(dead_code)]
const TRIG_EXT_PE: u32 = 6;  // External positive edge
#[allow(dead_code)]
const TRIG_EXT_NE: u32 = 7;  // External negative edge
#[allow(dead_code)]
const TRIG_AWG_PE: u32 = 8;  // AWG positive edge
#[allow(dead_code)]
const TRIG_AWG_NE: u32 = 9;  // AWG negative edge

// ADC parameters
const ADC_BITS: i32 = 14;
const ADC_MAX: f32 = (1 << (ADC_BITS - 1)) as f32; // 8192 for 14-bit

pub struct RealOscilloscope {
    config: Mutex<ScopeConfig>,
    mem: Mutex<Option<memmap2::MmapMut>>,
    armed: Mutex<bool>,
}

pub struct RealFeedbackController {
    config: Mutex<FeedbackConfig>,
    mem: Mutex<Option<memmap2::MmapMut>>,
}

impl RealOscilloscope {
    pub fn new() -> Self {
        let osc = Self {
            config: Mutex::new(ScopeConfig {
                decimation: 1,
                trigger_level: 0.0,
                trigger_source: 0,
            }),
            mem: Mutex::new(None),
            armed: Mutex::new(false),
        };
        
        // Try to map memory
        if let Err(e) = osc.init_mmap() {
            eprintln!("Warning: Failed to map FPGA memory: {}. Will retry on acquire.", e);
        }
        
        osc
    }
    
    fn init_mmap(&self) -> Result<(), String> {
        let mut mem_guard = self.mem.lock().unwrap();
        if mem_guard.is_some() {
            return Ok(());
        }
        
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/mem")
            .map_err(|e| format!("Failed to open /dev/mem: {}", e))?;
        
        let mmap = unsafe {
            memmap2::MmapOptions::new()
                .offset(OSC_BASE as u64)
                .len(OSC_SIZE)
                .map_mut(&file)
                .map_err(|e| format!("Failed to mmap: {}", e))?
        };
        
        *mem_guard = Some(mmap);
        println!("Successfully mapped FPGA oscilloscope registers at 0x{:08x}", OSC_BASE);
        Ok(())
    }
    
    fn read_reg(&self, offset: usize) -> Result<u32, String> {
        let mem_guard = self.mem.lock().unwrap();
        let mem = mem_guard.as_ref().ok_or("Memory not mapped")?;
        
        if offset + 4 > mem.len() {
            return Err(format!("Offset 0x{:x} out of bounds", offset));
        }
        
        Ok(LittleEndian::read_u32(&mem[offset..offset + 4]))
    }
    
    fn write_reg(&self, offset: usize, value: u32) -> Result<(), String> {
        let mut mem_guard = self.mem.lock().unwrap();
        let mem = mem_guard.as_mut().ok_or("Memory not mapped")?;
        
        if offset + 4 > mem.len() {
            return Err(format!("Offset 0x{:x} out of bounds", offset));
        }
        
        LittleEndian::write_u32(&mut mem[offset..offset + 4], value);
        Ok(())
    }
    
    fn read_buffer(&self, offset: usize, count: usize) -> Result<Vec<i16>, String> {
        let mem_guard = self.mem.lock().unwrap();
        let mem = mem_guard.as_ref().ok_or("Memory not mapped")?;
        
        let mut samples = Vec::with_capacity(count);
        for i in 0..count {
            let addr = offset + i * 4;
            if addr + 4 > mem.len() {
                break;
            }
            let raw = LittleEndian::read_u32(&mem[addr..addr + 4]);
            // Data is 14-bit signed in lower 16 bits, sign-extend to i16
            let raw_14 = (raw & 0x3FFF) as i16;
            let sample = if raw_14 >= 0x2000 { raw_14 - 0x4000 } else { raw_14 };
            samples.push(sample);
        }
        
        Ok(samples)
    }
    
    fn convert_to_float(samples: &[i16]) -> Vec<f32> {
        samples.iter()
            .map(|&s| (s as f32) / ADC_MAX)
            .collect()
    }
    
    fn arm_acquisition(&self, config: &ScopeConfig) -> Result<(), String> {
        self.write_reg(REG_CONFIG, CFG_RST)?;
        self.write_reg(REG_DEC, config.decimation)?;
        self.write_reg(REG_DELAY, (BUFFER_SIZE / 2) as u32)?; // Trigger in the middle of the buffer
        self.write_reg(REG_CONFIG, CFG_ARM)?;
        
        let trig_src = match config.trigger_source {
            1 => TRIG_CH_A_PE, // CH1 positive edge
            2 => TRIG_CH_B_PE, // CH2 positive edge
            _ => TRIG_IMMEDIATE, // Auto/Immediate
        };
        self.write_reg(REG_TRIG_SRC, trig_src)?;
        
        *self.armed.lock().unwrap() = true;
        Ok(())
    }
}

#[async_trait]
impl Oscilloscope for RealOscilloscope {
    fn set_config(&self, config: ScopeConfig) -> Result<(), String> {
        self.init_mmap()?;
        
        let threshold = ((config.trigger_level * ADC_MAX) as i32).clamp(-8192, 8191) as u32;
        self.write_reg(REG_CHA_THR, threshold & 0x3FFF)?;
        
        *self.config.lock().unwrap() = config.clone();
        
        self.arm_acquisition(&config)?;
        
        Ok(())
    }

    fn get_config(&self) -> ScopeConfig {
        self.config.lock().unwrap().clone()
    }

    async fn acquire(&self) -> Result<Vec<u8>, String> {
        self.init_mmap()?;
        
        let config = self.config.lock().unwrap().clone();
        
        if !*self.armed.lock().unwrap() {
            self.arm_acquisition(&config)?;
        }
        
        // Wait up to ~200ms for acquisition to complete
        // For low decimation, this will succeed quickly.
        // For high decimation, it will timeout, allowing us to read the partially filled buffer (roll mode).
        let mut acq_done = false;
        for _ in 0..20 {
            let status = self.read_reg(REG_CONFIG)?;
            if (status & CFG_ACQ_DONE) != 0 {
                acq_done = true;
                break;
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        }
        
        // To minimize tearing when reading a partially filled buffer, read write pointer before and after
        let wp_before = self.read_reg(REG_WP_CUR).unwrap_or(0);
        let mut cha_samples = self.read_buffer(CHA_BUF_OFFSET, BUFFER_SIZE)?;
        let mut chb_samples = self.read_buffer(CHB_BUF_OFFSET, BUFFER_SIZE)?;
        let wp_after = self.read_reg(REG_WP_CUR).unwrap_or(wp_before);

        // Handle circular buffer wrapping
        // Use wp_after for rotation, which represents the most recent data we got.
        let rotate_amount = (wp_after as usize + 1) % BUFFER_SIZE;
        cha_samples.rotate_left(rotate_amount);
        chb_samples.rotate_left(rotate_amount);
        
        if acq_done {
            self.arm_acquisition(&config)?;
        }
        
        let cha_float = Self::convert_to_float(&cha_samples);
        let chb_float = Self::convert_to_float(&chb_samples);
        
        let mut data = Vec::with_capacity(BUFFER_SIZE * 2 * 4);
        
        for &val in &cha_float {
            let mut buf = [0u8; 4];
            LittleEndian::write_f32(&mut buf, val);
            data.extend_from_slice(&buf);
        }
        
        for &val in &chb_float {
            let mut buf = [0u8; 4];
            LittleEndian::write_f32(&mut buf, val);
            data.extend_from_slice(&buf);
        }
        
        Ok(data)
    }
}

// Feedback Controller Register Offsets
const REG_FB_CONTROL: usize = 0x00;
const REG_FB_KP: usize = 0x04;
const REG_FB_KI: usize = 0x08;
const REG_FB_SETPOINT: usize = 0x0C;
const REG_FB_SIG_GEN_1: usize = 0x10;
const REG_FB_SIG_GEN_2: usize = 0x14;
const REG_FB_SIG_GEN_3: usize = 0x18;
// 0x1C was REG_FB_NOISE_CFG, now reserved (noise is from real DAC/ADC path)
const REG_FB_OUTPUT_MUX_CH1: usize = 0x20;
const REG_FB_OUTPUT_MUX_CH2: usize = 0x24;
const REG_FB_TEST: usize = 0x100;

impl RealFeedbackController {
    pub fn new() -> Self {
        let ctrl = Self {
            config: Mutex::new(FeedbackConfig::default()),
            mem: Mutex::new(None),
        };
        
        if let Err(e) = ctrl.init_mmap() {
            eprintln!("Warning: Failed to map feedback controller memory: {}. Will retry on access.", e);
        }
        
        ctrl
    }
    
    fn init_mmap(&self) -> Result<(), String> {
        let mut mem_guard = self.mem.lock().unwrap();
        if mem_guard.is_some() {
            return Ok(());
        }
        
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/mem")
            .map_err(|e| format!("Failed to open /dev/mem: {}", e))?;
        
        let mmap = unsafe {
            memmap2::MmapOptions::new()
                .offset(FB_CTRL_BASE as u64)
                .len(FB_CTRL_SIZE)
                .map_mut(&file)
                .map_err(|e| format!("Failed to mmap feedback controller: {}", e))?
        };
        
        *mem_guard = Some(mmap);
        println!("Successfully mapped feedback controller at 0x{:08x}", FB_CTRL_BASE);
        Ok(())
    }
    
    fn read_reg(&self, offset: usize) -> Result<u32, String> {
        let mem_guard = self.mem.lock().unwrap();
        let mem = mem_guard.as_ref().ok_or("Memory not mapped")?;
        
        if offset + 4 > mem.len() {
            return Err(format!("Offset 0x{:x} out of bounds", offset));
        }
        
        Ok(LittleEndian::read_u32(&mem[offset..offset + 4]))
    }
    
    fn write_reg(&self, offset: usize, value: u32) -> Result<(), String> {
        let mut mem_guard = self.mem.lock().unwrap();
        let mem = mem_guard.as_mut().ok_or("Memory not mapped")?;
        
        if offset + 4 > mem.len() {
            return Err(format!("Offset 0x{:x} out of bounds", offset));
        }
        
        LittleEndian::write_u32(&mut mem[offset..offset + 4], value);
        Ok(())
    }
}

impl FeedbackController for RealFeedbackController {
    fn set_config(&self, config: &FeedbackConfig) -> Result<(), String> {
        self.init_mmap()?;
        
        // First disable everything for clean state
        self.write_reg(REG_FB_CONTROL, 0)?;
        
        // Write signal generator gains (Q16.16 signed, cast to u32 for register write)
        self.write_reg(REG_FB_SIG_GEN_1, config.sig_gen_1 as u32)?;
        self.write_reg(REG_FB_SIG_GEN_2, config.sig_gen_2 as u32)?;
        self.write_reg(REG_FB_SIG_GEN_3, config.sig_gen_3 as u32)?;
        
        // Write PID parameters
        self.write_reg(REG_FB_KP, config.kp as u32)?;
        self.write_reg(REG_FB_KI, config.ki as u32)?;
        
        // Write setpoint (sign-extend to 32-bit)
        let setpoint_u32 = if config.setpoint < 0 {
            (config.setpoint as i32 as u32) & 0x3FFF
        } else {
            config.setpoint as u32 & 0x3FFF
        };
        self.write_reg(REG_FB_SETPOINT, setpoint_u32)?;
        
        // Write output MUX (independent CH1/CH2)
        self.write_reg(REG_FB_OUTPUT_MUX_CH1, config.output_mux_ch1 as u32)?;
        self.write_reg(REG_FB_OUTPUT_MUX_CH2, config.output_mux_ch2 as u32)?;
        
        // Finally write control register to enable
        let ctrl_val = config.to_control_reg();
        self.write_reg(REG_FB_CONTROL, ctrl_val)?;
        
        // Save configuration
        *self.config.lock().unwrap() = config.clone();
        
        Ok(())
    }
    
    fn get_config(&self) -> Result<FeedbackConfig, String> {
        self.init_mmap()?;
        
        let mut config = self.config.lock().unwrap().clone();
        
        // Read control register
        let ctrl = self.read_reg(REG_FB_CONTROL)?;
        config.from_control_reg(ctrl);
        
        // Read PID parameters
        config.kp = self.read_reg(REG_FB_KP)? as i32;
        config.ki = self.read_reg(REG_FB_KI)? as i32;
        
        // Read setpoint
        let setpoint_raw = self.read_reg(REG_FB_SETPOINT)? & 0x3FFF;
        config.setpoint = if setpoint_raw >= 0x2000 {
            (setpoint_raw as i16) - 0x4000
        } else {
            setpoint_raw as i16
        };
        
        // Read signal generators (Q16.16 signed, interpret u32 bits as i32)
        config.sig_gen_1 = self.read_reg(REG_FB_SIG_GEN_1)? as i32;
        config.sig_gen_2 = self.read_reg(REG_FB_SIG_GEN_2)? as i32;
        config.sig_gen_3 = self.read_reg(REG_FB_SIG_GEN_3)? as i32;
        
        // Read output MUX (independent CH1/CH2)
        config.output_mux_ch1 = self.read_reg(REG_FB_OUTPUT_MUX_CH1)? as u8;
        config.output_mux_ch2 = self.read_reg(REG_FB_OUTPUT_MUX_CH2)? as u8;
        
        Ok(config)
    }
    
    fn read_test_register(&self) -> Result<u32, String> {
        self.init_mmap()?;
        self.read_reg(REG_FB_TEST)
    }
}
