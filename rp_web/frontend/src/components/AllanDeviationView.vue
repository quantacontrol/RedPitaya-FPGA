<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import uPlot from 'uplot';
import 'uplot/dist/uPlot.min.css';

// Props
interface Props {
  latestSample?: { ch1Mean: number; ch2Mean: number } | null;
}
const props = defineProps<Props>();

// Component state
interface Measurement {
  timestamp: number; // milliseconds
  ch1: number;       // volts
  ch2: number;       // volts
}

const plotRef = ref<HTMLElement | null>(null);
const containerRef = ref<HTMLElement | null>(null);
let uplotInst: uPlot | null = null;
let computeTimer: number = 0;
let resizeObserver: ResizeObserver | null = null;

const measurements = ref<Measurement[]>([]);
const maxMeasurements = 20000; // ~16 minutes @ 20 FPS

// UI Controls
type ChannelSelection = 'ch1' | 'ch2' | 'both';
const selectedChannel = ref<ChannelSelection>('both');
const sampleCount = ref(0);
const totalDuration = ref(0); // seconds

// Watch for new samples
watch(() => props.latestSample, (newSample) => {
  if (newSample) {
    addMeasurement(newSample.ch1Mean, newSample.ch2Mean);
  }
});

function addMeasurement(ch1: number, ch2: number) {
  measurements.value.push({
    timestamp: Date.now(),
    ch1,
    ch2
  });
  
  // Ring buffer: remove oldest if exceeds capacity
  if (measurements.value.length > maxMeasurements) {
    measurements.value.shift();
  }
  
  updateStats();
}

function updateStats() {
  sampleCount.value = measurements.value.length;
  if (measurements.value.length >= 2) {
    const first = measurements.value[0].timestamp;
    const last = measurements.value[measurements.value.length - 1].timestamp;
    totalDuration.value = (last - first) / 1000; // convert to seconds
  } else {
    totalDuration.value = 0;
  }
}

function resetData() {
  measurements.value = [];
  sampleCount.value = 0;
  totalDuration.value = 0;
  if (uplotInst) {
    uplotInst.setData([[], [], []]);
  }
}

// Estimate average measurement interval (tau0)
function estimateInterval(data: Measurement[]): number {
  if (data.length < 2) return 0.05; // default 50ms
  
  // Use recent 100 samples to estimate interval
  const recent = data.slice(-Math.min(100, data.length));
  if (recent.length < 2) return 0.05;
  
  let totalInterval = 0;
  for (let i = 1; i < recent.length; i++) {
    totalInterval += (recent[i].timestamp - recent[i-1].timestamp);
  }
  return (totalInterval / (recent.length - 1)) / 1000; // convert to seconds
}

// Generate logarithmically-spaced tau values
function generateLogTaus(tau0: number, totalTime: number): number[] {
  const tauMin = tau0;
  const tauMax = totalTime / 3; // statistical rule of thumb
  
  if (tauMax <= tauMin) return [tau0];
  
  const numPoints = 40;
  const logMin = Math.log10(tauMin);
  const logMax = Math.log10(tauMax);
  const step = (logMax - logMin) / (numPoints - 1);
  
  const taus: number[] = [];
  for (let i = 0; i < numPoints; i++) {
    taus.push(Math.pow(10, logMin + i * step));
  }
  return taus;
}

// Compute overlapping Allan Deviation for a specific tau
function computeAdevForTau(data: number[], tau: number, tau0: number): number | null {
  const N = data.length;
  const m = Math.round(tau / tau0);
  
  if (m < 1 || 2 * m >= N) return null;
  
  let sum = 0;
  for (let i = 0; i < N - 2 * m; i++) {
    const diff = data[i + 2 * m] - 2 * data[i + m] + data[i];
    sum += diff * diff;
  }
  
  const loopCount = N - 2 * m;
  const variance = sum / (2 * m * m * loopCount);
  return Math.sqrt(variance);
}

// Main ADEV computation
interface AdevResult {
  tau: number[];
  adev_ch1: number[];
  adev_ch2: number[];
}

