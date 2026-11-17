<template>
  <CnrCard class="how-to-play" title="How to play" closable @close="emit('close')">
    <BngTabs v-model="tab" :show-arrows="false">
      <div tab-heading="Basics" class="htp-tab">
        <p>
          One player is the <b class="runner">runner</b>, everyone else is a <b class="cop">cop</b>. Everyone drives the same car.
          The runner's score is how long they survive.
        </p>
        <p v-if="trafficOn">There's traffic: <span class="v">{{ value("trafficPerPlayer") }}</span> cars around {{ r.trafficRunnerOnly === true ? "the runner" : "each player" }}.</p>
        <div class="flow">
          <div class="step">
            <div class="step-name"><BngIcon :type="icons.cogSolid" />Prep</div>
            <div class="step-text">The host starts a round. You're frozen; open Settings for your colour.</div>
          </div>
          <div class="step">
            <div class="step-name"><BngIcon :type="icons.play" />GO</div>
            <div class="step-text">The host presses GO and the runner goes <span class="v">{{ sec("runnerCountdownSeconds") }}</span> later.</div>
          </div>
          <div class="step">
            <div class="step-name"><BngIcon :type="icons.timer" />Head start</div>
            <div class="step-text">Cops wait <span class="v">{{ sec("headStartSeconds") }}</span> more.</div>
          </div>
          <div class="step">
            <div class="step-name"><BngIcon :type="icons.carChase01" />Chase</div>
            <div class="step-text">
              The clock runs until the runner is caught<template v-if="!noLimit"> or <span class="v">{{ duration("roundTimeLimitSeconds") }}</span> is up</template>.
            </div>
          </div>
          <div class="step">
            <div class="step-name"><BngIcon :type="icons.flag" />Result</div>
            <div class="step-text">The time goes on the leaderboard.</div>
          </div>
        </div>
        <p class="muted">Next round you might be the runner: whoever has run least goes next.</p>
        <p class="muted">
          Need a break? <b>Sit out</b> on the lobby card keeps you out of rounds until you press <b>Play</b>; your car leaves the map
          for the round and comes back where it stood. Sitting out, or joining while a round runs, you spectate: the game's switch-car
          keys (Tab and Ctrl+Tab by default) go through the players' cars, and free camera (Shift+C) works. With Sit out on,
          practice in the Host panel lets you watch the AI: an AI runner against two AI cops, spectated the same way.
        </p>
      </div>

      <div tab-heading="Runner" class="htp-tab">
        <div class="li">
          <BngIcon class="runner" :type="icons.carChase01" />
          <span>
            <b>Being caught:</b> a cop within <span class="v">{{ dist("catchRadiusMeters") }}</span> while you're under
            <span class="v">{{ kmh("catchMaxSpeedKmh") }}</span>, or stuck (rocking back and forth within 3 m in 4 s counts), fills the BEING CAUGHT bar, and after
            <span class="v">{{ sec("catchHoldSeconds") }}</span> you're caught. Drive away and it empties twice as fast as it filled.
          </span>
        </div>
        <div class="li">
          <BngIcon :type="sightOff ? icons.eyeSolidClosed : icons.eyeSolidOpened" />
          <span v-if="!sightOff">
            <b>SPOTTED / HIDDEN:</b> whether any cop can see you, up to <span class="v">{{ dist("sightMaxMeters") }}</span> away.
            While you're spotted, every cop sees where you are.
            <template v-if="heliOn">SPOTTED / HIDDEN is about cop sight only: while the helicopter tracks you, cops see you anyway
              (your live position, the minimap and your name tag).</template>
          </span>
          <span v-else>
            <b>Sight is off:</b> cops can't see you from their cars. They see you on the minimap and by name tag all round.
          </span>
        </div>
        <div v-if="heliOn" class="li">
          <BngIcon :type="icons.radar" />
          <span>
            <b>Police helicopter:</b>
            <template v-if="arrivalNow">it arrives as the cops are released</template>
            <template v-else>it arrives <span class="v">{{ duration("helicopterArrivalSeconds") }}</span> after the cops are released</template>
            and flies for <span class="v">{{ duration("helicopterUpSeconds") }}</span>.
            <template v-if="refuelNever">Then it stays up.</template>
            <template v-else>Then it refuels for <span class="v">{{ duration("helicopterRefuelSeconds") }}</span>.</template>
            It starts by searching from where you are as it arrives or, after a refuel, from where it last knew you were, and it searches the same way when it loses you. If you were moving, it searches along the road ahead, then the best other branch, then back; if not, it circles that spot. In a tunnel it watches each way out in turn, then searches the road beyond. When a cop sees you in a tunnel, it waits at the exit ahead.
            When a cop sees you, it flies to you; AI cops in practice don't guide it.
            It finds you only by seeing you itself, within <span class="v">{{ meters(400) }}</span>. Then it tracks you, and the cops know where you are.
            Buildings, hills, tunnels and garages hide you: it loses you after 2 s out of its sight.
            <template v-if="refuelNever">Before it arrives, it can't see you.</template>
            <template v-else>Before it arrives and while it refuels, it can't see you.</template>
            It is grounded while it is storm, fog or snow, and returns when the weather clears.
            At night its searchlight shines on you while it tracks you and keeps sweeping while it searches; you can turn its beam in the air off in your settings.
            <template v-if="sightOff">While it tracks you, cops see you live.</template>
          </span>
        </div>
        <div v-if="!sightOff" class="li">
          <BngIcon :type="icons.eyeSolidClosed" />
          <span><b>Hiding:</b> cops only see you on the minimap and by name tag while you're spotted<template v-if="heliOn"> or the helicopter tracks you</template>.</span>
        </div>
        <div class="li">
          <BngIcon :type="icons.eyeSolidClosed" />
          <span><b>No cop radar:</b> you never see the cops on the minimap or by name tag. The Nearest cop distance is all you get.</span>
        </div>
        <div class="li">
          <BngIcon :type="icons.mapPoint" />
          <span><b>Nearest cop:</b> the HUD shows how far away the closest cop is.</span>
        </div>
        <div class="li">
          <BngIcon :type="icons.stopwatchArrows02" />
          <span v-if="noLimit">There's <b>no time limit</b>: the chase runs until you're caught.</span>
          <span v-else><b>Time limit:</b> survive <span class="v">{{ duration("roundTimeLimitSeconds") }}</span> and you escape.</span>
        </div>
      </div>

      <div tab-heading="Cop" class="htp-tab">
        <div class="li">
          <BngIcon class="cop" :type="icons.carChase01" />
          <span>
            <b>Catch:</b> keep the runner under <span class="v">{{ kmh("catchMaxSpeedKmh") }}</span>, or stuck (rocking back and forth within 3 m in 4 s), with a cop within
            <span class="v">{{ dist("catchRadiusMeters") }}</span> for <span class="v">{{ sec("catchHoldSeconds") }}</span>.
            Every cop that close shares the catch.
          </span>
        </div>
        <div class="li">
          <BngIcon :type="sightOff ? icons.eyeSolidClosed : icons.eyeSolidOpened" />
          <span v-if="!sightOff">
            <b>Sight:</b> while any cop can see the runner (up to <span class="v">{{ dist("sightMaxMeters") }}</span>), every cop sees
            where the runner is. Otherwise the runner is hidden on the minimap and by name tag.
          </span>
          <span v-else>
            <b>Sight is off:</b> you see the runner on the minimap all round.
          </span>
        </div>
        <div class="li">
          <BngIcon :type="icons.eyeSolidClosed" />
          <span><b>Cops stay hidden:</b> the runner never sees you on the minimap or by name tag.</span>
        </div>
        <div v-if="heliOn" class="li">
          <BngIcon :type="icons.radar" />
          <span>
            <b>Police helicopter:</b>
            <template v-if="arrivalNow">it arrives as you're released</template>
            <template v-else>it arrives <span class="v">{{ duration("helicopterArrivalSeconds") }}</span> after you're released</template>
            and flies for <span class="v">{{ duration("helicopterUpSeconds") }}</span>.
            <template v-if="refuelNever">Then it stays up.</template>
            <template v-else>Then it refuels for <span class="v">{{ duration("helicopterRefuelSeconds") }}</span>.</template>
            It starts by searching from where the runner is as it arrives or, after a refuel, from where it last knew they were, and it searches the same way when it loses them. If they were moving, it searches along the road ahead, then the best other branch, then back; if not, it circles that spot. In a tunnel it watches each way out in turn, then searches the road beyond.
            While any cop sees the runner, it flies to them; seen in a tunnel, it waits at the exit ahead.
            It finds them only by seeing them itself, within <span class="v">{{ meters(400) }}</span>. While it tracks the runner, every cop sees where they are.
            Buildings, hills, tunnels and garages hide them: it loses them after 2 s out of its sight.
            <template v-if="refuelNever">Before it arrives, it can't see the runner.</template>
            <template v-else>Before it arrives and while it refuels, it can't see the runner.</template>
            It is grounded while it is storm, fog or snow, and returns when the weather clears.
            At night its searchlight shines on the runner while it tracks them and keeps sweeping while it searches; you can turn its beam in the air off in your settings.
          </span>
        </div>
        <div class="li">
          <BngIcon class="warn" :type="icons.caution" />
          <span>
            <b>Crash penalty:</b> crash into someone hard (losing <span class="v">{{ kmh("crashSpeedLossKmh") }}</span> in half a second)
            within <span class="v">{{ dist("copResetMinDistanceMeters") }}</span> of the runner and you're frozen for <span class="v">{{ sec("crashPenaltySeconds") }}</span>. Getting hit doesn't count.<template v-if="trafficOn"> Driving into traffic counts too; being hit by it doesn't.</template>
          </span>
        </div>
        <div class="li">
          <BngIcon :type="icons.strobeLights" />
          <span>Cops drive with emergency lights on.</span>
        </div>
      </div>

      <div tab-heading="Resets" class="htp-tab">
        <div class="two">
          <div class="box">
            <div class="box-title good"><BngIcon :type="icons.checkmarkBold" />You may reset</div>
            <div class="li">
              <BngIcon :type="icons.mapPoint" />
              <span>standing still at a gas station</span>
            </div>
            <div class="li">
              <BngIcon :type="icons.timer" />
              <span>after standing still for <span class="v">{{ sec("resetWaitSeconds") }}</span>, rocking in place still counts</span>
            </div>
            <div class="li">
              <BngIcon :type="icons.carChase01" />
              <span>as a cop, any time you're <span class="v">{{ dist("copResetMinDistanceMeters") }}</span> or more from the runner</span>
            </div>
            <div class="li">
              <BngIcon :type="icons.restart" />
              <span>as the runner, once right away when a cop crashes into you, while that cop serves the penalty (not while being caught)</span>
            </div>
          </div>
          <div class="box">
            <div class="box-title warn"><BngIcon :type="icons.abandon" />You may not</div>
            <div class="li">
              <BngIcon :type="icons.danger" />
              <span>as the runner, while you're being caught</span>
            </div>
            <div class="li">
              <BngIcon :type="icons.caution" />
              <span>during a crash penalty</span>
            </div>
            <div class="li">
              <BngIcon :type="icons.lockClosed" />
              <span>while you're frozen (prep, countdown, head start)</span>
            </div>
          </div>
        </div>
        <p>
          Any reset button works, and the HUD says when you may. A reset repairs your car where it stands; as a cop, a home or
          last-road reset moves you to the nearest road. A reset at the wrong moment is shown to everyone.
        </p>
      </div>

      <div tab-heading="Rules" class="htp-tab">
        <div v-if="r.weatherChanges !== false" class="li">
          <BngIcon :type="icons.caution" />
          <span>
            <b>Changing weather:</b> the weather can change during the chase, and the grip changes with it. A forecast line under the round clock shows the next change.
          </span>
        </div>
        <div class="li">
          <BngIcon :type="icons.lockClosed" />
          <span>
            <b>Locked during a round:</b> teleporting and recovery, the parts, tuning and paint menus, switching cars and free camera (open while spectating; free camera in practice too),
            photo mode, walking, slow motion, the node grabber, the editor and AI traffic.
          </span>
        </div>
        <div class="li">
          <BngIcon class="warn" :type="icons.caution" />
          <span>
            <b>Shown to everyone:</b> a reset at the wrong moment, a teleport, and parts changed during a round.
          </span>
        </div>
        <div class="li">
          <span class="swatch"></span>
          <span>
            <b>Your settings:</b> use the Settings button for your car colour, auto headlights at night and in bad weather, the helicopter's searchlight beam in the air, the helicopter's rotor sound, and as a cop, <span v-if="r.sirensAllowed !== false">a siren and </span>how the route to the runner is shown (always, only out of sight, or never).
            A colour set in prep repaints your car straight away; otherwise it applies from the next round.
          </span>
        </div>
        <div v-if="evolving" class="li">
          <BngIcon :type="icons.cogSolid" />
          <span>
            <b>Evolving car:</b> the same car carries over from round to round. In prep the runner makes one change that works on
            its own (an engine swap, one performance stage, or wheels one axle at a time), then presses Apply change. Everyone
            sees the change on their HUD.
          </span>
        </div>
      </div>
    </BngTabs>
    <template #actions>
      <BngButton class="got-it" :accent="ACCENTS.main" @click="emit('close')">Got it</BngButton>
    </template>
  </CnrCard>
