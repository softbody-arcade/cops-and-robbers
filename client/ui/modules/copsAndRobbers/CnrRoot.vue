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
  --cnr-muted: var(--bng-cool-gray-100);
  --cnr-card: rgba(var(--bng-off-black-rgb), 0.8);
  --cnr-row: rgba(var(--bng-off-black-rgb), 0.7);
  --cnr-shadow-strong: 0 0.0625rem 0.125rem rgba(var(--bng-off-black-rgb), 0.9), 0 0 0.5rem rgba(var(--bng-off-black-rgb), 0.75);
  --cnr-display: "Overpass", var(--fnt-defs);
  color: var(--cnr-text);
  font-family: var(--fnt-defs);
}
.cnr-fit-box {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  overflow: hidden;
  pointer-events: none;
  --bng-icon-color: currentColor;
}
.cnr-root.cnr-hud-text {
  font-family: var(--cnr-display);
  text-shadow: var(--cnr-shadow-strong);
}
.cnr-fit-content {
  flex: none;
  box-sizing: border-box;
  max-width: calc(100% / var(--cnr-fit-growth, 1));
}
.cnr-root .cnr-hud-title {
  font-size: 2.5rem;
  font-style: italic;
  font-weight: 900;
  line-height: 1.1;
  letter-spacing: 0.01em;
}
.cnr-root .cnr-mono {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
}
.cnr-root .cnr-tone-runner {
  color: var(--cnr-runner-text);
}
.cnr-root .cnr-tone-cop {
  color: var(--cnr-cop-text);
}
.cnr-root .cnr-tone-warn {
  color: var(--cnr-warn);
}
.cnr-root .cnr-tone-good {
  color: var(--cnr-good);
}
.cnr-root .cnr-btn {
  font-family: var(--cnr-display);
  font-weight: 700;
  --bng-button-margin: 0;
  --bng-content-align: center;
}
.cnr-root .cnr-swatch {
  display: inline-block;
  flex: 0 0 auto;
  width: 1rem;
  height: 1rem;
  border-radius: var(--bng-corners-1);
  box-shadow: 0 0 0 0.125rem var(--cnr-muted);
}
.cnr-root .cnr-btn .cnr-swatch {
  margin-right: 0.5rem;
}
.cnr-root .cnr-swatch.empty {
  background: transparent;
}
</style>
