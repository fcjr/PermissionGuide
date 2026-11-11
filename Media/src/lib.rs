//! PermissionGuide's README clips and release teaser, drawn with fframes.
//!
//! Nothing here is a screen recording. `guide_stage` redraws what the library shows (System
//! Settings, the highlight, the side panel, the drag hint and the Touch ID prompt) on a
//! 960x600 stage, with the sizes and texts taken from `Sources/PermissionGuide`. The clips
//! (`clips.rs`) and the teaser (`teaser.rs`) place that stage and add a pointer.
use fframes::{EncoderOptions, RenderOptions, Svgr, Video, cli, include_media_dir};
use fframes_skia_renderer::{SkiaFFramesRenderer, SkiaPipelineConcurrencyPolicy, SkiaPipelineConfig, metal::SkiaMetalCtx};
use std::f32::consts::PI;
use std::process::ExitCode;

pub mod clips;
pub mod teaser;
pub mod timing;

use timing::Beats;

include_media_dir!(pub struct Media, "media");

pub const TEXT: &str = "SF Pro Text";
pub const DISPLAY: &str = "SF Pro Display";
pub const MONO: &str = "Monaco";

pub const INK: &str = "#1d1d1f";
pub const SECOND: &str = "#6e6e73";
pub const LINE: &str = "#dedee3";
pub const TINT: &str = "#0a7aff";
pub const GREEN: &str = "#34c759";

/// The stage every demo is drawn on, in points.
pub const STAGE_W: f32 = 960.0;
pub const STAGE_H: f32 = 600.0;

// System Settings' window, with the library's own measurements of it.
const WX: f32 = 36.0;
const WY: f32 = 40.0;
const WW: f32 = 660.0;
const WH: f32 = 520.0;
const SIDEBAR: f32 = 232.0;
const INSET: f32 = 20.0;
const ROW: f32 = 40.0;
const LIST_X: f32 = SIDEBAR + INSET;
const LIST_Y: f32 = 112.0;
const LIST_W: f32 = WW - SIDEBAR - INSET * 2.0;
const LIST_FOOT: f32 = 30.0;

// The side panel: 216 pt wide, 16 pt from the window, centered on it.
const PX: f32 = WX + WW + 16.0;
const PW: f32 = 216.0;
const PH: f32 = 300.0;
const PY: f32 = WY + WH / 2.0 - PH / 2.0;
/// The center of the panel's icon, where a drag starts.
pub const ICON: [f32; 2] = [PX + PW / 2.0, PY + 104.0];
/// The middle of the list, where it ends.
pub const DROP: [f32; 2] = [WX + LIST_X + LIST_W / 2.0, WY + LIST_Y + 54.0];

// The extension sheet and its one row.
const SHEET: [f32; 4] = [SIDEBAR + 24.0, 118.0, 380.0, 190.0];
const SHEET_ROW: [f32; 4] = [SHEET[0] + 20.0, SHEET[1] + 54.0, SHEET[2] - 40.0, 48.0];
/// The switch in the sheet.
pub const SWITCH: [f32; 2] = [WX + SHEET_ROW[0] + SHEET_ROW[2] - 31.0, WY + SHEET_ROW[1] + 24.0];

// The Touch ID prompt, centered on the window.
const AUTH: [f32; 4] = [WX + WW / 2.0 - 125.0, WY + WH / 2.0 - 115.0, 250.0, 230.0];

// The app's own window.
const AX: f32 = 220.0;
const AY: f32 = 142.0;
const AW: f32 = 520.0;
const AH: f32 = 316.0;
/// The Grant button on the app's first row.
pub const GRANT: [f32; 2] = [AX + AW - 74.0, AY + 132.0];

/// What the guide asks the user to do.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mode {
    /// Drag the app into a privacy list (Accessibility here).
    Drag,
    /// Turn on a system extension's switch.
    Toggle,
}

// ---------------------------------------------------------------------------------------------
// Motion helpers.

pub fn clamp01(x: f32) -> f32 {
    x.clamp(0.0, 1.0)
}

pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// 0..1 between `start` and `start + duration`.
pub fn span(t: f32, start: f32, duration: f32) -> f32 {
    clamp01((t - start) / duration)
}

pub fn ease_out(x: f32) -> f32 {
    1.0 - (1.0 - x).powi(3)
}

pub fn ease_in_out(x: f32) -> f32 {
    if x < 0.5 { 4.0 * x * x * x } else { 1.0 - (-2.0 * x + 2.0).powi(3) / 2.0 }
}

/// Damped spring from 0 to 1 starting at `start`; overshoots a little.
pub fn spring(t: f32, start: f32) -> f32 {
    let t = t - start;
    if t <= 0.0 {
        return 0.0;
    }
    let (stiffness, damping) = (170.0_f32, 17.0_f32);
    let w0 = stiffness.sqrt();
    let zeta = damping / (2.0 * w0);
    let wd = w0 * (1.0 - zeta * zeta).sqrt();
    1.0 - (-zeta * w0 * t).exp() * ((wd * t).cos() + zeta * w0 / wd * (wd * t).sin())
}

/// The position at `t` along `keys`, easing between them.
pub fn track(t: f32, keys: &[(f32, [f32; 2])]) -> [f32; 2] {
    let Some(next) = keys.iter().position(|k| k.0 > t) else {
        return keys[keys.len() - 1].1;
    };
    if next == 0 {
        return keys[0].1;
    }
    let (a, b) = (keys[next - 1], keys[next]);
    let p = ease_in_out(span(t, a.0, b.0 - a.0));
    [lerp(a.1[0], b.1[0], p), lerp(a.1[1], b.1[1], p)]
}

