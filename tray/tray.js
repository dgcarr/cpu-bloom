// CPU Bloom top-bar indicator. Shows average CPU load next to a flower icon
// in the top bar or system tray (any StatusNotifierItem host) and starts or
// stops the visualisation window from its menu. It is a single-instance
// Gtk.Application, so running `cpu-bloom` again just forwards the arguments:
//
//   cpu-bloom               open the full window
//   cpu-bloom --overlay     open the small always-on-top overlay
//   cpu-bloom --background  indicator only (used at login)
//   cpu-bloom --quit        close the window and the indicator
//   --theme=<id>            with any of the above: switch theme (remembered)
//
// Without AyatanaAppIndicator3 or a StatusNotifier host (a desktop without a
// tray, or GNOME without the AppIndicator extension) there is no icon: it just
// opens the window and exits when the window closes. CPU_BLOOM_NO_TRAY=1
// forces that.
//
// In a snap, AppArmor won't let it own APP_ID on the session bus (that needs a
// store-reviewed dbus slot), so there it runs non-unique and forwards the
// arguments to the first instance over a socket in the snap's own runtime dir.
//
// Run with gjs; CPU_BLOOM_HOME and CPU_BLOOM_BIN come from bin/cpu-bloom.

imports.gi.versions.Gtk = '3.0';
const { GLib, Gio, Gtk } = imports.gi;
let AppIndicator = null;
try {
    AppIndicator = imports.gi.AyatanaAppIndicator3;
} catch (e) {
    // Not installed: run without an indicator.
}

const APP_ID = 'io.github.cpubloom.CpuBloom';
const APP_HOME = GLib.getenv('CPU_BLOOM_HOME');
const BIN = GLib.getenv('CPU_BLOOM_BIN');
const LAUNCHER = GLib.build_filenamev([APP_HOME, 'app', 'cpu_bloom']);
const AUTOSTART = GLib.build_filenamev([GLib.get_user_config_dir(), 'autostart', 'cpu-bloom.desktop']);
// Shared with the sketch (Settings.pde), which also writes and watches it.
const SETTINGS = GLib.build_filenamev([GLib.get_user_config_dir(), 'cpu-bloom', 'settings.properties']);
const IN_SNAP = GLib.getenv('SNAP') !== null;
// Per user: in a snap XDG_RUNTIME_DIR is /run/user/<uid>/snap.<name>.
const FORWARD_SOCKET = GLib.build_filenamev([GLib.get_user_runtime_dir(), 'tray.sock']);

function readCpuTotals() {
    const [, bytes] = GLib.file_get_contents('/proc/stat');
    const fields = new TextDecoder().decode(bytes).split('\n')[0].trim().split(/\s+/).slice(1, 9).map(Number);
    return { idle: fields[3] + fields[4], total: fields.reduce((a, b) => a + b, 0) };
}

// The indicator only shows up if something hosts StatusNotifierItems.
function trayAvailable() {
    if (!AppIndicator || GLib.getenv('CPU_BLOOM_NO_TRAY')) return false;
    try {
        const reply = Gio.DBus.session.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', 'NameHasOwner', new GLib.Variant('(s)', ['org.kde.StatusNotifierWatcher']),
            new GLib.VariantType('(b)'), Gio.DBusCallFlags.NONE, -1, null);
        return reply.deep_unpack()[0];
    } catch (e) {
        return false;
    }
}

function readSettings() {
    try {
        const [, bytes] = GLib.file_get_contents(SETTINGS);
        return new TextDecoder().decode(bytes);
    } catch (e) {
        return '';
    }
}

// Rewrites only this key's line so other settings survive.
function writeSetting(key, value) {
    const line = `${key}=${value}`;
    const pattern = new RegExp(`^${key}=.*$`, 'm');
    const text = readSettings();
    const next = pattern.test(text)
        ? text.replace(pattern, line)
        : `${text}${text && !text.endsWith('\n') ? '\n' : ''}${line}\n`;
    GLib.mkdir_with_parents(GLib.path_get_dirname(SETTINGS), 0o755);
    GLib.file_set_contents(SETTINGS, next);
}

