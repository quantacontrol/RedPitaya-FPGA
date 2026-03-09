<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import uPlot from 'uplot';
import 'uplot/dist/uPlot.min.css';

// Define emits
const emit = defineEmits<{
  'scope-sample': [{ ch1Mean: number; ch2Mean: number }]
}>();

const plotRef = ref<HTMLElement | null>(null);
const containerRef = ref<HTMLElement | null>(null);
let uplotInst: uPlot | null = null;
let timer: number | null = null;
let isPolling = false;
let resizeObserver: ResizeObserver | null = null;

// Config
const BUFFER_SIZE = 16384;
const BASE_SAMPLE_RATE = 125e6; // 125 MSPS
const BASE_TIME_PER_SAMPLE = 1 / BASE_SAMPLE_RATE; // 8ns

// Current decimation factor (updated when we change time range)
let currentDecimation = 1;
let currentTimePerSample = BASE_TIME_PER_SAMPLE; 

// Scale configuration
interface VoltageRange {
  label: string;
  max: number; // Range will be [-max, max]
  unit: string;
}

interface TimeRange {
  label: string;
  span: number; // Duration in seconds
}

const voltageRanges: VoltageRange[] = [
  { label: '±2 V',    max: 2.0,   unit: 'V' },
  { label: '±1 V',    max: 1.0,   unit: 'V' },
  { label: '±500 mV', max: 0.5,   unit: 'mV' },
  { label: '±200 mV', max: 0.2,   unit: 'mV' },
  { label: '±100 mV', max: 0.1,   unit: 'mV' },
  { label: '±50 mV',  max: 0.05,  unit: 'mV' },
  { label: '±20 mV',  max: 0.02,  unit: 'mV' },
  { label: '±10 mV',  max: 0.01,  unit: 'mV' },
];

const timeRanges: TimeRange[] = [
  { label: 'Auto (Full)', span: -1 }, // -1 indicates auto/full
  { label: '10 s',   span: 10.0 },
  { label: '5 s',    span: 5.0 },
  { label: '2 s',    span: 2.0 },
  { label: '1 s',    span: 1.0 },
  { label: '500 ms', span: 0.5 },
  { label: '200 ms', span: 0.2 },
  { label: '100 ms', span: 0.1 },
  { label: '50 ms',  span: 0.05 },
  { label: '20 ms',  span: 0.02 },
  { label: '10 ms',  span: 0.01 },
  { label: '5 ms',   span: 5e-3 },
  { label: '2 ms',   span: 2e-3 },
  { label: '1 ms',   span: 1e-3 },
  { label: '500 µs', span: 500e-6 },
  { label: '200 µs', span: 200e-6 },
  { label: '100 µs', span: 100e-6 },
];

const rangeCH1 = ref<VoltageRange>(voltageRanges[0]); // Default ±2 V
const rangeCH2 = ref<VoltageRange>(voltageRanges[0]); // Default ±2 V
const rangeTime = ref<TimeRange>(timeRanges[0]); // Default Auto

// Formatter factories
const formatters: Record<string, (u: uPlot, v: number | null) => string> = {
  'V': (u, v) => v == null ? "-" : v.toFixed(3) + " V",
  'mV': (u, v) => v == null ? "-" : (v * 1000).toFixed(1) + " mV",
  'µV': (u, v) => v == null ? "-" : (v * 1000000).toFixed(0) + " µV",
};

// Time formatter (adaptive)
function formatTime(v: number): string {
  if (v == null) return "-";
  const absV = Math.abs(v);
  if (absV === 0) return "0s";
  if (absV < 1e-6) return (v * 1e9).toFixed(0) + " ns";
  if (absV < 1e-3) return (v * 1e6).toFixed(1) + " µs";
  if (absV < 1) return (v * 1e3).toFixed(1) + " ms";
  return v.toFixed(2) + " s";
}

