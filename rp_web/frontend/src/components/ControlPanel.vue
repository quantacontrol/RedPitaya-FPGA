<script setup lang="ts">
import { ref, onMounted, reactive, computed } from 'vue';

// Track which sections are collapsed
const collapsed = reactive({
  quickModes: false,
  control: false,
  pid: false,
  signalGen: false,
  output: false,
});

function toggleSection(section: keyof typeof collapsed) {
  collapsed[section] = !collapsed[section];
}

interface FeedbackConfig {
  global_enable: boolean;
  rst_pid: boolean;
  closed_loop: boolean;
  cic_enable: boolean;
  kp: number;
  ki: number;
  setpoint: number;
  sig_gen_1: number;
  sig_gen_2: number;
  sig_gen_3: number;
  output_mux_ch1: number;
  output_mux_ch2: number;
}

type ControlMode = 'open' | 'closed' | 'raw' | 'bypass';

const config = ref<FeedbackConfig>({
  global_enable: false,
  rst_pid: false,
  closed_loop: false,
  cic_enable: false,
  kp: 0,
  ki: 0,
  setpoint: 0,
  sig_gen_1: Math.round(0.50 * 65536),   // 0.50 → 0x00008000 (peak ~4096 counts, 50% FS)
  sig_gen_2: Math.round(0.10 * 65536),   // 0.10 → 0x0000199A
  sig_gen_3: Math.round(0.05 * 65536),   // 0.05 → 0x00000CCD  (total 0.65, safe headroom)
  output_mux_ch1: 5,  // CIC Filtered
  output_mux_ch2: 3,  // Feedback/PID
});

const statusMessage = ref<string>('');
const testRegValue = ref<string>('');

async function loadConfig() {
  try {
    const response = await fetch('/api/v1/feedback/config');
    if (response.ok) {
      config.value = await response.json();
      statusMessage.value = '✓ Configuration loaded';
    } else {
      statusMessage.value = '✗ Failed to load config';
    }
  } catch (e) {
    console.error('Failed to load config:', e);
    statusMessage.value = '✗ Connection error';
  }
}

async function applyConfig() {
  try {
    const response = await fetch('/api/v1/feedback/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(config.value),
    });
    
    if (response.ok) {
      statusMessage.value = '✓ Configuration applied';
    } else {
      const error = await response.text();
      statusMessage.value = `✗ Error: ${error}`;
    }
  } catch (e) {
    console.error('Failed to apply config:', e);
    statusMessage.value = '✗ Connection error';
  }
}

async function setMode(mode: ControlMode) {
  try {
    const response = await fetch('/api/v1/feedback/mode', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(mode),
    });
    
    if (response.ok) {
      statusMessage.value = `✓ Mode set to: ${mode}`;
      await loadConfig(); // Reload to show updated values
    } else {
      const error = await response.text();
      statusMessage.value = `✗ Error: ${error}`;
    }
  } catch (e) {
    console.error('Failed to set mode:', e);
    statusMessage.value = '✗ Connection error';
  }
}

async function testRegister() {
  try {
    const response = await fetch('/api/v1/feedback/test');
    if (response.ok) {
      testRegValue.value = await response.text();
      statusMessage.value = '✓ Test register read';
    } else {
      testRegValue.value = 'Error';
      statusMessage.value = '✗ Failed to read test register';
    }
  } catch (e) {
    console.error('Failed to test register:', e);
    testRegValue.value = 'Error';
    statusMessage.value = '✗ Connection error';
  }
}

// Q16.16 helpers: float <-> raw int conversion, hex display
function toHex32(n: number): string {
  return '0x' + (n >>> 0).toString(16).toUpperCase().padStart(8, '0');
}

function q16float(raw: number): number {
  return parseFloat((raw / 65536).toFixed(5));
}

function q16raw(f: number): number {
  return Math.round(f * 65536);
}

const kpFloat = computed({
  get: () => q16float(config.value.kp),
  set: (val: number) => { config.value.kp = q16raw(val); }
});

const kiFloat = computed({
  get: () => q16float(config.value.ki),
  set: (val: number) => { config.value.ki = q16raw(val); }
});

const gen1Float = computed({
  get: () => q16float(config.value.sig_gen_1),
  set: (val: number) => { config.value.sig_gen_1 = q16raw(val); }
});

const gen2Float = computed({
  get: () => q16float(config.value.sig_gen_2),
  set: (val: number) => { config.value.sig_gen_2 = q16raw(val); }
});