// The window or overlay process. onChange runs whenever it starts or stops;
// onExit only when it exits by itself, not when it is closed or replaced.
class Window {
    constructor(onChange, onExit) {
        this.onChange = onChange;
        this.onExit = onExit;
        this.proc = null;
        this.mode = null;
    }

    open(mode) {
        if (this.proc && this.mode === mode) return;
        this.close();
        const argv = mode === 'overlay' ? [LAUNCHER, '--overlay'] : [LAUNCHER];
        const proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
        this.proc = proc;
        this.mode = mode;
        proc.wait_async(null, (p, res) => {
            try {
                p.wait_finish(res);
            } catch (e) {
                // Exit status doesn't matter; the window is gone either way.
            }
            if (this.proc === proc) {
                this.proc = null;
                this.mode = null;
                this.onChange();
                this.onExit();
            }
        });
        this.onChange();
    }

    close() {
        if (this.proc) {
            const proc = this.proc;
            this.proc = null;
            this.mode = null;
            proc.send_signal(15);
        }
        this.onChange();
    }
}

class Indicator {
    constructor(window) {
        this.window = window;
        this.syncing = false;

        // In a snap the tray host can't look up our icon by name, but it can
        // read the file from the snap's mount.
        const icon = IN_SNAP
            ? GLib.build_filenamev([GLib.getenv('SNAP'), 'usr/share/icons/hicolor/scalable/apps/cpu-bloom-symbolic.svg'])
            : 'cpu-bloom-symbolic';
        this.indicator = AppIndicator.Indicator.new('cpu-bloom', icon,
            AppIndicator.IndicatorCategory.SYSTEM_SERVICES);
        this.indicator.set_title('CPU Bloom');
        this.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE);
        this.buildMenu();

