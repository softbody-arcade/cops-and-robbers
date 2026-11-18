# Host-configurable lightning frequency

The host sets the minimum and maximum time between lightning strikes under **Host panel → Settings → More settings → Sky**. Show the two controls only in the expanded settings when Weather is Thunderstorm or Random, or Weather changes is enabled. Label them **Minimum strike interval** and **Maximum strike interval**, in seconds.

Use whole seconds starting at 1, with defaults of 10 and 40. Follow the existing settings editor and persistence rules for paired timing values, including applying a batch that lowers both. Ensure the maximum is at least the minimum. Existing configurations and sky payloads use the defaults.

Capture both settings when a round sky is generated and send the captured values with its lightning seed to each client, including reconnects and spectators. In a full Thunderstorm, use the shared seed to draw each wait uniformly within the chosen range. Equal values give a fixed interval, including the first wait from the start of the runner countdown when the host presses GO. Retain the current reduction in strikes during weather transitions. Lightning remains exclusive to weather with thunderstorm weight. Host changes apply to newly generated skies. The current round keeps its shared timing.

Verify at a fixed 5 seconds with Night, Thunderstorm, Weather changes off and Lightning flashes on. Compare the cadence between bolts rather than rumble arrivals. Thunder delays still depend on distance.