/// Rough width of a line of SF Pro Text.
pub fn tw(text: &str, size: f32) -> f32 {
    text.chars().count() as f32 * size * 0.52
}

/// A rounded rectangle as a path, so two of them can share one even-odd fill.
fn round_rect(x: f32, y: f32, w: f32, h: f32, r: f32) -> String {
    format!(
        "M{} {y} H{} Q{} {y} {} {} V{} Q{} {} {} {} H{} Q{x} {} {x} {} V{} Q{x} {y} {} {y} Z",
        x + r, x + w - r, x + w, x + w, y + r, y + h - r, x + w, y + h, x + w - r, y + h, x + r, y + h, y + h - r, y + r, x + r
    )
}

fn grow(about: [f32; 2], scale: f32) -> String {
    format!("translate({} {}) scale({scale}) translate({} {})", about[0], about[1], -about[0], -about[1])
}

// ---------------------------------------------------------------------------------------------
// Shared pieces.

/// Gradients and filters used by every clip and scene.
pub fn defs() -> Svgr<'static> {
    fframes::svgr!(
        <defs>
            <filter id="window-shadow" x="-20%" y="-20%" width="140%" height="150%">
                <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#000" flood-opacity="0.32" />
            </filter>
            <filter id="panel-shadow" x="-30%" y="-30%" width="160%" height="170%">
                <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.3" />
            </filter>
            <filter id="soft-shadow" x="-40%" y="-40%" width="180%" height="190%">
                <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000" flood-opacity="0.3" />
            </filter>
            <filter id="cursor-shadow" x="-50%" y="-50%" width="200%" height="200%">
                <feDropShadow dx="0" dy="1" stdDeviation="1.2" flood-color="#000" flood-opacity="0.4" />
            </filter>
            <filter id="glow-near" x="-30%" y="-60%" width="160%" height="220%">
                <feGaussianBlur stdDeviation="4" />
            </filter>
            <filter id="glow-far" x="-30%" y="-60%" width="160%" height="220%">
                <feGaussianBlur stdDeviation="11" />
            </filter>
            <linearGradient id="wall" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0" stop-color="#1b2a6b" />
                <stop offset="0.55" stop-color="#3a2f8f" />
                <stop offset="1" stop-color="#0f6f8c" />
            </linearGradient>
            <linearGradient id="night" x1="0" y1="0" x2="0.6" y2="1">
                <stop offset="0" stop-color="#0b1026" />
                <stop offset="1" stop-color="#151a3d" />
            </linearGradient>
            <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
                <stop offset="0" stop-color="#3d7bff" stop-opacity="0.5" />
                <stop offset="1" stop-color="#3d7bff" stop-opacity="0" />
            </radialGradient>
            <linearGradient id="icon" x1="0" y1="0" x2="0.4" y2="1">
                <stop offset="0" stop-color="#ff9f43" />
                <stop offset="1" stop-color="#ff5e62" />
            </linearGradient>
            <linearGradient id="mark" x1="0" y1="0" x2="0.4" y2="1">
                <stop offset="0" stop-color="#4da3ff" />
                <stop offset="1" stop-color="#0a5cff" />
            </linearGradient>
        </defs>
    )
}

/// The made-up app's icon, `size` wide with its top-left at (x, y).
pub fn app_icon(x: f32, y: f32, size: f32) -> Svgr<'static> {
    fframes::svgr!(<g transform={format!("translate({x} {y}) scale({})", size / 100.0)}>
        <rect x="6" y="6" width="88" height="88" rx="20" fill="url(#icon)" />
        <rect x="6.75" y="6.75" width="86.5" height="86.5" rx="19.3" fill="none" stroke="#fff" stroke-opacity="0.25" stroke-width="1.5" />
        <circle cx="50" cy="50" r="19" fill="none" stroke="#fff" stroke-width="7" />
        <circle cx="50" cy="50" r="6.5" fill="#fff" />
    </g>)
}

/// PermissionGuide's mark: an app dropped into a highlighted list.
pub fn mark(x: f32, y: f32, size: f32) -> Svgr<'static> {
    fframes::svgr!(<g transform={format!("translate({x} {y}) scale({})", size / 100.0)}>
        <rect x="4" y="4" width="92" height="92" rx="21" fill="url(#mark)" />
        <rect x="22" y="26" width="56" height="48" rx="9" fill="#fff" fill-opacity="0.16" stroke="#fff" stroke-width="5" />
        <rect x="31" y="36" width="13" height="13" rx="3.5" fill="#fff" />
        <rect x="50" y="40" width="19" height="5" rx="2.5" fill="#fff" />
        <rect x="31" y="56" width="38" height="5" rx="2.5" fill="#fff" fill-opacity="0.55" />
    </g>)
}

fn traffic_lights(x: f32, y: f32) -> Svgr<'static> {
    fframes::svgr!(<g>
        <circle cx={x} cy={y} r="6" fill="#ff5f57" />
        <circle cx={x + 20.0} cy={y} r="6" fill="#febc2e" />
        <circle cx={x + 40.0} cy={y} r="6" fill="#28c840" />
    </g>)
}