</template>

<script setup>
import { ref, computed } from "vue"
import { BngButton, BngIcon, BngTabs, ACCENTS, icons } from "@/common/components/base"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"
import { formatTime } from "../../copsAndRobbers/format.js"

const props = defineProps({
  rules: Object,
  units: String,
})
const emit = defineEmits(["close"])

const tab = ref(0)
const r = computed(() => props.rules || {})
const noLimit = computed(() => r.value.noLimit !== false)
const sightOff = computed(() => r.value.sightOff === true)
const heliOn = computed(() => r.value.heliOn === true)
const refuelNever = computed(() => r.value.refuelNever === true)
const arrivalNow = computed(() => value("helicopterArrivalSeconds") === 0)
const evolving = computed(() => r.value.carMode === "evolving")
const trafficOn = computed(() => r.value.trafficOn === true)
const imperial = computed(() => props.units === "imperial")

function value(key) {
  const n = Number(r.value[key])
  return r.value[key] != null && Number.isFinite(n) ? n : null
}
function round1(n) {
  return String(Math.round(n * 10) / 10)
}
function unit(key, suffix) {
  const n = value(key)
  return n === null ? "–" : `${round1(n)} ${suffix}`
}
const sec = key => unit(key, "s")
function kmh(key) {
  const n = value(key)
  if (n === null) return "–"
  return imperial.value ? `${round1(n * 0.621371)} mph` : `${round1(n)} km/h`
}
function dist(key) {
  const n = value(key)
  return n === null ? "–" : meters(n)
}
function meters(n) {
  if (imperial.value) {
    const ft = Math.round(n * 3.28084)
    if (ft < 1000) return `${ft} ft`
    const mi = n / 1609.344
    return mi < 1 ? `${String(Math.round(mi * 100) / 100)} mi` : `${round1(mi)} mi`
  }
  return n >= 1000 ? `${round1(n / 1000)} km` : `${round1(n)} m`
}
function duration(key) {
  const n = value(key)
  if (n === null) return "–"
  return n % 60 === 0 ? `${n / 60} min` : formatTime(n)
}
</script>

