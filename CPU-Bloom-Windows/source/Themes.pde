// Finds every Theme subclass in the sketch by reflection, so adding a theme
// is just adding a tab. Themes are inner classes of the sketch, so each is
// constructed with the sketch instance as its hidden outer argument.

final String DEFAULT_THEME = "bloom";

ArrayList<Theme> themes = new ArrayList<Theme>();
volatile Theme theme;

void discoverThemes() {
  themes.clear();
  for (Class<?> c : getClass().getDeclaredClasses()) {
    if (!Theme.class.isAssignableFrom(c) || java.lang.reflect.Modifier.isAbstract(c.getModifiers())) continue;
    try {
      themes.add((Theme) c.getDeclaredConstructor(getClass()).newInstance(this));
    } catch (Exception e) {
      println("Skipping theme " + c.getSimpleName() + ": " + e);
    }
  }
  // The default theme first, the rest alphabetically.
  themes.sort((a, b) -> a.id().equals(DEFAULT_THEME) ? -1 : b.id().equals(DEFAULT_THEME) ? 1
                        : a.name().compareToIgnoreCase(b.name()));
}

Theme findTheme(String id) {
  for (Theme t : themes) if (t.id().equals(id)) return t;
  return null;
}

// Switches to the theme with this id; unknown ids fall back to the default.
void setTheme(String id) {
  Theme next = findTheme(id);
  if (next == null) next = findTheme(DEFAULT_THEME);
  if (next == null && !themes.isEmpty()) next = themes.get(0);
  if (next == null || next == theme) return;
  if (theme != null) theme.stop();
  theme = next;
  theme.start();
  theme.setSuspended(false);
}

void nextTheme() {
  if (themes.isEmpty()) return;
  setTheme(themes.get((themes.indexOf(theme) + 1) % themes.size()).id());
  saveSetting("theme", theme.id());
}

// `cpu_bloom --list-themes` prints "id<TAB>name" lines for the indicator menu.
void printThemes() {
  for (Theme t : themes) System.out.println(t.id() + "\t" + t.name());
}