/// A switch, 34x20 with its top-left at (x, y); `on` is 0..1.
fn switch(x: f32, y: f32, on: f32) -> Svgr<'static> {
    fframes::svgr!(<g>
        <rect x={x} y={y} width="34" height="20" rx="10" fill="#d1d1d6" />
        <rect x={x} y={y} width="34" height="20" rx="10" fill={GREEN} opacity={on} />
        <circle cx={x + 10.0 + 14.0 * on} cy={y + 10.0} r="8" fill="#fff" filter="url(#cursor-shadow)" />
    </g>)
}

/// A push button with its label centered.
fn button(x: f32, y: f32, w: f32, h: f32, label: &'static str, primary: bool, enabled: bool) -> Svgr<'static> {
    let (fill, ink, stroke) = if primary { (TINT, "#fff", TINT) } else { ("#fff", INK, "#cfcfd4") };
    fframes::svgr!(<g opacity={if enabled { 1.0 } else { 0.4 }}>
        <rect x={x} y={y} width={w} height={h} rx="6" fill={fill} stroke={stroke} stroke-width="0.8" />
        <text x={x + w / 2.0} y={y + h / 2.0 + 4.3} text-anchor="middle" font-family={TEXT} font-weight="500" font-size="12.5" fill={ink}>{label}</text>
    </g>)
}

/// A green circle with a check, centered on (x, y).
fn check(x: f32, y: f32, r: f32) -> Svgr<'static> {
    let s = r / 10.0;
    fframes::svgr!(<g transform={format!("translate({x} {y}) scale({s})")}>
        <circle cx="0" cy="0" r="10" fill={GREEN} />
        <path d="M-4.6 0.4 L-1.4 3.6 L4.8 -3.4" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" />
    </g>)
}

/// How the pointer looks.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Pointer {
    Arrow,
    OpenHand,
    ClosedHand,
}

const OPEN_HAND: &str = "M4 11 V6 Q4 4.5 5.5 4.5 Q7 4.5 7 6 V3.5 Q7 2 8.5 2 Q10 2 10 3.5 V3 Q10 1.5 11.5 1.5 Q13 1.5 13 3 V4 Q13 2.8 14.5 2.8 Q16 2.8 16 4.3 V13 Q16 19 10.5 19 H9.5 Q6 19 4.5 15.5 L2 11.5 Q1.3 10 2.6 9.6 Q3.5 9.4 4 11 Z";
const CLOSED_HAND: &str = "M4.2 9.5 Q4 6.8 6 6.6 Q6.8 5 8.6 5.6 Q9.8 4.4 11.4 5.4 Q13.2 4.8 14 6.4 Q16 6.4 16 8.6 V13 Q16 19 10.5 19 H9.5 Q5.6 19 4.6 15.4 L3.4 12 Q3 10 4.2 9.5 Z";

/// The pointer with its hot spot at (x, y).
pub fn pointer(x: f32, y: f32, kind: Pointer, pressed: bool) -> Svgr<'static> {
    match kind {
        Pointer::Arrow => {
            let scale = if pressed { 0.92 } else { 1.0 };
            fframes::svgr!(<g transform={format!("translate({x} {y}) scale({scale})")} filter="url(#cursor-shadow)">
                <path d="M0 0 V18.5 L4.6 14.1 L7.9 21.7 L11.3 20.3 L8 12.8 H14 Z" fill="#000" stroke="#fff" stroke-width="1.4" stroke-linejoin="round" />
            </g>)
        }
        Pointer::OpenHand | Pointer::ClosedHand => {
            let d = if kind == Pointer::OpenHand { OPEN_HAND } else { CLOSED_HAND };
            fframes::svgr!(<g transform={format!("translate({} {}) scale(1.4)", x - 13.0, y - 15.0)} filter="url(#cursor-shadow)">
                <path d={d} fill="#fff" stroke="#000" stroke-width="1.1" stroke-linejoin="round" />
            </g>)
        }
    }
}

/// A pointer with a ripple for each click in `clicks`.
pub fn cursor(t: f32, at: [f32; 2], kind: Pointer, clicks: &[f32]) -> Svgr<'static> {
    let pressed = clicks.iter().any(|c| (t - c).abs() < 0.09);
    let ripples: Vec<Svgr> = clicks
        .iter()
        .filter(|c| t >= **c && t < **c + 0.45)
        .map(|c| {
            let p = ease_out(span(t, *c, 0.45));
            fframes::svgr!(<circle cx={at[0]} cy={at[1]} r={5.0 + 17.0 * p} fill={TINT} fill-opacity={0.25 * (1.0 - p)} stroke={TINT} stroke-opacity={0.7 * (1.0 - p)} stroke-width="1.5" />)
        })
        .collect();
    fframes::svgr!(<g>
        {ripples}
        {pointer(at[0], at[1], kind, pressed)}
    </g>)
}

// ---------------------------------------------------------------------------------------------
// System Settings.

const SIDEBAR_ITEMS: [(&str, &str); 15] = [
    ("Wi-Fi", "#0a84ff"),
    ("Bluetooth", "#0a84ff"),
    ("Network", "#0a84ff"),
    ("General", "#8e8e93"),
    ("Accessibility", "#0a84ff"),
    ("Appearance", "#1d1d1f"),
    ("Control Center", "#8e8e93"),
    ("Desktop & Dock", "#1d1d1f"),
    ("Displays", "#0a84ff"),
    ("Notifications", "#ff453a"),
    ("Sound", "#ff375f"),
    ("Focus", "#5e5ce6"),
    ("Screen Time", "#5e5ce6"),
    ("Privacy & Security", "#0a84ff"),
    ("Touch ID & Password", "#ff453a"),
];

