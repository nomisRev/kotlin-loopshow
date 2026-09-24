<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { createClicksContextBase } from '@slidev/client/composables/useClicks.ts'
import { useNav } from '@slidev/client/composables/useNav.ts'
import NoteStatic from '@slidev/client/internals/NoteStatic.vue'
import SlideContainer from '@slidev/client/internals/SlideContainer.vue'
import SlidesShow from '@slidev/client/internals/SlidesShow.vue'
import SlideWrapper from '@slidev/client/internals/SlideWrapper.vue'

const {
  clicksContext,
  currentSlideNo,
  currentSlideRoute,
  go,
  hasNext,
  nextRoute,
  nextSlide,
  prevSlide,
  slides,
} = useNav()

const previewClicks = ref(0)
const previewContext = computed(() => createClicksContextBase(
  previewClicks,
  nextRoute.value?.meta.slide?.frontmatter.clicksStart ?? 0,
  nextRoute.value?.meta.clicks,
))

const previewRoute = computed(() => {
  if (!hasNext.value)
    return undefined
  if (clicksContext.value.current < clicksContext.value.total)
    return currentSlideRoute.value
  return nextRoute.value
})

async function navigate(event: MouseEvent) {
  if ((event.target as HTMLElement).closest('a, button, input, textarea, select'))
    return

  if (event.clientX < window.innerWidth / 2) {
    if (clicksContext.value.current > clicksContext.value.clicksStart)
      await go(currentSlideNo.value, clicksContext.value.current - 1)
    else
      await prevSlide(true)
  }
  else if (clicksContext.value.current < clicksContext.value.total) {
    // Reveal the next v-click step without leaving the current slide.
    await go(currentSlideNo.value, clicksContext.value.current + 1)
  }
  else {
    await nextSlide()
  }
}

watch(previewRoute, () => {
  previewClicks.value = previewRoute.value === currentSlideRoute.value
    ? clicksContext.value.current + 1
    : 0
}, { immediate: true })
</script>

<template>
  <main class="remote-control" aria-label="Tap the left half to go back and the right half to advance" @click="navigate">
    <!-- Mount the current slide so Slidev registers its v-click steps. -->
    <SlideContainer class="current-clicks-context" aria-hidden="true">
      <SlidesShow render-context="presenter" />
    </SlideContainer>

    <section class="next-slide" aria-label="Upcoming slide preview">
      <SlideContainer v-if="previewRoute" class="preview">
        <SlideWrapper
          :key="`${previewRoute.no}-${previewClicks}`"
          :route="previewRoute"
          :clicks-context="previewContext"
          render-context="previewNext"
        />
      </SlideContainer>
      <div v-else class="end-of-deck">End of presentation</div>
    </section>

    <div class="slide-count" aria-live="polite">{{ currentSlideNo }} / {{ slides.length }}</div>

    <section class="speaker-notes" aria-label="Speaker notes">
      <NoteStatic :no="currentSlideNo" :clicks-context="clicksContext" class="notes-content" />
    </section>
  </main>
</template>

<style scoped>
.remote-control {
  box-sizing: border-box;
  min-height: 100dvh;
  color: #1d1d1d;
  background: #f9fafb;
  display: grid;
  grid-template-rows: minmax(14rem, 43dvh) minmax(0, 1fr);
  cursor: pointer;
  font-family: 'JetBrains Sans', system-ui, sans-serif;
}

.current-clicks-context {
  position: fixed;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
  overflow: hidden;
}

.next-slide {
  position: relative;
  min-height: 0;
  overflow: hidden;
  background: #fff;
}

.preview {
  width: 100%;
  height: 100%;
}

.end-of-deck {
  height: 100%;
  display: grid;
  place-items: center;
  color: #767676;
  font-size: 1.25rem;
}

.slide-count {
  position: fixed;
  z-index: 1;
  top: calc(43dvh - 1.15rem);
  left: 50%;
  transform: translateX(-50%);
  padding: 0.25rem 0.55rem;
  border-radius: 999px;
  background: rgb(249 250 251 / 88%);
  color: #666;
  font-size: 0.8rem;
  pointer-events: none;
}

.speaker-notes {
  min-height: 0;
  overflow: auto;
  padding: 1.25rem max(1.25rem, env(safe-area-inset-right)) calc(1.25rem + env(safe-area-inset-bottom)) max(1.25rem, env(safe-area-inset-left));
}

:deep(.notes-content) { font-size: 1rem; line-height: 1.45; }
:deep(.notes-content > :first-child) { margin-top: 0; }

@media (min-width: 700px) {
  .remote-control {
    max-width: 31rem;
    margin: 0 auto;
    border-inline: 2px dotted #c9c9c9;
    box-shadow: 0 0 2rem rgb(0 0 0 / 12%);
  }
}
</style>