const gen3Float = computed({
  get: () => q16float(config.value.sig_gen_3),
  set: (val: number) => { config.value.sig_gen_3 = q16raw(val); }
});

onMounted(() => {
  loadConfig();
});
</script>

<template>
  <div class="control-panel">
    <div class="panel-header">
      <h2>Controller</h2>
      <button @click="testRegister" class="btn-test">Test</button>
    </div>
    
    <div class="status-bar">
      <span :class="['status', statusMessage.includes('✓') ? 'success' : 'error']">
        {{ statusMessage || 'Ready' }}
      </span>
      <span v-if="testRegValue" class="test-value">{{ testRegValue }}</span>
    </div>

    <!-- Quick Modes Section -->
    <section class="collapsible-section">
      <div class="section-header" @click="toggleSection('quickModes')">
        <span class="toggle-icon">{{ collapsed.quickModes ? '▶' : '▼' }}</span>
        <h3>Quick Modes</h3>
      </div>
      <div v-show="!collapsed.quickModes" class="section-content">
        <div class="mode-buttons">
          <button @click="setMode('open')" class="btn-mode">Open Loop</button>
          <button @click="setMode('closed')" class="btn-mode">Closed Loop</button>
          <button @click="setMode('raw')" class="btn-mode">Raw Dist</button>
          <button @click="setMode('bypass')" class="btn-mode">DAC Out</button>
        </div>
      </div>
    </section>

    <!-- Control Settings Section -->
    <section class="collapsible-section">
      <div class="section-header" @click="toggleSection('control')">
        <span class="toggle-icon">{{ collapsed.control ? '▶' : '▼' }}</span>
        <h3>Control Settings</h3>
      </div>
      <div v-show="!collapsed.control" class="section-content">
        <div class="checkbox-grid">
          <label class="checkbox-label">
            <input type="checkbox" v-model="config.global_enable">
            Enable
          </label>
          <label class="checkbox-label">
            <input type="checkbox" v-model="config.rst_pid">
            Reset PID
          </label>
          <label class="checkbox-label">
            <input type="checkbox" v-model="config.closed_loop">
            Closed Loop
          </label>
          <label class="checkbox-label">
            <input type="checkbox" v-model="config.cic_enable">
            CIC Enable
          </label>
        </div>
      </div>
    </section>

    <!-- PID Parameters Section -->
    <section class="collapsible-section">
      <div class="section-header" @click="toggleSection('pid')">
        <span class="toggle-icon">{{ collapsed.pid ? '▶' : '▼' }}</span>
        <h3>PID Parameters</h3>
      </div>
      <div v-show="!collapsed.pid" class="section-content">
        <div class="inline-param">
          <span class="param-label">Kp</span>
          <input type="number" v-model.number="kpFloat" step="0.01">
          <span class="value-display">{{ toHex32(config.kp) }}</span>
        </div>
        <div class="inline-param">
          <span class="param-label">Ki</span>
          <input type="number" v-model.number="kiFloat" step="0.0001">
          <span class="value-display">{{ toHex32(config.ki) }}</span>
        </div>
        <div class="inline-param">
          <span class="param-label">Setpoint</span>
          <input type="number" v-model.number="config.setpoint" min="-8191" max="8191" step="1">
        </div>
      </div>
    </section>

    <!-- Signal Generators Section -->
    <section class="collapsible-section">
      <div class="section-header" @click="toggleSection('signalGen')">
        <span class="toggle-icon">{{ collapsed.signalGen ? '▶' : '▼' }}</span>
        <h3>Signal Generators</h3>
      </div>
      <div v-show="!collapsed.signalGen" class="section-content">
        <div class="inline-param">
          <span class="param-label">0.5 Hz</span>
          <input type="number" v-model.number="gen1Float" step="0.01">
          <span class="value-display">{{ toHex32(config.sig_gen_1) }}</span>
        </div>
        <div class="inline-param">
          <span class="param-label">330 Hz</span>
          <input type="number" v-model.number="gen2Float" step="0.01">
          <span class="value-display">{{ toHex32(config.sig_gen_2) }}</span>
        </div>
        <div class="inline-param">
          <span class="param-label">1.2 kHz</span>
          <input type="number" v-model.number="gen3Float" step="0.01">
          <span class="value-display">{{ toHex32(config.sig_gen_3) }}</span>
        </div>
      </div>
    </section>

    <!-- Output Selection Section -->
    <section class="collapsible-section">
      <div class="section-header" @click="toggleSection('output')">
        <span class="toggle-icon">{{ collapsed.output ? '▶' : '▼' }}</span>
        <h3>Output Selection</h3>
      </div>
      <div v-show="!collapsed.output" class="section-content">
        <div class="inline-param">
          <span class="param-label">CH1</span>
          <select v-model.number="config.output_mux_ch1" class="signal-select">
            <option :value="0">Raw Input (ADC)</option>
            <option :value="2">Original Disturbance</option>
            <option :value="3">PID Compensation</option>
            <option :value="4">Physical Output (DAC)</option>
            <option :value="5">Filtered Error (CIC)</option>
          </select>
        </div>
        <div class="inline-param">
          <span class="param-label">CH2</span>
          <select v-model.number="config.output_mux_ch2" class="signal-select">
            <option :value="0">Raw Input (ADC)</option>
            <option :value="2">Original Disturbance</option>
            <option :value="3">PID Compensation</option>
            <option :value="4">Physical Output (DAC)</option>
            <option :value="5">Filtered Error (CIC)</option>
          </select>
        </div>
      </div>
    </section>

    <div class="action-buttons">
      <button @click="loadConfig" class="btn-secondary">Reload</button>
      <button @click="applyConfig" class="btn-primary">Apply</button>
    </div>
  </div>