fn sidebar(selected: usize) -> Svgr<'static> {
    let items: Vec<Svgr> = SIDEBAR_ITEMS
        .iter()
        .enumerate()
        .map(|(i, (label, color))| {
            let y = 86.0 + i as f32 * 27.5;
            let on = i == selected;
            fframes::svgr!(<g>
                <rect x="10" y={y} width={SIDEBAR - 20.0} height="25" rx="6" fill={TINT} opacity={if on { 1.0 } else { 0.0 }} />
                <rect x="18" y={y + 3.5} width="18" height="18" rx="4.5" fill={*color} stroke="#fff" stroke-opacity={if on { 0.5 } else { 0.0 }} stroke-width="0.8" />
                <text x="44" y={y + 17.0} font-family={TEXT} font-size="12.5" fill={if on { "#fff" } else { INK }}>{*label}</text>
            </g>)
        })
        .collect();
    fframes::svgr!(<g>
        <path d={format!("M12 0 H{SIDEBAR} V{WH} H12 Q0 {WH} 0 {} V12 Q0 0 12 0 Z", WH - 12.0)} fill="#e9e9ee" />
        <rect x={SIDEBAR - 0.5} y="0" width="1" height={WH} fill={LINE} />
        {traffic_lights(20.0, 22.0)}
        <rect x="12" y="46" width={SIDEBAR - 24.0} height="26" rx="7" fill="#dcdce2" />
        <circle cx="26" cy="58.5" r="4.2" fill="none" stroke={SECOND} stroke-width="1.4" />
        <path d="M29.2 61.7 L32 64.5" stroke={SECOND} stroke-width="1.4" stroke-linecap="round" />
        <text x="38" y="63" font-family={TEXT} font-size="12.5" fill={SECOND}>"Search"</text>
        {items}
    </g>)
}

fn list_row(y: f32, icon: Svgr<'static>, name: &'static str, on: f32, opacity: f32) -> Svgr<'static> {
    fframes::svgr!(<g opacity={opacity}>
        {icon}
        <text x={LIST_X + 46.0} y={y + 24.5} font-family={TEXT} font-size="13" fill={INK}>{name}</text>
        {switch(LIST_X + LIST_W - 46.0, y + 10.0, on)}
        <rect x={LIST_X + 46.0} y={y + ROW - 0.5} width={LIST_W - 46.0} height="1" fill={LINE} />
    </g>)
}

/// The privacy pane: a list of apps, with the app added on top once `added` reaches 1.
fn privacy_pane(added: f32) -> Svgr<'static> {
    let y = LIST_Y + ROW * added;
    let height = ROW * (2.0 + added) + LIST_FOOT;
    let foot = LIST_Y + height - LIST_FOOT;
    fframes::svgr!(<g>
        <text x={LIST_X + 44.0} y="32" font-family={TEXT} font-weight="600" font-size="15" fill={INK}>"Accessibility"</text>
        <text x={LIST_X} y="92" font-family={TEXT} font-size="12" fill={SECOND}>"Allow the applications below to control your computer."</text>
        <rect x={LIST_X} y={LIST_Y} width={LIST_W} height={height} rx="8" fill="#f6f6f8" stroke={LINE} stroke-width="1" />
        {list_row(LIST_Y, app_icon(LIST_X + 10.0, LIST_Y + 7.0, 26.0), "MyApp", 1.0, ease_out(span(added, 0.4, 0.6)))}
        {list_row(y, fframes::svgr!(<g>
            <rect x={LIST_X + 12.0} y={y + 9.0} width="22" height="22" rx="5.5" fill="#c7c7cc" />
            <path d={format!("M{} {} h10 M{} {} h7 M{} {} h9", LIST_X + 17.0, y + 16.0, LIST_X + 17.0, y + 20.0, LIST_X + 17.0, y + 24.0)} stroke="#fff" stroke-width="1.6" stroke-linecap="round" />
        </g>), "Script Editor", 0.0, 1.0)}
        {list_row(y + ROW, fframes::svgr!(<g>
            <rect x={LIST_X + 12.0} y={y + ROW + 9.0} width="22" height="22" rx="5.5" fill="#1d1d1f" />
            <path d={format!("M{} {} l4 3.5 l-4 3.5 M{} {} h5", LIST_X + 17.0, y + ROW + 16.0, LIST_X + 24.0, y + ROW + 24.0)} fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
        </g>), "Terminal", 1.0, 1.0)}
        <path d={format!("M{} {} h9 M{} {} v9 M{} {} h9", LIST_X + 14.0, foot + 15.0, LIST_X + 18.5, foot + 10.5, LIST_X + 40.0, foot + 15.0)} stroke={SECOND} stroke-width="1.4" stroke-linecap="round" />
    </g>)
}

