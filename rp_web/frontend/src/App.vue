<script setup lang="ts">
import { ref } from 'vue'
import ScopeView from './components/ScopeView.vue'
import ControlPanel from './components/ControlPanel.vue'
import AllanDeviationView from './components/AllanDeviationView.vue'

// Store latest sample for Allan Deviation
const latestSample = ref<{ ch1Mean: number; ch2Mean: number } | null>(null);

function handleScopeSample(sample: { ch1Mean: number; ch2Mean: number }) {
  latestSample.value = sample;
}
</script>

<template>
  <div class="app-container">
    <header class="app-header">
      <h1>Red Pitaya Web Scope & Control</h1>
    </header>
    
    <div class="app-layout">
      <aside class="sidebar">
        <ControlPanel />
      </aside>
      
      <main class="main-content">
        <ScopeView @scope-sample="handleScopeSample" />
        <AllanDeviationView :latest-sample="latestSample" />
      </main>
    </div>
  </div>
</template>

<style scoped>
.app-container {
  font-family: sans-serif;
  color: #ddd;
  background: #222;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.app-header {
  background: #1a1a1a;
  padding: 15px 20px;
  border-bottom: 2px solid #444;
}

.app-header h1 {
  margin: 0;
  font-size: 24px;
  color: #fff;
}

.app-layout {
  display: flex;
  flex: 1;
  gap: 0;
  overflow: hidden;
}

.sidebar {
  width: 380px;
  background: #1a1a1a;
  border-right: 1px solid #444;
  overflow-y: auto;
  overflow-x: hidden;
}

.main-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}

@media (max-width: 768px) {
  .app-layout {
    flex-direction: column;
    overflow: visible;
  }

  .sidebar {
    width: 100%;
    border-right: none;
    border-bottom: 1px solid #444;
    overflow-y: visible;
  }

  .main-content {
    padding: 10px;
    overflow-y: visible;
  }

  .app-header h1 {
    font-size: 18px;
  }
}

/* Scrollbar styling */
.sidebar::-webkit-scrollbar {
  width: 8px;
}

.sidebar::-webkit-scrollbar-track {
  background: #1a1a1a;
}

.sidebar::-webkit-scrollbar-thumb {
  background: #444;
  border-radius: 4px;
}

.sidebar::-webkit-scrollbar-thumb:hover {
  background: #555;
}
</style>
