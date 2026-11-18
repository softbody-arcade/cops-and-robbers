# Shadows from nearby lightning

A nearby bolt should briefly throw a car or tree's shadow away from the bolt. Distant lightning still lights the open scene overhead. The feature uses the existing local lightning-flashes preference, round schedule and strike-time camera distance. The listener can be a driver or a free-camera spectator.

## Lighting

A strike is close when the 3D distance between the camera and the captured landing point is strictly below 1,000 m. This matches the existing close thunder band. Exactly 1,000 m uses the distant flash. Evaluate the distance once per strike.

For a close flash, aim from the strike-time camera toward a point 450 m above the captured landing, halfway up the 900 m bolt. Put the PointLight 300 m from that camera along the resulting direction and freeze the position for every pulse of the strike. If the aim point and camera coincide, place the light 300 m overhead. This places the light on the bolt side of the scene, so nearby objects cast shadows away from the visible bolt. The light represents the direction of the channel. A building beyond the light's position cannot cast a shadow from it onto the listener.

Use the same 1,500 m radius and the existing intensity curve, `1e10 * (300 / max(300, d))^2` times the pulse level. Keeping the source 300 m from the observer at capture preserves the tested source distance while using the curve once. Visible brightness on a particular surface will also depend on its angle and occlusion.

Set `castShadows` only for close flashes. Distant flashes use the current camera position plus 300 m vertically. Both modes reuse the existing single unsaved PointLight. When pulses overlap, the strongest active pulse selects the position, shadow state and field intensity together. The newer strike wins an exact tie. All visible bolts keep their own shapes and all thunder keeps its existing arrival times. Dark pulse gaps, cover, disabled visuals, a changed seed and round end continue to disable or remove the light.

## In-game acceptance

At night on West Coast USA, view a nearby bolt from beside a tree or parked car with the bolt to one side. Look for a shadow away from the bolt, consistent successive pulses and suitable brightness. Check at least one distant flash, a covered camera and the transition out of the round. Compare frame pacing during a close flash. A screenshot or short recording of the side-lit scene will help distinguish shadow direction from the car's lights.