/// Login Items & Extensions with the Network Extensions sheet open; `on` is the switch.
fn extension_pane(on: f32) -> Svgr<'static> {
    let [sx, sy, sw, sh] = SHEET;
    let [rx, ry, rw, rh] = SHEET_ROW;
    let rows: Vec<Svgr> = ["Network Extensions", "Endpoint Security Extensions", "Driver Extensions"]
        .into_iter()
        .enumerate()
        .map(|(i, name)| {
            let y = LIST_Y + 20.0 + i as f32 * ROW;
            fframes::svgr!(<g>
                <text x={LIST_X + 14.0} y={y + 24.5} font-family={TEXT} font-size="13" fill={INK}>{name}</text>
                <circle cx={LIST_X + LIST_W - 22.0} cy={y + 20.0} r="8" fill="none" stroke={SECOND} stroke-width="1.2" />
                <rect x={LIST_X + 14.0} y={y + ROW - 0.5} width={LIST_W - 14.0} height="1" fill={LINE} />
            </g>)
        })
        .collect();
    fframes::svgr!(<g>
        <text x={LIST_X + 44.0} y="32" font-family={TEXT} font-weight="600" font-size="15" fill={INK}>"Login Items & Extensions"</text>
        <text x={LIST_X} y={LIST_Y + 8.0} font-family={TEXT} font-weight="600" font-size="13" fill={INK}>"Extensions"</text>
        <rect x={LIST_X} y={LIST_Y + 20.0} width={LIST_W} height={ROW * 3.0} rx="8" fill="#f6f6f8" stroke={LINE} stroke-width="1" />
        {rows}
        <path d={format!("M{SIDEBAR} 0 H{} Q{WW} 0 {WW} 12 V{} Q{WW} {WH} {} {WH} H{SIDEBAR} Z", WW - 12.0, WH - 12.0, WW - 12.0)} fill="#000" fill-opacity="0.14" />
        <rect x={sx} y={sy} width={sw} height={sh} rx="12" fill="#fff" filter="url(#panel-shadow)" />
        <text x={sx + 20.0} y={sy + 34.0} font-family={TEXT} font-weight="600" font-size="15" fill={INK}>"Network Extensions"</text>
        <rect x={rx} y={ry} width={rw} height={rh} rx="8" fill="#f6f6f8" stroke={LINE} stroke-width="1" />
        {app_icon(rx + 10.0, ry + 10.0, 28.0)}
        <text x={rx + 48.0} y={ry + 22.0} font-family={TEXT} font-size="13" fill={INK}>"Example VPN"</text>
        <text x={rx + 48.0} y={ry + 37.0} font-family={TEXT} font-size="11" fill={SECOND}>"MyApp"</text>
        {switch(rx + rw - 48.0, ry + 14.0, on)}
        {button(sx + sw - 84.0, sy + sh - 44.0, 64.0, 24.0, "Done", true, true)}
    </g>)
}

/// System Settings' window in its own coordinates.
fn settings_window(mode: Mode, changed: f32) -> Svgr<'static> {
    let (selected, pane) = match mode {
        Mode::Drag => (13, privacy_pane(changed)),
        Mode::Toggle => (3, extension_pane(changed)),
    };
    fframes::svgr!(<g>
        <rect x="0" y="0" width={WW} height={WH} rx="12" fill="#fff" filter="url(#window-shadow)" />
        {sidebar(selected)}
        <path d={format!("M{} 22 l-6 6 l6 6 M{} 22 l6 6 l-6 6", LIST_X + 8.0, LIST_X + 24.0)} fill="none" stroke={SECOND} stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
        {pane}
        <rect x="0.5" y="0.5" width={WW - 1.0} height={WH - 1.0} rx="11.5" fill="none" stroke="#000" stroke-opacity="0.18" stroke-width="1" />
    </g>)
}

/// The Touch ID prompt; `ok` turns the fingerprint into a check.
fn auth_prompt(ok: f32) -> Svgr<'static> {
    let [x, y, w, h] = AUTH;
    let cx = x + w / 2.0;
    let rings: Vec<Svgr> = [7.0_f32, 13.0, 19.0, 25.0]
        .into_iter()
        .map(|r| {
            let d = format!("M{} {} A{r} {r} 0 1 1 {} {}", cx - r * 0.94, y + 62.0 + r * 0.34, cx + r * 0.94, y + 62.0 + r * 0.34);
            fframes::svgr!(<path d={d} fill="none" stroke="#ff375f" stroke-width="2.6" stroke-linecap="round" />)
        })
        .collect();
    fframes::svgr!(<g>
        <rect x={x} y={y} width={w} height={h} rx="14" fill="#f4f4f6" filter="url(#panel-shadow)" />
        <g opacity={1.0 - ok}>{rings}</g>
        <g opacity={ok}>{check(cx, y + 60.0, 26.0)}</g>
        <text x={cx} y={y + 116.0} text-anchor="middle" font-family={TEXT} font-weight="600" font-size="13" fill={INK}>"System Settings"</text>
        <text x={cx} y={y + 136.0} text-anchor="middle" font-family={TEXT} font-size="11.5" fill={INK}>"Touch ID or enter your password"</text>
        <text x={cx} y={y + 151.0} text-anchor="middle" font-family={TEXT} font-size="11.5" fill={INK}>"to allow this."</text>
        {button(x + 20.0, y + h - 46.0, 118.0, 26.0, "Use Password…", false, true)}
        {button(x + 148.0, y + h - 46.0, 82.0, 26.0, "Cancel", false, true)}
    </g>)
}

// ---------------------------------------------------------------------------------------------
// The guide.

/// What the highlight is around: the list or the switch, then the Touch ID prompt.
fn target(mode: Mode, d: f32, b: &Beats) -> [f32; 4] {
    let from = match mode {
        Mode::Drag => [WX + LIST_X, WY + LIST_Y, LIST_W, ROW * 2.0 + LIST_FOOT],
        Mode::Toggle => [WX + SHEET_ROW[0], WY + SHEET_ROW[1], SHEET_ROW[2], SHEET_ROW[3]],
    };
    let p = ease_in_out(span(d, b.auth_in, 0.3));
    std::array::from_fn(|i| lerp(from[i], AUTH[i], p))
}

