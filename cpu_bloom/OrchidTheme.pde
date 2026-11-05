// Orchid: a photorealistic moth orchid (Phalaenopsis) whose openness follows
// average CPU load, from a closed bud on its arching stalk at idle to a full
// bloom facing you at 100%, and whose backlight brightens as the CPU warms
// up. The frames are rendered with Blender Cycles; FrameSequenceTheme plays
// them.

class OrchidTheme extends FrameSequenceTheme {
  String id() { return "orchid"; }
  String name() { return "Orchid"; }
  String folder() { return "orchid"; }

  // The backdrop is black and the stems leave through the sides, so the
  // frame sits in the middle of the window.
  boolean anchorBottom() { return false; }

  // The bud and the finished bloom change little from frame to frame, and the
  // unfurling in between changes a lot, so pass quickly through both ends and
  // slowly through the middle. Measured on the frames, 25/50/75% load shows
  // about 10/50/85% of the visible change instead of 3/27/91%.
  float sequencePosition(float open) {
    return constrain(open + 0.6 * sin(TWO_PI * open) / TWO_PI + 0.08 * sin(PI * open), 0, 1);
  }

  // Sways about where the flower spike enters, at the bottom right.
  float pivotX() { return 0.85; }
  float pivotY() { return 1.0; }

  int fallbackBackground() { return color(0); }
}
