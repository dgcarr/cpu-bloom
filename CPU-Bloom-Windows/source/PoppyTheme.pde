// Poppy: a photorealistic poppy whose openness follows average CPU load, from
// a closed bud at idle to a full bloom turned to face you at 100%, and whose
// backlight brightens as the CPU warms up. The frames are rendered with
// Blender Cycles; FrameSequenceTheme plays them.

class PoppyTheme extends FrameSequenceTheme {
  String id() { return "poppy"; }
  String name() { return "Poppy"; }
  String folder() { return "poppy"; }
}