/// The dimmed window with a pulsing ring around the target.
fn spotlight(mode: Mode, d: f32, b: &Beats) -> Svgr<'static> {
    let alpha = ease_out(span(d, b.guide, 0.3)) * (1.0 - span(d, b.auth_out, 0.2));
    if alpha <= 0.0 {
        return Svgr::empty();
    }
    let [x, y, w, h] = target(mode, d, b);
    let dragging = d >= b.grab && d < b.drop;
    let pulse = 0.5 - 0.5 * (d * 2.0 * PI / 1.8).cos();
    let dim = format!("{} {}", round_rect(WX, WY, WW, WH, 12.0), round_rect(x, y, w, h, 10.0));
    fframes::svgr!(<g opacity={alpha}>
        <path d={dim} fill="#000" fill-opacity="0.45" fill-rule="evenodd" />
        <rect x={x} y={y} width={w} height={h} rx="10" fill="none" stroke={TINT} stroke-width="5" opacity={0.9 * (1.0 - pulse)} filter="url(#glow-near)" />
        <rect x={x} y={y} width={w} height={h} rx="10" fill="none" stroke={TINT} stroke-width="7" opacity={0.9 * pulse} filter="url(#glow-far)" />
        <rect x={x} y={y} width={w} height={h} rx="10" fill={TINT} fill-opacity={if dragging { 0.18 } else { 0.08 }} stroke={TINT} stroke-width={if dragging { 5.0 } else { 3.0 }} />
    </g>)
}

/// The side panel: title, the app's icon, what to do, an arrow at the window, and Cancel.
fn side_panel(mode: Mode, d: f32, b: &Beats) -> Svgr<'static> {
    let alpha = ease_out(span(d, b.guide, 0.3)) * (1.0 - span(d, b.back, 0.25));
    if alpha <= 0.0 {
        return Svgr::empty();
    }
    let (title, lines): (&str, [&str; 3]) = if d >= b.done {
        ("Almost Done", ["Returning to MyApp…", "", ""])
    } else if d >= b.auth_in {
        ("Confirm It's You", ["Use Touch ID or enter your", "password to allow MyApp.", ""])
    } else {
        match mode {
            Mode::Drag => ("Grant Accessibility", ["Drag this icon into the", "highlighted list in System", "Settings."]),
            Mode::Toggle => ("Allow Network Extension", ["Turn on the switch next to", "Example VPN in System", "Settings."]),
        }
    };
    let dragging = d >= b.grab && d < b.drop + 0.2;
    let cx = PX + PW / 2.0;
    let slide = (1.0 - ease_out(span(d, b.guide, 0.35))) * 14.0;
    let hint: Vec<Svgr> = lines
        .into_iter()
        .enumerate()
        .map(|(i, line)| fframes::svgr!(<text x={cx} y={PY + 176.0 + i as f32 * 16.0} text-anchor="middle" font-family={TEXT} font-size="12" fill={SECOND}>{line}</text>))
        .collect();
    fframes::svgr!(<g opacity={alpha} transform={format!("translate({slide} 0)")}>
        <rect x={PX} y={PY} width={PW} height={PH} rx="16" fill="#f2f2f5" fill-opacity="0.97" filter="url(#panel-shadow)" />
        <rect x={PX + 0.5} y={PY + 0.5} width={PW - 1.0} height={PH - 1.0} rx="15.5" fill="none" stroke={TINT} stroke-opacity="0.6" stroke-width="1" />
        <text x={cx} y={PY + 40.0} text-anchor="middle" font-family={TEXT} font-weight="600" font-size="15" fill={INK}>{title}</text>
        <g opacity={if dragging { 0.35 } else { 1.0 }}>{app_icon(ICON[0] - 44.0, ICON[1] - 44.0, 88.0)}</g>
        {hint}
        <path d={format!("M{} {} l-8 7 l8 7 M{} {} h20", cx - 3.0, PY + 229.0, cx - 11.0, PY + 236.0)} fill="none" stroke={TINT} stroke-width="3" stroke-linecap="round" stroke-linejoin="round" />
        {button(cx - 34.0, PY + 258.0, 68.0, 22.0, "Cancel", false, true)}
    </g>)
}

/// The drag hint: a hand carries a copy of the icon to the list, as `GhostFlight` does.
fn ghost(d: f32, b: &Beats) -> Svgr<'static> {
    let (lift, travel, drop, rest) = (0.35, 1.2, 0.4, 1.1);
    let t = d - b.ghost;
    if t < 0.0 || d >= b.grab {
        return Svgr::empty();
    }
    let t = t % (lift + travel + drop + rest);
    if t >= lift + travel + drop {
        return Svgr::empty();
    }
    let p = ease_in_out(span(t, lift, travel));
    let arc = (((ICON[0] - DROP[0]).hypot(ICON[1] - DROP[1])) * 0.3).min(140.0);
    let control = [(ICON[0] + DROP[0]) / 2.0, ICON[1].min(DROP[1]) - arc];
    let at: [f32; 2] = std::array::from_fn(|i| {
        (1.0 - p).powi(2) * ICON[i] + 2.0 * (1.0 - p) * p * control[i] + p * p * DROP[i]
    });
    let opacity = 0.9 * span(t, 0.0, lift) * (1.0 - span(t, lift + travel, drop));
    let scale = if t < lift {
        lerp(1.0, 1.15, ease_out(t / lift))
    } else if t < lift + travel {
        lerp(1.15, 1.0, p)
    } else {
        lerp(1.0, 0.7, span(t, lift + travel, drop))
    };
    let hand = if t < lift * 0.6 || t >= lift + travel { Pointer::OpenHand } else { Pointer::ClosedHand };
    fframes::svgr!(<g opacity={opacity}>
        <g transform={grow(at, scale)} filter="url(#soft-shadow)">{app_icon(at[0] - 36.0, at[1] - 36.0, 72.0)}</g>
        {pointer(at[0] + 6.0, at[1] + 10.0, hand, false)}
    </g>)
}