// Wheel zoom plugin (X-axis only for simplicity with dual Y)
function wheelZoomPlugin(opts: { factor?: number } = {}) {
  let factor = opts.factor || 0.75;
  let xMin = 0, xMax = 0, xRange = 0;

  function clamp(nRange: number, nMin: number, nMax: number, fRange: number, fMin: number, fMax: number) {
    if (nRange > fRange) {
      nMin = fMin;
      nMax = fMax;
    }
    else if (nMin < fMin) {
      nMin = fMin;
      nMax = fMin + nRange;
    }
    else if (nMax > fMax) {
      nMax = fMax;
      nMin = fMax - nRange;
    }
    return [nMin, nMax];
  }

  function updateDataRange(u: uPlot) {
    // Get the actual data range (not the current view range)
    if (u.data && u.data[0] && u.data[0].length > 0) {
      const xData = u.data[0];
      xMin = xData[0];
      xMax = xData[xData.length - 1];
      xRange = xMax - xMin;
    }
  }

  return {
    hooks: {
      ready: (u: uPlot) => {
        updateDataRange(u);

        const over = u.over;

        // wheel drag pan (middle mouse)
        over.addEventListener("mousedown", (e) => {
          if (e.button === 1) {
            e.preventDefault();
            const left0 = e.clientX;
            const scXMin0 = u.scales.x.min;
            const scXMax0 = u.scales.x.max;
            const xUnitsPerPx = u.posToVal(1, 'x') - u.posToVal(0, 'x');

            function onmove(e: MouseEvent) {
              e.preventDefault();
              const left1 = e.clientX;
              const dx = xUnitsPerPx * (left1 - left0);
              u.setScale('x', {
                min: scXMin0 - dx,
                max: scXMax0 - dx,
              });
            }

            function onup() {
              document.removeEventListener("mousemove", onmove);
              document.removeEventListener("mouseup", onup);
            }

            document.addEventListener("mousemove", onmove);
            document.addEventListener("mouseup", onup);
          }
        });

        // wheel scroll zoom
        over.addEventListener("wheel", (e) => {
          e.preventDefault();
          
          // Update data range before zooming
          updateDataRange(u);
          
          const rect = over.getBoundingClientRect();
          const { left } = u.cursor;
          const leftPct = left / rect.width;
          const xVal = u.posToVal(left, "x");
          const oxRange = u.scales.x.max - u.scales.x.min;

          const nxRange = e.deltaY < 0 ? oxRange * factor : oxRange / factor;
          const nxMin = xVal - leftPct * nxRange;
          const nxMax = nxMin + nxRange;
          const [clampedNxMin, clampedNxMax] = clamp(nxRange, nxMin, nxMax, xRange, xMin, xMax);

          u.batch(() => {
            u.setScale("x", {
              min: clampedNxMin,
              max: clampedNxMax,
            });
          });
        });
      },
      setData: (u: uPlot) => {
        // Update data range whenever new data arrives
        updateDataRange(u);
      },
    },
  };
}

function getPlotOptions(): uPlot.Options {
  const r1 = rangeCH1.value;
  const r2 = rangeCH2.value;

  // Use formatter based on the unit of the range (V -> use 'V' formatter, mV -> use 'mV' formatter)
  // The raw data is always in Volts.
  const formatValue1 = (u: uPlot, v: number | null) => {
    if (v == null) return "-";
    if (r1.unit === 'mV') return (v * 1000).toFixed(1) + " mV";
    return v.toFixed(3) + " V";
  };
  
  const formatValue2 = (u: uPlot, v: number | null) => {
    if (v == null) return "-";
    if (r2.unit === 'mV') return (v * 1000).toFixed(1) + " mV";
    return v.toFixed(3) + " V";
  };

  const width = containerRef.value?.clientWidth || 800;

  return {
    title: "Real-time Scope",
    width,
    height: Math.max(250, Math.round(width * 0.5)),
    plugins: [
      wheelZoomPlugin({ factor: 0.75 })
    ],
    series: [
      {
        // X-axis (Time)
        label: "Time",
        value: (u, v) => formatTime(v),
      },
      {
        // Channel 1
        stroke: "yellow",
        label: "CH1",
        scale: "ch1",
        value: formatValue1,
        width: 2,
      },
      {
        // Channel 2
        stroke: "cyan",
        label: "CH2",
        scale: "ch2",
        value: formatValue2,
        width: 2,
      }
    ],
    axes: [
      {
        // X Axis
        scale: 'x',
        values: (u, vals) => vals.map(v => formatTime(v)),
        grid: { show: true, stroke: '#333' },
        ticks: { show: true, stroke: '#333' },
      },
      {
        // CH1 Axis (Left)
        scale: 'ch1',
        stroke: 'yellow',
        side: 3, // Left
        grid: { show: true, stroke: '#333' },
        ticks: { show: true, stroke: '#333' },
        values: (u, vals) => vals.map(v => {
            if (r1.unit === 'mV') return (v * 1000).toFixed(0);
            return v.toFixed(1);
        }),
        label: `CH1 (${r1.unit})`,
        labelSize: 30,
      },
      {
        // CH2 Axis (Right)
        scale: 'ch2',
        stroke: 'cyan',
        side: 1, // Right
        grid: { show: false }, // Avoid grid clutter
        ticks: { show: true, stroke: '#333' },
        values: (u, vals) => vals.map(v => {
            if (r2.unit === 'mV') return (v * 1000).toFixed(0);
            return v.toFixed(1);
        }),
        label: `CH2 (${r2.unit})`,
        labelSize: 30,
      }
    ],
    scales: {
      x: {
        time: false,
        auto: rangeTime.value.span === -1, // Only auto if "Auto" is selected
      },
      ch1: {
        auto: false,
        range: [-r1.max, r1.max],
      },
      ch2: {
        auto: false,
        range: [-r2.max, r2.max],
      }
    }
  };
}