        this.prev = readCpuTotals();
        this.indicator.set_label('–', '100%');
        GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this.updateLoad();
            return GLib.SOURCE_CONTINUE;
        });
    }

    updateLoad() {
        const cur = readCpuTotals();
        const dTotal = cur.total - this.prev.total;
        const pct = dTotal > 0 ? Math.round(100 * (1 - (cur.idle - this.prev.idle) / dTotal)) : 0;
        this.prev = cur;
        if (pct !== this.lastPct) {
            this.indicator.set_label(`${pct}%`, '100%');
            this.lastPct = pct;
        }
    }

    buildMenu() {
        const menu = new Gtk.Menu();
        const add = (label, onActivate) => {
            const item = new Gtk.MenuItem({ label });
            item.connect('activate', onActivate);
            menu.append(item);
            return item;
        };

        this.windowItem = add('Open CPU Bloom', () => this.window.open('window'));
        this.overlayItem = add('Show Overlay', () => this.window.open('overlay'));
        this.closeItem = add('Close Window', () => this.window.close());
        this.onTopItem = new Gtk.CheckMenuItem({ label: 'Keep Window on Top' });
        this.onTopItem.connect('toggled', () => {
            if (!this.syncing) writeSetting('alwaysOnTop', String(this.onTopItem.active));
        });
        menu.append(this.onTopItem);

        const themeItem = new Gtk.MenuItem({ label: 'Theme' });
        this.themeMenu = new Gtk.Menu();
        themeItem.set_submenu(this.themeMenu);
        menu.append(themeItem);
        this.themeItems = new Map();
        this.buildThemeMenu([['bloom', 'Bloom']]);  // until the real list arrives
        this.loadThemes();
        menu.append(new Gtk.SeparatorMenuItem());

        this.loginItem = new Gtk.CheckMenuItem({ label: 'Start at Login' });
        this.loginOverlayItem = new Gtk.CheckMenuItem({ label: 'Show Overlay at Login' });
        this.loginItem.connect('toggled', () => this.writeAutostart());
        this.loginOverlayItem.connect('toggled', () => this.writeAutostart());
        menu.append(this.loginItem);
        menu.append(this.loginOverlayItem);
        menu.append(new Gtk.SeparatorMenuItem());

        add('Quit', () => quit());

        menu.show_all();
        this.indicator.set_menu(menu);
        this.syncAutostartItems();
        this.syncWindowItems();

        // Follow changes the sketch makes when A or N is pressed in the window.
        GLib.mkdir_with_parents(GLib.path_get_dirname(SETTINGS), 0o755);
        this.settingsMonitor = Gio.File.new_for_path(SETTINGS).monitor_file(Gio.FileMonitorFlags.NONE, null);
        this.settingsMonitor.connect('changed', () => {
            this.syncOnTopItem();
            this.syncThemeItems();
        });
        this.syncOnTopItem();
    }

    // Themes are compiled into the app, so ask it for the list rather than
    // keeping a copy here. `--list-themes` exits before opening a window.
    loadThemes() {
        try {
            const proc = Gio.Subprocess.new([LAUNCHER, '--list-themes'], Gio.SubprocessFlags.STDOUT_PIPE);
            proc.communicate_utf8_async(null, null, (p, res) => {
                try {
                    const [, stdout] = p.communicate_utf8_finish(res);
                    const list = stdout.split('\n')
                        .map(line => line.split('\t'))
                        .filter(parts => parts.length === 2 && parts[0]);
                    if (list.length > 0) this.buildThemeMenu(list);
                } catch (e) {
                    logError(e, 'Could not list themes');
                }
            });
        } catch (e) {
            logError(e, 'Could not start the app to list themes');
        }
    }

    buildThemeMenu(list) {
        for (const child of this.themeMenu.get_children()) this.themeMenu.remove(child);
        this.themeItems.clear();
        let previous = null;
        for (const [id, name] of list) {
            const item = Gtk.RadioMenuItem.new_with_label(previous ? previous.get_group() : [], name);
            item.connect('toggled', () => {
                if (!this.syncing && item.active) writeSetting('theme', id);
            });
            this.themeMenu.append(item);
            this.themeItems.set(id, item);
            previous = item;
        }
        this.themeMenu.show_all();
        this.syncThemeItems();
    }

    syncThemeItems() {
        const id = readSettings().match(/^theme=(\S+)\s*$/m)?.[1] ?? 'bloom';
        const item = this.themeItems.get(id) ?? this.themeItems.get('bloom');
        if (!item || item.active) return;
        this.syncing = true;
        item.active = true;
        this.syncing = false;
    }

    syncOnTopItem() {
        const on = /^alwaysOnTop=true\s*$/m.test(readSettings());
        if (this.onTopItem.active === on) return;
        this.syncing = true;
        this.onTopItem.active = on;
        this.syncing = false;
    }

    // The autostart file is the only state: present means "start at login",
    // and its Exec line says whether the overlay opens too.
    syncAutostartItems() {
        let exec = null;
        try {
            const [, bytes] = GLib.file_get_contents(AUTOSTART);
            exec = new TextDecoder().decode(bytes).match(/^Exec=(.*)$/m)?.[1] ?? '';
        } catch (e) {
            // No autostart file.
        }
        this.syncing = true;
        this.loginItem.active = exec !== null;
        this.loginOverlayItem.active = exec !== null && exec.includes('--overlay');
        this.loginOverlayItem.sensitive = exec !== null;
        this.syncing = false;
    }

    writeAutostart() {
        if (this.syncing) return;
        if (!this.loginItem.active) {
            GLib.unlink(AUTOSTART);
        } else {
            const mode = this.loginOverlayItem.active ? '--overlay' : '--background';
            GLib.mkdir_with_parents(GLib.path_get_dirname(AUTOSTART), 0o755);
            GLib.file_set_contents(AUTOSTART, [
                '[Desktop Entry]',
                'Type=Application',
                'Name=CPU Bloom',
                'Comment=CPU load indicator and overlay',
                `Exec="${BIN}" ${mode}`,
                'Icon=cpu-bloom',
                'NoDisplay=true',
                'X-GNOME-Autostart-enabled=true',
                '',
            ].join('\n'));
        }
        this.syncAutostartItems();
    }

    syncWindowItems() {
        const mode = this.window.mode;
        this.windowItem.sensitive = mode !== 'window';
        this.onTopItem.sensitive = mode !== 'overlay';  // the overlay is always on top
        this.overlayItem.sensitive = mode !== 'overlay';
        this.closeItem.sensitive = this.window.proc !== null;
    }

}

