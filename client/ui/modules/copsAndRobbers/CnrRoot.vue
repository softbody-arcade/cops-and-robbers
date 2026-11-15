<template>
  <div class="cnr-root"><slot /></div>
</template>

<style>
.cnr-root {
  --cnr-runner: var(--bng-add-red-500);
  --cnr-runner-text: var(--bng-add-red-400);
  --cnr-cop: var(--bng-add-blue-500);
  --cnr-cop-text: var(--bng-add-blue-400);
  --cnr-warn: var(--bng-ter-yellow-200);
  --cnr-good: var(--bng-add-green-400);
  --cnr-accent: var(--bng-orange-b400);
  --cnr-main: var(--bng-orange-500);
  --cnr-me: var(--bng-orange-300);
  --cnr-text: var(--bng-off-white);
  --cnr-muted: var(--bng-cool-gray-300);
  --cnr-card: rgba(var(--bng-off-black-rgb), 0.6);
  --cnr-row: rgba(var(--bng-off-black-rgb), 0.5);
  --cnr-shadow: 0 0 0.25rem rgba(var(--bng-off-black-rgb), 0.6);
  --cnr-display: "Overpass", var(--fnt-defs);
  color: var(--cnr-text);
  font-family: var(--fnt-defs);
}
</style>