</template>

<style scoped>
.control-panel {
  background: #1a1a1a;
  color: #ddd;
  height: 100%;
  display: flex;
  flex-direction: column;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
  border-bottom: 2px solid #444;
  background: #111;
}

.panel-header h2 {
  margin: 0;
  color: #fff;
  font-size: 18px;
}

.collapsible-section {
  border-bottom: 1px solid #333;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  cursor: pointer;
  user-select: none;
  transition: background 0.2s;
}

.section-header:hover {
  background: #222;
}

.toggle-icon {
  color: #888;
  font-size: 12px;
  width: 12px;
  transition: transform 0.2s;
}

.section-header h3 {
  margin: 0;
  color: #aaa;
  font-size: 12px;
  font-weight: 600;
  flex: 1;
}

.section-content {
  padding: 6px 12px 8px;
  background: #1a1a1a;
}

.status-bar {
  background: #111;
  padding: 4px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  font-size: 12px;
  border-bottom: 1px solid #333;
}

.status {
  flex: 1;
}

.status.success {
  color: #4CAF50;
}

.status.error {
  color: #f44336;
}

.test-value {
  font-family: monospace;
  color: #4CAF50;
  font-weight: bold;
}

.mode-buttons {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 4px;
}

.btn-mode {
  background: #2196F3;
  color: white;
  border: none;
  padding: 6px 8px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 12px;
  transition: background 0.2s;
}

.btn-mode:hover {
  background: #1976D2;
}

.checkbox-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px 12px;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  font-size: 12px;
}

.checkbox-label input[type="checkbox"] {
  width: 14px;
  height: 14px;
  cursor: pointer;
}

.inline-param {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}

.inline-param:last-child {
  margin-bottom: 0;
}

.param-label {
  font-size: 12px;
  color: #999;
  min-width: 55px;
  flex-shrink: 0;
}

.inline-param input[type="number"] {
  background: #111;
  border: 1px solid #444;
  color: #fff;
  padding: 3px 6px;
  border-radius: 3px;
  font-size: 12px;
  width: 90px;
  flex-shrink: 0;
}

.inline-param input[type="number"]:focus {
  outline: none;
  border-color: #2196F3;
}

.value-display {
  font-size: 11px;
  color: #666;
  font-family: monospace;
  white-space: nowrap;
}

.signal-select {
  background: #111;
  border: 1px solid #444;
  color: #fff;
  padding: 3px 6px;
  border-radius: 3px;
  font-size: 12px;
  flex: 1;
  cursor: pointer;
}

.signal-select:focus {
  outline: none;
  border-color: #2196F3;
}

.action-buttons {
  display: flex;
  gap: 8px;
  padding: 8px 12px;
  background: #111;
  border-top: 1px solid #333;
}

.btn-primary, .btn-secondary, .btn-test {
  padding: 6px 14px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 12px;
  font-weight: 600;
  transition: all 0.2s;
}

.btn-primary {
  background: #4CAF50;
  color: white;
  flex: 1;
}

.btn-primary:hover {
  background: #45a049;
}

.btn-secondary {
  background: #555;
  color: white;
}

.btn-secondary:hover {
  background: #666;
}

.btn-test {
  background: #FF9800;
  color: white;
  padding: 6px 12px;
  font-size: 12px;
}

.btn-test:hover {
  background: #F57C00;
}
</style>