/// Where the pointer waits once it has nothing left to do.
pub const REST: [f32; 2] = [DROP[0] + 70.0, DROP[1] + 190.0];

/// Where the pointer is while the guide is up: on its way to the icon, dragging it to the
/// list, then out of the way. For a switch it goes there and clicks.
pub fn guide_pointer(mode: Mode, d: f32, b: &Beats, from: [f32; 2]) -> ([f32; 2], Pointer) {
    let rest = REST;
    match mode {
        Mode::Drag => {
            let hold = [ICON[0] + 6.0, ICON[1] + 10.0];
            let keys = [(b.reach, from), (b.grab - 0.15, hold), (b.grab + 0.1, hold), (b.drop - 0.08, DROP), (b.drop + 0.2, DROP), (b.drop + 0.9, rest)];
            let mut at = track(d, &keys);
            // The drag rises a little on the way, like the hint.
            at[1] -= 50.0 * (span(d, b.grab + 0.1, b.drop - b.grab - 0.18) * PI).sin();
            let kind = if d >= b.grab && d < b.drop {
                Pointer::ClosedHand
            } else if d >= b.grab - 0.15 && d < b.grab {
                Pointer::OpenHand
            } else {
                Pointer::Arrow
            };
            (at, kind)
        }
        Mode::Toggle => {
            let keys = [(b.reach, from), (b.drop - 0.12, SWITCH), (b.auth_in + 0.3, SWITCH), (b.auth_in + 1.0, rest)];
            (track(d, &keys), Pointer::Arrow)
        }
    }
}

/// The icon under the pointer during the drag.
fn dragged_icon(d: f32, b: &Beats, at: [f32; 2]) -> Svgr<'static> {
    if d < b.grab || d >= b.drop + 0.2 {
        return Svgr::empty();
    }
    let landing = span(d, b.drop, 0.2);
    let center = [at[0] - 6.0, at[1] - 10.0];
    fframes::svgr!(<g opacity={0.92 * (1.0 - landing)} transform={grow(center, lerp(1.0, 0.5, landing))} filter="url(#soft-shadow)">
        {app_icon(center[0] - 36.0, center[1] - 36.0, 72.0)}
    </g>)
}

/// Everything the guide shows between `b.open` and `b.back`, without the pointer.
/// `pointer_at` is where the pointer is, for the icon it drags.
pub fn guide_stage(mode: Mode, d: f32, b: &Beats, pointer_at: [f32; 2]) -> Svgr<'static> {
    let shown = ease_out(span(d, b.open, 0.25)) * (1.0 - span(d, b.back, 0.3));
    if shown <= 0.0 {
        return Svgr::empty();
    }
    let scale = lerp(0.94, 1.0, spring(d, b.open)) * lerp(1.0, 0.97, span(d, b.back, 0.3));
    let changed = match mode {
        Mode::Drag => ease_out(span(d, b.done, 0.4)),
        Mode::Toggle => ease_out(span(d, b.done, 0.2)),
    };
    let auth = ease_out(span(d, b.auth_in, 0.25)) * (1.0 - span(d, b.auth_out, 0.2));
    let prompt = if auth > 0.0 {
        fframes::svgr!(<g opacity={auth} transform={grow([AUTH[0] + AUTH[2] / 2.0, AUTH[1] + AUTH[3] / 2.0], lerp(0.9, 1.0, ease_out(span(d, b.auth_in, 0.25))))}>
            {auth_prompt(ease_out(span(d, b.auth_ok, 0.2)))}
        </g>)
    } else {
        Svgr::empty()
    };
    fframes::svgr!(<g>
        <g opacity={shown}>
            <g transform={grow([WX + WW / 2.0, WY + WH / 2.0], scale)}>
                <g transform={format!("translate({WX} {WY})")}>{settings_window(mode, changed)}</g>
            </g>
            {prompt}
            {spotlight(mode, d, b)}
        </g>
        {side_panel(mode, d, b)}
        {if mode == Mode::Drag { ghost(d, b) } else { Svgr::empty() }}
        {if mode == Mode::Drag { dragged_icon(d, b, pointer_at) } else { Svgr::empty() }}
    </g>)
}

// ---------------------------------------------------------------------------------------------
// The app.