<style scoped>
.how-to-play {
  flex: 1 1 auto;
  width: 100%;
  text-shadow: none;
  pointer-events: auto;
  font-size: 1rem;
  line-height: 1.5;
}
.how-to-play :deep(.cnr-card-actions) {
  justify-content: flex-end;
}
.htp-tab {
  box-sizing: border-box;
  padding: 0.75rem 0.25rem 0;
}
p {
  margin: 0 0 0.75rem;
}
b {
  font-weight: 700;
}
.v {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
  font-weight: 700;
  color: var(--cnr-me);
  white-space: nowrap;
}
.muted {
  color: var(--cnr-muted);
}
.runner {
  color: var(--cnr-runner-text);
}
.cop {
  color: var(--cnr-cop-text);
}
.warn {
  color: var(--cnr-warn);
}
.good {
  color: var(--cnr-good);
}
.flow {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 0.25rem;
  margin: 0 0 0.75rem;
}
.step {
  padding: 0.5rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.step-name {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  font-family: var(--cnr-display);
  font-weight: 800;
  --bng-icon-size: 1rem;
}
.step-text {
  margin-top: 0.25rem;
  font-size: 0.875rem;
  line-height: 1.4;
  color: var(--cnr-muted);
}
.li {
  display: grid;
  grid-template-columns: 1.5rem 1fr;
  gap: 0.5rem;
  align-items: start;
  margin: 0 0 0.5rem;
  --bng-icon-size: 1.25rem;
}
.two {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}
.box {
  padding: 0.5rem 0.75rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.box .li {
  margin-bottom: 0.25rem;
  font-size: 0.875rem;
}
.box-title {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.25rem;
  font-family: var(--cnr-display);
  font-weight: 800;
  --bng-icon-size: 1rem;
}
.swatch {
  width: 1rem;
  height: 1rem;
  margin: 0.25rem 0 0 0.25rem;
  border-radius: var(--bng-corners-1);
  box-shadow: 0 0 0 0.125rem var(--cnr-muted);
}
.how-to-play .got-it {
  font-family: var(--cnr-display);
  font-weight: 700;
  --bng-button-margin: 0;
}
</style>