function computeAllanDeviation(): AdevResult | null {
  const data = measurements.value;
  if (data.length < 10) return null;
  
  const N = data.length;
  const tau0 = estimateInterval(data);
  const totalTime = (data[N - 1].timestamp - data[0].timestamp) / 1000;
  
  const taus = generateLogTaus(tau0, totalTime);
  const adev_ch1: number[] = [];
  const adev_ch2: number[] = [];
  const validTaus: number[] = [];
  
  // Extract channel data
  const ch1Data = data.map(m => m.ch1);
  const ch2Data = data.map(m => m.ch2);
  
  for (const tau of taus) {
    const adev1 = computeAdevForTau(ch1Data, tau, tau0);
    const adev2 = computeAdevForTau(ch2Data, tau, tau0);
    
    if (adev1 !== null && adev2 !== null && !isNaN(adev1) && !isNaN(adev2) && adev1 > 0 && adev2 > 0) {
      validTaus.push(tau);
      adev_ch1.push(adev1);
      adev_ch2.push(adev2);
    }
  }
  
  return { tau: validTaus, adev_ch1, adev_ch2 };
}

// Format values for log scale display
function formatLogValue(v: number | null): string {
  if (v == null) return "-";
  if (v === 0) return "0";
  
  const absV = Math.abs(v);
  if (absV >= 1) return v.toFixed(1);
  if (absV >= 0.01) return v.toFixed(3);
  if (absV >= 0.001) return v.toFixed(4);
  return v.toExponential(1);
}

// Format for axis ticks (more compact)
function formatAxisTick(v: number | null): string {
  if (v == null || v === 0) return "0";
  
  const absV = Math.abs(v);
  const sign = v < 0 ? '-' : '';
  
  // For log scale, use powers of 10 notation
  if (absV >= 1) {
    return sign + absV.toFixed(0);
  } else if (absV >= 0.01) {
    return sign + absV.toFixed(2);
  } else {
    // Scientific notation: 1e-5 format
    const exp = Math.floor(Math.log10(absV));
    const mantissa = absV / Math.pow(10, exp);
    if (Math.abs(mantissa - 1) < 0.01) {
      return sign + '1e' + exp;
    }
    return sign + mantissa.toFixed(1) + 'e' + exp;
  }
}

function getPlotOptions(): uPlot.Options {
  const width = containerRef.value?.clientWidth || 800;
  return {
    title: "Allan Deviation",
    width,
    height: Math.max(200, Math.round(width * 0.4)),
    series: [
      {
        label: "τ",
        value: (u, v) => v == null ? "-" : formatLogValue(v) + " s",
      },
      {
        stroke: "yellow",
        label: "CH1 σ(τ)",
        show: selectedChannel.value === 'ch1' || selectedChannel.value === 'both',
        width: 2,
        points: { show: true, size: 4 },
        value: (u, v) => v == null ? "-" : formatLogValue(v) + " V",
      },
      {
        stroke: "cyan",
        label: "CH2 σ(τ)",
        show: selectedChannel.value === 'ch2' || selectedChannel.value === 'both',
        width: 2,
        points: { show: true, size: 4 },
        value: (u, v) => v == null ? "-" : formatLogValue(v) + " V",
      }
    ],
    axes: [
      {
        scale: 'x',
        label: 'τ (Averaging Time, seconds)',
        labelSize: 30,
        labelFont: 'bold 14px sans-serif',
        stroke: '#aaa',
        grid: { show: true, stroke: '#333' },
        ticks: { show: true, stroke: '#666', width: 1 },
        values: (u, vals) => vals.map(v => {
          if (v == null) return '';
          return formatAxisTick(v) + ' s';
        }),
        font: '11px sans-serif',
        gap: 5,
        size: 50,
      },
      {
        scale: 'y',
        label: 'Allan Deviation σ(τ) (Volts)',
        labelSize: 30,
        labelFont: 'bold 14px sans-serif',
        stroke: '#aaa',
        side: 3, // left
        grid: { show: true, stroke: '#333' },
        ticks: { show: true, stroke: '#666', width: 1 },
        values: (u, vals) => vals.map(v => {
          if (v == null) return '';
          return formatAxisTick(v) + ' V';
        }),
        font: '10px sans-serif',
        gap: 3,
        size: 70,
      }
    ],
    scales: {
      x: {
        distr: 3, // log distribution
        log: 10,  // base 10
      },
      y: {
        distr: 3, // log distribution
        log: 10,  // base 10
      }
    },
    cursor: {
      drag: {
        x: false,
        y: false,
      }
    }
  };
}