function initPlot() {
  if (!plotRef.value) return;

  // Destroy existing instance if any
  if (uplotInst) {
    uplotInst.destroy();
  }

  const opts = getPlotOptions();
  uplotInst = new uPlot(opts, [[], [], []], plotRef.value);

  // Fixed time ranges will be set when data arrives (in fetchScopeData)
  // Don't set here because we don't know the data range yet
}

// Calculate optimal decimation for desired time span
async function updateDecimation() {
  let decimation = 1;
  
  if (rangeTime.value.span !== -1) {
    // User wants to see 'span' seconds of data
    // We have BUFFER_SIZE samples
    // Required sample period = span / BUFFER_SIZE
    const requiredSamplePeriod = rangeTime.value.span / BUFFER_SIZE;
    
    // decimation = requiredSamplePeriod / BASE_TIME_PER_SAMPLE
    const idealDecimation = requiredSamplePeriod / BASE_TIME_PER_SAMPLE;
    
    // Round to nearest power of 2 for Red Pitaya hardware
    // Valid decimation: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, ...
    if (idealDecimation <= 1) {
      decimation = 1;
    } else {
      // Find nearest power of 2
      const log2 = Math.log2(idealDecimation);
      decimation = Math.pow(2, Math.round(log2));
      
      // Clamp to reasonable range (1 to 65536)
      decimation = Math.max(1, Math.min(65536, decimation));
    }
    
    console.log(`Time span: ${rangeTime.value.span}s → Ideal decimation: ${idealDecimation.toFixed(1)} → Actual: ${decimation}`);
  } else {
    console.log('Auto mode: decimation = 1');
  }
  
  if (decimation !== currentDecimation) {
    currentDecimation = decimation;
    currentTimePerSample = BASE_TIME_PER_SAMPLE * decimation;
    
    const sampleRate = BASE_SAMPLE_RATE / decimation;
    const actualTimeSpan = BUFFER_SIZE * currentTimePerSample;
    
    console.log(`Decimation: ${decimation}`);
    console.log(`Sample rate: ${(sampleRate / 1e3).toFixed(2)} kSPS`);
    console.log(`Time per sample: ${(currentTimePerSample * 1e6).toFixed(3)} µs`);
    console.log(`Actual time span: ${(actualTimeSpan * 1e3).toFixed(2)} ms`);
    
    // Send config to backend
    try {
      await fetch('/api/v1/scope/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          decimation: decimation,
          trigger_level: 0.0,
          trigger_source: 0
        })
      });
      console.log('✓ Decimation configured successfully');
    } catch (e) {
      console.error('Failed to set decimation:', e);
    }
  }
}

// Watch for range changes and update chart dynamically without destroying it
watch([rangeCH1, rangeCH2, rangeTime], async () => {
  await updateDecimation();
  
  if (uplotInst) {
    const r1 = rangeCH1.value;
    const r2 = rangeCH2.value;

    uplotInst.batch(() => {
      // Update Y-axis scales
      uplotInst!.setScale('ch1', { min: -r1.max, max: r1.max });
      uplotInst!.setScale('ch2', { min: -r2.max, max: r2.max });
      
      // Note: X-axis scale is automatically updated in fetchScopeData 
      // based on rangeTime.value.span

      // We need to re-init axes formatting since unit might have changed (e.g. V -> mV)
      // Since uPlot doesn't support deep axis reconfiguration dynamically easily, 
      // we only avoid full re-init if units are the same.
      // But for simplicity in this fix and to avoid flashing, we accept that 
      // the axis labels might not perfectly update unit text without re-init.
      // A better way is to update the axes array if uPlot allows, but setScale is usually enough.
    });
    
    // To properly update labels and formatters, we must recreate, but we can do it smoothly
    // Actually, uPlot requires destroy/recreate to change axis labels/formatters.
    // So to fix the "flash", we can just NOT clear the data on recreate.
    const currentData = uplotInst.data;
    uplotInst.destroy();
    const opts = getPlotOptions();
    uplotInst = new uPlot(opts, currentData, plotRef.value!);
  } else {
    initPlot();
  }
});

