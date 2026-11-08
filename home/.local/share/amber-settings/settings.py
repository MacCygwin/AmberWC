#!/usr/bin/env python3
"""Amber Settings: a small GTK4 / libadwaita settings window.
Colours come from ~/.config/gtk-4.0/gtk.css (the amber palette). Edit freely, then just reopen it."""
import os
import platform
import re
import shutil
import subprocess
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk

APP_ID = "local.amber.Settings"
WAYBAR_SWITCH = os.path.expanduser("~/.config/waybar/waybar_switch.sh")

CSS = """
.navigation-sidebar row { border-radius: 14px; margin: 2px 8px; }
.navigation-sidebar row:selected { background: @accent_bg_color; color: @accent_fg_color; }
.navigation-sidebar row:selected image,
.navigation-sidebar row:selected label { color: @accent_fg_color; }
"""


# ----------------------------------------------------------------- helpers
def sh(*cmd, timeout=8):
    """Run a command, return stdout ('' on any failure)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ""


def ok(*cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout).returncode == 0
    except Exception:
        return False


def spawn(*cmd):
    try:
        subprocess.Popen(cmd, start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def tui(*cmd):
    spawn("foot", "-a", "amber-tui", "-e", *cmd)


def have(cmd):
    return shutil.which(cmd) is not None


def bg(work, done=None):
    """Run work() in a thread, then done(result) on the GTK main loop."""
    def run():
        result = work()
        if done:
            GLib.idle_add(done, result)
    threading.Thread(target=run, daemon=True).start()


def row(title, subtitle=""):
    r = Adw.ActionRow(title=title, subtitle=subtitle)
    r.set_use_markup(False)
    return r


def button_row(title, subtitle, label, callback):
    r = row(title, subtitle)
    b = Gtk.Button(label=label, valign=Gtk.Align.CENTER)
    b.connect("clicked", lambda *_: callback())
    r.add_suffix(b)
    r.set_activatable_widget(b)
    return r


class SliderRow(Adw.ActionRow):
    """0-100 slider that calls on_change(value) at most every ~80 ms."""

    def __init__(self, title, on_change):
        super().__init__(title=title)
        self._cb = on_change
        self._lock = False
        self._pending = None
        self._timer = 0
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.scale.set_size_request(280, -1)
        self.scale.set_valign(Gtk.Align.CENTER)
        self.scale.set_draw_value(False)
        self.scale.connect("value-changed", self._changed)
        self.add_suffix(self.scale)

    def set_value(self, v):
        self._lock = True
        self.scale.set_value(v)
        self._lock = False

    def _changed(self, scale):
        if self._lock:
            return
        self._pending = int(scale.get_value())
        if not self._timer:
            self._timer = GLib.timeout_add(80, self._fire)

    def _fire(self):
        self._timer = 0
        if self._pending is not None:
            self._cb(self._pending)
        return False


class Page(Adw.PreferencesPage):
    NAME = ""
    ICON = "preferences-system-symbolic"

    def refresh(self):
        pass

    def toast(self, msg):
        root = self.get_root()
        if root is not None and hasattr(root, "toast"):
            root.toast(msg)


# ----------------------------------------------------------------- Network
class NetworkPage(Page):
    NAME, ICON = "Network", "network-wireless-symbolic"

    def __init__(self):
        super().__init__()
        self._lock = False
        self._rows = []

        g = Adw.PreferencesGroup()
        self.sw = Adw.SwitchRow(title="Wi-Fi")
        self.sw.connect("notify::active", self._toggle)
        g.add(self.sw)
        self.add(g)

        self.nets = Adw.PreferencesGroup(title="Available networks")
        rescan = Gtk.Button(icon_name="view-refresh-symbolic", valign=Gtk.Align.CENTER,
                            css_classes=["flat"])
        rescan.connect("clicked", lambda *_: self.refresh(rescan=True))
        self.nets.set_header_suffix(rescan)
        self.add(self.nets)

        more = Adw.PreferencesGroup()
        more.add(button_row("Advanced", "Saved networks, VPN, static IP (nmtui)", "Open",
                            lambda: tui("nmtui")))
        self.add(more)

    def refresh(self, rescan=False):
        def work():
            on = sh("nmcli", "radio", "wifi") == "enabled"
            if on and rescan:
                sh("nmcli", "device", "wifi", "rescan", timeout=10)
            known = set(sh("nmcli", "-t", "-f", "NAME", "connection", "show").splitlines())
            nets, seen = [], set()
            if on:
                out = sh("nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID",
                         "device", "wifi", "list", "--rescan", "no")
                for line in out.splitlines():
                    parts = line.split(":", 3)
                    if len(parts) < 4:
                        continue
                    use, sig, sec, ssid = parts
                    ssid = ssid.replace("\\:", ":")
                    if not ssid or ssid in seen:
                        continue
                    seen.add(ssid)
                    nets.append((use == "*", int(sig or 0), sec not in ("", "--"), ssid, ssid in known))
            nets.sort(key=lambda n: (not n[0], -n[1]))
            return on, nets
        bg(work, self._render)

    def _render(self, result):
        on, nets = result
        self._lock = True
        self.sw.set_active(on)
        self._lock = False
        for r in self._rows:
            self.nets.remove(r)
        self._rows = []
        self.nets.set_visible(on)
        for connected, sig, secured, ssid, known in nets:
            sub = f"{sig}%" + (" · Secured" if secured else "") + (" · Connected" if connected else "")
            r = row(ssid, sub)
            if connected:
                b = Gtk.Button(label="Disconnect", valign=Gtk.Align.CENTER)
                b.connect("clicked", lambda _b, s=ssid: self._disconnect(s))
            else:
                b = Gtk.Button(label="Connect", valign=Gtk.Align.CENTER, css_classes=["suggested-action"])
                b.connect("clicked", lambda _b, s=ssid, sec=secured, k=known: self._connect(s, sec, k))
            r.add_suffix(b)
            self.nets.add(r)
            self._rows.append(r)

    def _toggle(self, sw, _p):
        if self._lock:
            return
        ok("nmcli", "radio", "wifi", "on" if sw.get_active() else "off")
        GLib.timeout_add(700, lambda: (self.refresh(rescan=True), False)[1])

    def _connect(self, ssid, secured, known):
        if secured and not known:
            self._ask_password(ssid)
        else:
            self._do_connect(ssid, None)

    def _ask_password(self, ssid):
        d = Adw.AlertDialog(heading=f"Connect to {ssid}", body="Enter the network password")
        entry = Gtk.PasswordEntry(show_peek_icon=True)
        d.set_extra_child(entry)
        d.add_response("cancel", "Cancel")
        d.add_response("connect", "Connect")
        d.set_response_appearance("connect", Adw.ResponseAppearance.SUGGESTED)
        d.set_default_response("connect")
        d.connect("response", lambda _d, resp: resp == "connect" and self._do_connect(ssid, entry.get_text()))
        d.present(self.get_root())

    def _do_connect(self, ssid, password):
        cmd = ["nmcli", "device", "wifi", "connect", ssid] + (["password", password] if password else [])
        self.toast(f"Connecting to {ssid}…")

        def done(success):
            self.toast(f"Connected to {ssid}" if success else f"Could not connect to {ssid}")
            self.refresh()
        bg(lambda: ok(*cmd, timeout=40), done)

    def _disconnect(self, ssid):
        bg(lambda: ok("nmcli", "connection", "down", "id", ssid), lambda _r: self.refresh())


# --------------------------------------------------------------- Bluetooth
class BluetoothPage(Page):
    NAME, ICON = "Bluetooth", "bluetooth-symbolic"

    def __init__(self):
        super().__init__()
        self._lock = False
        self._rows = []

        self.top = Adw.PreferencesGroup()
        self.sw = Adw.SwitchRow(title="Bluetooth")
        self.sw.connect("notify::active", self._toggle)
        self.top.add(self.sw)
        self.add(self.top)

        self.devs = Adw.PreferencesGroup(title="Paired devices")
        self.add(self.devs)

        self.pair = Adw.PreferencesGroup()
        self.pair.add(button_row("Pair a new device", "Opens bluetui", "Open", lambda: tui("bluetui")))
        self.add(self.pair)

    def refresh(self):
        def work():
            info = sh("bluetoothctl", "show") if have("bluetoothctl") else ""
            if "Powered" not in info:
                return None
            devs = []
            for line in sh("bluetoothctl", "devices").splitlines():
                p = line.split(" ", 2)
                if len(p) == 3 and p[0] == "Device":
                    devs.append((p[1], p[2], "Connected: yes" in sh("bluetoothctl", "info", p[1])))
            return "Powered: yes" in info, devs
        bg(work, self._render)

    def _render(self, result):
        for r in self._rows:
            self.devs.remove(r)
        self._rows = []
        if result is None:
            self.sw.set_visible(False)
            self.pair.set_visible(False)
            self.devs.set_title("")
            self.devs.set_description(
                "No Bluetooth adapter found. On NixOS add  hardware.bluetooth.enable = true;")
            return
        self.sw.set_visible(True)
        self.pair.set_visible(True)
        self.devs.set_title("Paired devices")
        self.devs.set_description("")
        on, devs = result
        self._lock = True
        self.sw.set_active(on)
        self._lock = False
        self.devs.set_visible(on)
        for mac, name, connected in devs:
            r = row(name, "Connected" if connected else "")
            b = Gtk.Button(label="Disconnect" if connected else "Connect", valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda _b, m=mac, c=connected: self._link(m, c))
            r.add_suffix(b)
            self.devs.add(r)
            self._rows.append(r)

    def _toggle(self, sw, _p):
        if self._lock:
            return
        ok("bluetoothctl", "power", "on" if sw.get_active() else "off")
        GLib.timeout_add(700, lambda: (self.refresh(), False)[1])

    def _link(self, mac, connected):
        verb = "disconnect" if connected else "connect"
        bg(lambda: ok("bluetoothctl", verb, mac, timeout=25), lambda r: (self.toast("Done" if r else "Failed"), self.refresh()))


# ------------------------------------------------------------------- Sound
def parse_volume(out):
    m = re.search(r"([\d.]+)", out)
    return (round(float(m.group(1)) * 100) if m else 0), ("MUTED" in out)


class SoundPage(Page):
    NAME, ICON = "Sound", "audio-volume-high-symbolic"

    def __init__(self):
        super().__init__()
        self._lock = False

        out = Adw.PreferencesGroup(title="Output")
        self.vol = SliderRow("Volume", lambda v: sh("wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", f"{v}%"))
        out.add(self.vol)
        self.mute = Adw.SwitchRow(title="Mute")
        self.mute.connect("notify::active", lambda s, _p: not self._lock and
                          sh("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if s.get_active() else "0"))
        out.add(self.mute)
        self.add(out)

        self.inp_group = Adw.PreferencesGroup(title="Input")
        self.mic = SliderRow("Microphone", lambda v: sh("wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", f"{v}%"))
        self.inp_group.add(self.mic)
        self.add(self.inp_group)

        adv = Adw.PreferencesGroup()
        mixer = ("wiremix",) if have("wiremix") else ("pavucontrol",)
        adv.add(button_row("Mixer", "Pick output / input devices and per-app volume", "Open", lambda: tui(*mixer) if mixer[0] == "wiremix" else spawn(*mixer)))
        self.add(adv)

    def refresh(self):
        def work():
            return (sh("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"),
                    sh("wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"))
        bg(work, self._render)

    def _render(self, result):
        sink, source = result
        v, muted = parse_volume(sink)
        self._lock = True
        self.vol.set_value(v)
        self.mute.set_active(muted)
        self._lock = False
        self.inp_group.set_visible(bool(source))
        if source:
            self.mic.set_value(parse_volume(source)[0])


# ----------------------------------------------------------------- Display
class DisplayPage(Page):
    NAME, ICON = "Display", "video-display-symbolic"

    def __init__(self):
        super().__init__()
        self._lock = False

        g = Adw.PreferencesGroup()
        self.bri = SliderRow("Brightness", lambda v: sh("brightnessctl", "set", f"{max(v, 1)}%"))
        g.add(self.bri)
        self.night = Adw.SwitchRow(title="Night light", subtitle="Warm screen colour (wlsunset, 3500 K)")
        self.night.connect("notify::active", self._night)
        g.add(self.night)
        self.add(g)

        arr = Adw.PreferencesGroup()
        arr.add(button_row("Arrange displays", "Resolution, scale and position (wdisplays)", "Open", lambda: spawn("wdisplays")))
        self.add(arr)

    def refresh(self):
        def work():
            m = sh("brightnessctl", "-m").split(",")
            pct = int(m[3].rstrip("%")) if len(m) > 3 and m[3].rstrip("%").isdigit() else None
            return pct, ok("pgrep", "-x", "wlsunset")
        bg(work, self._render)

    def _render(self, result):
        pct, night = result
        self._lock = True
        self.bri.set_visible(pct is not None)
        if pct is not None:
            self.bri.set_value(pct)
        self.night.set_active(night)
        self._lock = False

    def _night(self, sw, _p):
        if self._lock:
            return
        if sw.get_active():
            spawn("wlsunset", "-T", "3500", "-t", "3500", "-S", "07:00", "-s", "19:00")
        else:
            sh("pkill", "-x", "wlsunset")


# ------------------------------------------------------------------- Power
PROFILE_NAMES = {"power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance"}


class PowerPage(Page):
    NAME, ICON = "Power", "battery-symbolic"

    def __init__(self):
        super().__init__()
        self._lock = False
        self._profiles = []

        g = Adw.PreferencesGroup()
        self.battery = row("Battery")
        g.add(self.battery)
        self.combo = Adw.ComboRow(title="Power profile")
        self.combo.connect("notify::selected", self._set_profile)
        g.add(self.combo)
        self.add(g)

        s = Adw.PreferencesGroup(title="Session")
        s.add(button_row("Lock screen", "", "Lock", lambda: spawn("swaylock", "-f")))
        s.add(button_row("Power menu", "Log out, reboot, shut down", "Open", lambda: spawn("wlogout", "-b", "4")))
        self.add(s)

    def refresh(self):
        def work():
            bat = ""
            for d in sorted(os.listdir("/sys/class/power_supply")) if os.path.isdir("/sys/class/power_supply") else []:
                if d.startswith("BAT"):
                    try:
                        cap = open(f"/sys/class/power_supply/{d}/capacity").read().strip()
                        st = open(f"/sys/class/power_supply/{d}/status").read().strip()
                        bat = f"{cap}% · {st}"
                    except OSError:
                        pass
                    break
            profiles = re.findall(r"^[ *]+([a-z-]+):$", sh("powerprofilesctl", "list"), re.M)
            return bat, profiles, sh("powerprofilesctl", "get")
        bg(work, self._render)

    def _render(self, result):
        bat, profiles, cur = result
        self.battery.set_visible(bool(bat))
        self.battery.set_subtitle(bat)
        self.combo.set_visible(bool(profiles))
        if profiles:
            self._lock = True
            self._profiles = profiles
            self.combo.set_model(Gtk.StringList.new([PROFILE_NAMES.get(p, p) for p in profiles]))
            if cur in profiles:
                self.combo.set_selected(profiles.index(cur))
            self._lock = False

    def _set_profile(self, combo, _p):
        if self._lock or not self._profiles:
            return
        i = combo.get_selected()
        if 0 <= i < len(self._profiles):
            sh("powerprofilesctl", "set", self._profiles[i])


# -------------------------------------------------------------- Appearance
class AppearancePage(Page):
    NAME, ICON = "Appearance", "applications-graphics-symbolic"

    def __init__(self):
        super().__init__()
        g = Adw.PreferencesGroup()
        if os.access(WAYBAR_SWITCH, os.X_OK):
            g.add(button_row("Bar style", "Cycle through the waybar styles", "Switch", lambda: spawn(WAYBAR_SWITCH)))
        if have("nwg-look"):
            g.add(button_row("GTK theme tool", "nwg-look", "Open", lambda: spawn("nwg-look")))
        g.add(button_row("Reload desktop", "Re-read labwc, swaync and waybar config", "Reload", lambda: spawn(
            "sh", "-c", "labwc --reconfigure; swaync-client -R; swaync-client -rs; pkill waybar; waybar &")))
        self.add(g)


# ------------------------------------------------------------------- About
def read_first(path, pattern):
    try:
        for line in open(path):
            m = re.match(pattern, line)
            if m:
                return m.group(1).strip()
    except OSError:
        pass
    return ""


class AboutPage(Page):
    NAME, ICON = "About", "help-about-symbolic"

    def __init__(self):
        super().__init__()
        g = Adw.PreferencesGroup()
        mem_kb = read_first("/proc/meminfo", r"MemTotal:\s+(\d+)")
        items = [
            ("Device name", platform.node()),
            ("System", read_first("/etc/os-release", r'PRETTY_NAME="?([^"\n]+)"?')),
            ("Kernel", platform.release()),
            ("Processor", read_first("/proc/cpuinfo", r"model name\s*:\s*(.+)")),
            ("Memory", f"{int(mem_kb) / 1048576:.1f} GiB" if mem_kb.isdigit() else ""),
        ]
        for title, value in items:
            if value:
                r = row(title, value)
                r.add_css_class("property")
                r.set_subtitle_selectable(True)
                g.add(r)
        self.add(g)


# ------------------------------------------------------------------ Window
class SettingsWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Settings", default_width=980, default_height=660)
        self.pages = [NetworkPage(), BluetoothPage(), SoundPage(), DisplayPage(),
                      PowerPage(), AppearancePage(), AboutPage()]

        self.sidebar = Gtk.ListBox(css_classes=["navigation-sidebar"])
        for p in self.pages:
            box = Gtk.Box(spacing=12, margin_top=10, margin_bottom=10, margin_start=12, margin_end=12)
            box.append(Gtk.Image.new_from_icon_name(p.ICON))
            box.append(Gtk.Label(label=p.NAME, xalign=0))
            r = Gtk.ListBoxRow()
            r.set_child(box)
            self.sidebar.append(r)
        self.sidebar.connect("row-selected", self._select)

        side = Adw.ToolbarView()
        side.add_top_bar(Adw.HeaderBar())
        side.set_content(Gtk.ScrolledWindow(child=self.sidebar))

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        for p in self.pages:
            self.stack.add_named(p, p.NAME)
        content = Adw.ToolbarView()
        content.add_top_bar(Adw.HeaderBar())
        content.set_content(self.stack)
        self.content_nav = Adw.NavigationPage.new(content, self.pages[0].NAME)

        split = Adw.NavigationSplitView()
        split.set_sidebar(Adw.NavigationPage.new(side, "Settings"))
        split.set_content(self.content_nav)

        self.toasts = Adw.ToastOverlay()
        self.toasts.set_child(split)
        self.set_content(self.toasts)

        self.connect("notify::is-active", lambda *_: self.is_active() and self._refresh_current())
        self.sidebar.select_row(self.sidebar.get_row_at_index(0))

    def toast(self, msg):
        self.toasts.add_toast(Adw.Toast.new(msg))

    def _select(self, _lb, row_):
        if row_ is None:
            return
        page = self.pages[row_.get_index()]
        self.stack.set_visible_child(page)
        self.content_nav.set_title(page.NAME)
        page.refresh()

    def _refresh_current(self):
        r = self.sidebar.get_selected_row()
        if r is not None:
            self.pages[r.get_index()].refresh()


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        provider = Gtk.CssProvider()
        if hasattr(provider, "load_from_string"):
            provider.load_from_string(CSS)
        else:
            provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def do_activate(self):
        win = self.props.active_window or SettingsWindow(self)
        win.present()


if __name__ == "__main__":
    raise SystemExit(App().run(None))
