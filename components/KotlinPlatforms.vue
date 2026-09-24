<script setup lang="ts">
/**
 * "Kotlin runs everywhere": the shared Kotlin core in the middle, one card per
 * target around it. Pure SVG so it scales with the 1440 canvas and prints.
 */
const targets = [
  { label: 'Android', x: 60 },
  { label: 'iOS', x: 300 },
  { label: 'Web', x: 540 },
  { label: 'Desktop', x: 780 },
  { label: 'Server', x: 1020 },
]
</script>

<template>
  <svg
    class="kotlin-platforms"
    viewBox="0 0 1240 420"
    role="img"
    aria-label="Kotlin code shared across Android, iOS, web, desktop and server"
  >
    <defs>
      <linearGradient id="kotlin-platforms-rail" x1="0" x2="1" y1="0" y2="0">
        <stop offset="0" stop-color="#7954f6" />
        <stop offset="1" stop-color="#eb55e6" />
      </linearGradient>
    </defs>

    <g v-for="target in targets" :key="target.label" class="target">
      <path :d="`M ${target.x + 80} 90 V 160`" class="leader" />
      <rect :x="target.x" y="20" width="160" height="70" rx="16" class="platform-card" />
      <text :x="target.x + 80" y="65" text-anchor="middle" class="platform-label">{{ target.label }}</text>
    </g>

    <rect x="20" y="160" width="1200" height="230" rx="28" class="core" />
    <rect x="20" y="160" width="1200" height="6" class="core-rail" />
    <text x="620" y="255" text-anchor="middle" class="core-title">Shared Kotlin code</text>
    <text x="620" y="315" text-anchor="middle" class="core-subtitle">
      JVM · Android · iOS and macOS via Kotlin/Native · JavaScript · WebAssembly
    </text>
    <text x="620" y="360" text-anchor="middle" class="core-subtitle">
      Compose Multiplatform for the UI, Ktor and Exposed on the server
    </text>
  </svg>
</template>

<style scoped>
.kotlin-platforms {
  display: block;
  width: 100%;
  max-width: 62rem;
  margin: 0.5rem auto 0;
  font-family: var(--slidev-font-sans);
}
.platform-card {
  fill: rgb(121 84 246 / 7%);
  stroke: var(--fundamentals-purple);
  stroke-width: 3;
}
.platform-label {
  fill: var(--fundamentals-ink);
  font-size: 30px;
  font-weight: 700;
}
.leader {
  stroke: var(--fundamentals-purple);
  stroke-width: 3;
  stroke-dasharray: 8 8;
}
.core {
  fill: rgb(121 84 246 / 5%);
  stroke: rgb(121 84 246 / 35%);
  stroke-width: 2;
}
.core-rail { fill: url(#kotlin-platforms-rail); }
.core-title {
  fill: var(--fundamentals-ink);
  font-size: 46px;
  font-weight: 750;
  letter-spacing: -0.03em;
}
.core-subtitle {
  fill: #665f71;
  font-size: 26px;
  font-weight: 600;
}
</style>
