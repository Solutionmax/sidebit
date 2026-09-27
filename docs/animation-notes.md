# Character scenes

`PetView` plays Bit's transparent films. When a film cannot play, it falls back to a cached 3×2 atlas: working, thinking, waiting, celebrating, sleeping and a coffee mishap, in row order. A missing atlas shows a symbol rather than crashing.

`CharacterScene` owns deterministic 48-second macrocycles. Working has four typing passages with different cadences, a long inspection pause and a brief look away. Thinking alternates two duck consultations, pauses, and small idea beats. Waiting gently rocks its existing raised-hand illustration three times across the minute; unknown stays quiet and uses a question cue. Completion compresses, jumps, lands and emits confetti **once on entering done**, then settles into quiet breathing. Sleeping breathes with drifting Zs and one brief hiccup near second 32.

These are whole-illustration transforms and native Canvas accents, not a skeletal rig or independently animated limbs. The six original pose meanings remain unchanged: a working session never borrows celebration art.

Coffee is a single 16-second vignette: two nervous wobbles, relief, and a settling pause. Its visibility is controlled by the parent through `gag`; the scene does not schedule coffee itself. Waiting and unknown status preempt the gag. Separate activity and coffee clocks prevent ending a joke from restarting a completion celebration. The accessibility label retains the actual activity during coffee.
Timeline updates are capped at 24 fps, or 12 fps for idle. The app preference and system Reduce Motion both pause the timeline, neutralize transforms, disable transitions and remove particles. Picker views (`decorations: false`) are also frozen. Scene changes fade and scale over 0.3 seconds. Everything fits the existing `size + 30` frame without an opaque stage background.

Quips come from `SnipkinCore/Quips.swift`. The model picks one per 24-second slice, seeded by when the activity started, so a line never flickers. Lines react to the tool in use (commands, edits, reads, web, helpers), errors, late nights, early mornings and both agents working at once. Bubbles appear in two short windows per macrocycle. Urgent lines (a new moment, being carried, a boop) show immediately.

Bit's sheet was visually inspected for pose order.

Timing review points: working 4/19/28/37/42s; thinking 5/13/18/29/42s; waiting 5/26/42s; done 1/4/49s; idle 8/32.3/35s. At done 49s there must be no new jump or confetti. Reduced motion must produce neutral transforms and no Canvas particles at every sample.