onMounted(async () => {
  await updateDecimation();
  initPlot();
  startPolling();

  if (containerRef.value) {
    resizeObserver = new ResizeObserver(() => {
      if (uplotInst && containerRef.value) {
        const w = containerRef.value.clientWidth;
        uplotInst.setSize({ width: w, height: Math.max(250, Math.round(w * 0.5)) });
      }
    });
    resizeObserver.observe(containerRef.value);
  }
});

onUnmounted(() => {
  isPolling = false;
  if (timer !== null) {
    window.clearTimeout(timer);
  }
  uplotInst?.destroy();
  resizeObserver?.disconnect();
});

async function fetchScopeData() {
  if (!isPolling) return;
  
  try {
    const response = await fetch('/api/v1/scope/data');
    if (!response.ok) throw new Error('Network error');

    const buffer = await response.arrayBuffer();
    const float32 = new Float32Array(buffer);

    // Assume data is [CH1... | CH2...]
    const ch1 = float32.subarray(0, BUFFER_SIZE);
    const ch2 = float32.subarray(BUFFER_SIZE, BUFFER_SIZE * 2);

    // Calculate means for Allan Deviation
    let ch1Sum = 0;
    let ch2Sum = 0;
    for (let i = 0; i < BUFFER_SIZE; i++) {
      ch1Sum += ch1[i];
      ch2Sum += ch2[i];
    }
    const ch1Mean = ch1Sum / BUFFER_SIZE;
    const ch2Mean = ch2Sum / BUFFER_SIZE;
    
    // Emit mean values for Allan Deviation calculation
    emit('scope-sample', { ch1Mean, ch2Mean });

    // Generate X axis (Time) using current decimation
    const x = new Float32Array(BUFFER_SIZE);
    // Align 0 to the middle of the buffer since we trigger in the middle
    const triggerIndex = BUFFER_SIZE / 2;
    for (let i = 0; i < BUFFER_SIZE; i++) {
        x[i] = (i - triggerIndex) * currentTimePerSample;
    }

    // Update plot data
    uplotInst?.setData([x as any, ch1 as any, ch2 as any]);

    // If in fixed time range mode (not Auto), show the most recent portion of data
    if (rangeTime.value.span !== -1) {
      // For centered trigger, data spans from -span/2 to span/2 around 0
      const span = rangeTime.value.span;
      uplotInst?.setScale('x', { min: -span/2, max: span/2 });
    } else {
      // If Auto, show full buffer from start to end (around trigger 0)
      const dataMin = x[0];
      const dataMax = x[x.length - 1];
      uplotInst?.setScale('x', { min: dataMin, max: dataMax });
    }

  } catch (e) {
    console.error("Fetch failed", e);
  } finally {
    if (isPolling) {
      // Wait for 50ms before asking for the next frame
      timer = window.setTimeout(fetchScopeData, 50);
    }
  }
}

function startPolling() {
  if (!isPolling) {
    isPolling = true;
    fetchScopeData();
  }
}
</script>

<template>
  <div class="scope-container">
    <div class="controls">
      <div class="channel-control">
        <label class="control-label ch1-label">CH1 Range:</label>
        <select v-model="rangeCH1" class="unit-select">
          <option v-for="r in voltageRanges" :key="r.label" :value="r">
            {{ r.label }}
          </option>
        </select>
      </div>

      <div class="channel-control">
        <label class="control-label ch2-label">CH2 Range:</label>
        <select v-model="rangeCH2" class="unit-select">
          <option v-for="r in voltageRanges" :key="r.label" :value="r">
            {{ r.label }}
          </option>
        </select>
      </div>

      <div class="channel-control">
        <label class="control-label time-label">Time Base:</label>
        <select v-model="rangeTime" class="unit-select">
          <option v-for="r in timeRanges" :key="r.label" :value="r">
            {{ r.label }}
          </option>
        </select>
      </div>
    </div>
    <div ref="containerRef" class="plot-wrapper">
      <div ref="plotRef" class="plot-area"></div>
    </div>
  </div>
</template>

<style scoped>
.scope-container {
  background: #111;
  padding: 20px;
  border-radius: 8px;
  box-shadow: 0 0 10px rgba(0,0,0,0.5);
}

@media (max-width: 768px) {
  .scope-container {
    padding: 10px;
    border-radius: 4px;
  }
}

.controls {
  margin-bottom: 15px;
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.plot-wrapper {
  width: 100%;
  overflow: hidden;
}

.channel-control {
  display: flex;
  align-items: center;
  gap: 10px;
}

.control-label {
  color: #fff;
  font-weight: bold;
}

.ch1-label {
  color: yellow;
}

.ch2-label {
  color: cyan;
}

.time-label {
  color: #aaa;
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

.plot-area {
  background: black;
}
</style>