function initPlot() {
  if (!plotRef.value) return;
  
  if (uplotInst) {
    uplotInst.destroy();
  }
  
  const opts = getPlotOptions();
  uplotInst = new uPlot(opts, [[], [], []], plotRef.value);
}

function updatePlot() {
  const result = computeAllanDeviation();
  if (!result || result.tau.length === 0) {
    return;
  }
  
  if (!uplotInst) {
    initPlot();
  }
  
  // Update data
  uplotInst?.setData([
    result.tau,
    result.adev_ch1,
    result.adev_ch2
  ]);
}

// Watch channel selection changes
watch(selectedChannel, () => {
  initPlot();
  updatePlot();
});

onMounted(() => {
  initPlot();

  // Recompute ADEV every second
  computeTimer = setInterval(() => {
    updatePlot();
  }, 1000);

  if (containerRef.value) {
    resizeObserver = new ResizeObserver(() => {
      if (uplotInst && containerRef.value) {
        const w = containerRef.value.clientWidth;
        uplotInst.setSize({ width: w, height: Math.max(200, Math.round(w * 0.4)) });
      }
    });
    resizeObserver.observe(containerRef.value);
  }
});

onUnmounted(() => {
  clearInterval(computeTimer);
  uplotInst?.destroy();
  resizeObserver?.disconnect();
});
</script>

<template>
  <div class="adev-container">
    <div class="controls">
      <div class="stats">
        <span class="stat-label">Samples:</span>
        <span class="stat-value">{{ sampleCount }}</span>
        <span class="stat-label">Duration:</span>
        <span class="stat-value">{{ totalDuration.toFixed(1) }}s</span>
      </div>
      
      <div class="channel-control">
        <label class="control-label">Display:</label>
        <select v-model="selectedChannel" class="unit-select">
          <option value="both">Both Channels</option>
          <option value="ch1">CH1 Only</option>
          <option value="ch2">CH2 Only</option>
        </select>
      </div>
      
      <button @click="resetData" class="reset-btn">Reset</button>
    </div>
    
    <div ref="containerRef" class="plot-wrapper">
      <div ref="plotRef" class="plot-area"></div>
    </div>
  </div>
</template>

<style scoped>
.adev-container {
  background: #111;
  padding: 20px;
  border-radius: 8px;
  box-shadow: 0 0 10px rgba(0,0,0,0.5);
  margin-top: 20px;
}

@media (max-width: 768px) {
  .adev-container {
    padding: 10px;
    border-radius: 4px;
    margin-top: 10px;
  }
}

.controls {
  margin-bottom: 15px;
  display: flex;
  align-items: center;
  gap: 20px;
  flex-wrap: wrap;
}

.stats {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 12px;
  background: #222;
  border-radius: 4px;
  border: 1px solid #444;
}

.stat-label {
  color: #888;
  font-size: 13px;
}

.stat-value {
  color: #fff;
  font-weight: bold;
  font-size: 14px;
}

.channel-control {
  display: flex;
  align-items: center;
  gap: 10px;
}

.control-label {
  color: #aaa;
  font-weight: bold;
}

.unit-select {
  background: #222;
  color: #fff;
  border: 1px solid #444;
  padding: 6px 12px;
  border-radius: 4px;
  font-size: 14px;
  cursor: pointer;
  outline: none;
}

.unit-select:hover {
  border-color: #666;
}

.unit-select:focus {
  border-color: #888;
  box-shadow: 0 0 0 2px rgba(255,255,255,0.1);
}

.reset-btn {
  background: #d44;
  color: white;
  border: none;
  padding: 7px 16px;
  border-radius: 4px;
  font-size: 14px;
  font-weight: bold;
  cursor: pointer;
  transition: background 0.2s;
}

.reset-btn:hover {
  background: #e55;
}

.reset-btn:active {
  background: #c33;
}

.plot-wrapper {
  width: 100%;
  overflow: hidden;
}

.plot-area {
  background: black;
}
</style>
