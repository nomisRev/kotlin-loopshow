<script setup lang="ts">
/**
 * Adoption numbers from "The State of Kotlin in 2026": a column of headline
 * stats beside one horizontal bar chart. Bars grow in when the slide mounts,
 * so the auto-advancing booth loop gets motion without click builds.
 */
defineProps<{
  stats: { value: string, label: string }[]
  bars: { label: string, value: number }[]
  title: string
  highlight?: number
}>()
</script>

<template>
  <div class="adoption-chart">
    <ul class="stats">
      <li v-for="stat in stats" :key="stat.label">
        <strong>{{ stat.value }}</strong>
        <span>{{ stat.label }}</span>
      </li>
    </ul>

    <figure class="bars" role="img" :aria-label="`${title}: ${bars.map(b => `${b.label} ${b.value}%`).join(', ')}`">
      <figcaption>{{ title }}</figcaption>
      <div
        v-for="(bar, i) in bars"
        :key="bar.label"
        class="row"
        :class="{ highlight: highlight === undefined || i >= highlight }"
        :style="{ '--value': bar.value, '--delay': `${i * 90}ms` }"
      >
        <span class="label">{{ bar.label }}</span>
        <span class="track"><span class="fill" /></span>
        <span class="value">{{ bar.value }}%</span>
      </div>
    </figure>
  </div>
</template>

<style scoped>
.adoption-chart {
  display: grid;
  grid-template-columns: 17rem minmax(0, 1fr);
  gap: 1.5rem 3.5rem;
  margin-top: 1.25rem;
}
.stats {
  display: grid;
  align-content: start;
  gap: 1.4rem;
  margin: 0;
  padding: 0;
  list-style: none;
}
.stats li {
  display: grid;
  margin: 0;
  padding-left: 1rem;
  border-left: 0.28rem solid var(--fundamentals-purple);
  border-image: linear-gradient(180deg, #7954f6, #d74ae5) 1;
}
.stats strong {
  background: linear-gradient(120deg, var(--fundamentals-purple), var(--fundamentals-pink));
  background-clip: text;
  -webkit-background-clip: text;
  color: transparent;
  font-size: 3.4rem;
  font-weight: 800;
  letter-spacing: -0.04em;
  line-height: 1;
}
.stats span {
  color: #665f71;
  font-size: 1.15rem;
  font-weight: 650;
  line-height: 1.3;
}
.bars {
  display: grid;
  align-content: start;
  gap: 0.85rem;
  margin: 0;
}
.bars figcaption {
  margin-bottom: 0.4rem;
  color: var(--fundamentals-ink);
  font-size: 1.35rem;
  font-weight: 750;
}
.row {
  display: grid;
  grid-template-columns: 11rem minmax(0, 1fr) 4.5rem;
  align-items: center;
  gap: 1rem;
  font-size: 1.35rem;
  font-weight: 680;
}
.label { color: var(--fundamentals-ink); }
.track {
  height: 2.1rem;
  border-radius: 0.5rem;
  background: rgb(121 84 246 / 7%);
  overflow: hidden;
}
.fill {
  display: block;
  height: 100%;
  width: calc(var(--value) * 1%);
  border-radius: 0.5rem;
  background: rgb(121 84 246 / 35%);
  transform-origin: left;
  animation: grow 900ms cubic-bezier(0.22, 0.61, 0.36, 1) var(--delay) both;
}
.row.highlight .fill {
  background: linear-gradient(90deg, var(--fundamentals-purple), var(--fundamentals-pink));
}
.value {
  color: #665f71;
  font-family: var(--slidev-font-mono);
  font-size: 1.2rem;
  text-align: right;
}
.row.highlight .value {
  color: var(--fundamentals-ink);
  font-weight: 800;
}
html.dark .stats span,
html.dark .value { color: #b9b2c4; }
@keyframes grow {
  from { transform: scaleX(0); }
  to { transform: scaleX(1); }
}
@media print {
  .fill { animation: none; }
}
</style>
