# Native lightning in multiplayer rounds

Use the opaque bolt and soft upper glow approved in West Coast USA freeroam on 2026-11-18. The reference was a bolt placed 3.5 km ahead horizontally at seed 47 with emissive factor 12, cloud cover 3 and a 450 m cloud base. In daylight and at night, the upper channel disappeared into dense cloud while the lower fork stayed bright. The player also confirmed the fade in motion.

## Bolt and lighting

- For a 3D camera-to-landing distance of 4,000 m or less at strike time, build the seeded 900 m channel and its branches from opaque emissive `TSStatic` rods. Keep their world positions for all pulses. Scale the rods at capture to approximate the tested four-pixel main channel and two-pixel branches, then narrow the branches on successive pulses. Hide the rods between pulses.
- Put the shadow-casting `PointLight` at the actual middle vertex of the seeded main channel. Use the tested full strength of `1e10` multiplied by the active pulse level. The light stays at that point through the strike, so shadows fall away from the bolt. Beyond 4,000 m, keep the distance-scaled overhead flash with shadows disabled. The strongest active pulse controls the single light, with ties going to the newer strike.
- Draw the seeded, soft, low-opacity glow at the upper channel during active pulses. Depth testing lets buildings and terrain cover the effect. Attenuate the glow using current fog and volumetric cloud conditions. In dense overcast, taper and hide segments where the view path passes through enough cloud. Preserve the core below cloud base and update the taper as the camera moves.

## Round behavior

Keep the existing round seed, clock, strike offsets, pulse times, weather transitions, landing-height raycast and late-join behavior. Thunder keeps its existing distance delay, gain, emitter limits and cleanup. There are no additional host or player settings.

The rain roof check and the player's Lightning flashes setting suppress the flash, bolt and glow while thunder continues. Discard visual objects on expiry, cover, preference off, seed replacement, round end, server leave and level unload. If native geometry fails to load or instantiate, remove any partially created objects and let the flash and thunder continue. If glow drawing fails, keep the core and other effects.