// Snap only: hand the arguments to a running instance. False if there is none.
function forwardToRunning(args) {
    try {
        const conn = new Gio.SocketClient().connect(Gio.UnixSocketAddress.new(FORWARD_SOCKET), null);
        conn.get_output_stream().write_all(new TextEncoder().encode(args.join('\0')), null);
        conn.close(null);
        return true;
    } catch (e) {
        return false;  // no socket, or a stale one from a crash
    }
}

// Snap only: accept arguments forwarded by later launches.
function listenForForwards() {
    GLib.unlink(FORWARD_SOCKET);  // stale, since nothing answered on it
    const service = new Gio.SocketService();
    try {
        service.add_address(Gio.UnixSocketAddress.new(FORWARD_SOCKET),
            Gio.SocketType.STREAM, Gio.SocketProtocol.DEFAULT, null);
    } catch (e) {
        logError(e, 'cpu-bloom: not accepting forwarded launches');
        return null;
    }
    service.connect('incoming', (_service, conn) => {
        const input = conn.get_input_stream();
        const chunks = [];
        const readMore = () => input.read_bytes_async(4096, GLib.PRIORITY_DEFAULT, null, (_s, res) => {
            const bytes = input.read_bytes_finish(res);
            if (bytes.get_size() > 0) {
                chunks.push(new TextDecoder().decode(bytes.toArray()));
                readMore();
            } else {
                conn.close(null);
                handleArgs(chunks.join('').split('\0'));
            }
        });
        readMore();
        return true;
    });
    service.start();
    return service;
}

const app = new Gtk.Application({
    application_id: APP_ID,
    flags: Gio.ApplicationFlags.HANDLES_COMMAND_LINE | (IN_SNAP ? Gio.ApplicationFlags.NON_UNIQUE : 0),
});
let window = null;
let indicator = null;
let forwardService = null;

function quit() {
    window.close();
    if (forwardService) {
        forwardService.stop();
        GLib.unlink(FORWARD_SOCKET);
    }
    app.release();
}

app.connect('startup', () => {
    app.hold();  // keep running with no windows of our own
    // Without an indicator nothing could reopen the window, so stop with it.
    window = new Window(() => indicator?.syncWindowItems(), () => {
        if (!indicator) quit();
    });
    if (trayAvailable()) indicator = new Indicator(window);
    if (IN_SNAP) forwardService = listenForForwards();
});

app.connect('command-line', (_app, cmdline) => {
    handleArgs(cmdline.get_arguments());
    return 0;
});

function handleArgs(args) {
    const themeArg = args.find(a => a.startsWith('--theme='));
    if (themeArg) writeSetting('theme', themeArg.slice('--theme='.length));
    if (args.includes('--quit'))
        quit();
    else if (args.includes('--overlay'))
        window.open('overlay');
    else if (!args.includes('--background'))
        window.open('window');
    else if (!indicator && !window.proc)
        quit();  // no indicator to keep running in the background
}

if (!(IN_SNAP && forwardToRunning(ARGV)))
    app.run([imports.system.programInvocationName].concat(ARGV));