/// The app's own window: a list of permissions, the first one waiting for a grant.
pub fn app_window(mode: Mode, d: f32, b: &Beats) -> Svgr<'static> {
    let shown = (1.0 - span(d, b.open, 0.25)).max(ease_out(span(d, b.back, 0.35)));
    if shown <= 0.0 {
        return Svgr::empty();
    }
    let scale = if d < b.back { lerp(1.0, 0.97, span(d, b.open, 0.25)) } else { lerp(0.97, 1.0, spring(d, b.back)) };
    let names: [(&str, &str); 3] = match mode {
        Mode::Drag => [("Accessibility", "Control the pointer and keyboard"), ("Full Disk Access", "Read files in protected folders"), ("Screen Recording", "Capture the screen")],
        Mode::Toggle => [("Example VPN", "Network extension"), ("Accessibility", "Control the pointer and keyboard"), ("Full Disk Access", "Read files in protected folders")],
    };
    let granted = spring(d, b.granted);
    let rows: Vec<Svgr> = names
        .into_iter()
        .enumerate()
        .map(|(i, (name, detail))| {
            let y = AY + 100.0 + i as f32 * 64.0;
            let right = AX + AW - 32.0;
            let state = match (i, mode) {
                (0, _) => fframes::svgr!(<g>
                    <g opacity={1.0 - span(d, b.granted, 0.15)}>{button(GRANT[0] - 42.0, y + 18.0, 84.0, 28.0, "Grant…", false, true)}</g>
                    <g opacity={span(d, b.granted, 0.15)}>
                        <g transform={grow([right - 78.0, y + 32.0], granted)}>{check(right - 78.0, y + 32.0, 9.0)}</g>
                        <text x={right - 62.0} y={y + 36.5} font-family={TEXT} font-weight="500" font-size="13" fill={INK}>"Granted"</text>
                    </g>
                </g>),
                (1, _) | (2, Mode::Toggle) => fframes::svgr!(<g>
                    {check(right - 78.0, y + 32.0, 9.0)}
                    <text x={right - 62.0} y={y + 36.5} font-family={TEXT} font-weight="500" font-size="13" fill={INK}>"Granted"</text>
                </g>),
                _ => button(GRANT[0] - 42.0, y + 18.0, 84.0, 28.0, "Grant…", false, true),
            };
            fframes::svgr!(<g>
                <rect x={AX + 24.0} y={y} width={AW - 48.0} height="56" rx="10" fill="#f6f6f8" stroke={LINE} stroke-width="1" />
                <text x={AX + 42.0} y={y + 26.0} font-family={TEXT} font-weight="500" font-size="14" fill={INK}>{name}</text>
                <text x={AX + 42.0} y={y + 43.0} font-family={TEXT} font-size="11.5" fill={SECOND}>{detail}</text>
                {state}
            </g>)
        })
        .collect();
    fframes::svgr!(<g opacity={shown} transform={grow([AX + AW / 2.0, AY + AH / 2.0], scale)}>
        <rect x={AX} y={AY} width={AW} height={AH} rx="12" fill="#fff" filter="url(#window-shadow)" />
        <rect x={AX + 0.5} y={AY + 0.5} width={AW - 1.0} height={AH - 1.0} rx="11.5" fill="none" stroke="#000" stroke-opacity="0.18" stroke-width="1" />
        {traffic_lights(AX + 20.0, AY + 22.0)}
        <text x={AX + AW / 2.0} y={AY + 27.0} text-anchor="middle" font-family={TEXT} font-weight="600" font-size="13" fill={INK}>"MyApp"</text>
        <rect x={AX} y={AY + 44.0} width={AW} height="1" fill={LINE} />
        {app_icon(AX + 22.0, AY + 54.0, 34.0)}
        <text x={AX + 64.0} y={AY + 77.0} font-family={TEXT} font-weight="600" font-size="17" fill={INK}>"Permissions"</text>
        {rows}
    </g>)
}

/// The whole demo on the 960x600 stage: the app, the guide and the pointer.
pub fn demo(mode: Mode, d: f32, b: &Beats) -> Svgr<'static> {
    let start = [GRANT[0] - 110.0, GRANT[1] + 190.0];
    let (at, kind) = if d < b.reach {
        (track(d, &[(0.1, start), (b.click - 0.15, GRANT)]), Pointer::Arrow)
    } else {
        guide_pointer(mode, d, b, GRANT)
    };
    let clicks = match mode {
        Mode::Drag => vec![b.click],
        Mode::Toggle => vec![b.click, b.drop],
    };
    fframes::svgr!(<g>
        {app_window(mode, d, b)}
        {guide_stage(mode, d, b, at)}
        {cursor(d, at, kind, &clicks)}
    </g>)
}

// ---------------------------------------------------------------------------------------------

/// The command line every binary shares: `render`, `frame`, `strip` and the rest of fframes' CLI.
pub fn run<V: Video + Send + Sync>(video: &V, media: &Media, output: &str) -> ExitCode {
    let args = cli::parse::<cli::NoArgs>();
    let gpu = SkiaMetalCtx::new(V::WIDTH, V::HEIGHT).expect("GPU context");
    cli::new(
        video,
        RenderOptions {
            media: Some(media),
            video_encoder_options: EncoderOptions {
                preferred_encoder: Some("h264_videotoolbox"),
                bitrate: Some(12_000_000),
                codec_params: Some(&[("profile", "high"), ("allow_sw", "1")]),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .args(args)
    .default_output(output)
    .backend(
        SkiaFFramesRenderer::new_metal(
            &gpu,
            SkiaPipelineConfig { concurrency_policy: SkiaPipelineConcurrencyPolicy::MaxPerformance, ..Default::default() },
        )
        .expect("skia renderer"),
    )
    .run()
}
