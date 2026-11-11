//! The README's clips: the stage on a wallpaper, 1200x750 at 25 fps (a GIF frame is 40 ms).
use crate::timing::{Beats, DRAG, INSTALLER, INSTALLER_CONTINUE, INSTALLER_FINISH, TOGGLE};
use crate::*;
use fframes::{AudioMap, Color, Duration, FFramesContext, Frame};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ClipKind {
    /// Dragging the app into a privacy list.
    Drag,
    /// Turning on a system extension.
    Extension,
    /// A Set Up step in a .pkg installer.
    Installer,
}

pub struct Clip<'a> {
    pub media: &'a Media,
    pub kind: ClipKind,
}

impl Video for Clip<'_> {
    const FPS: usize = 25;
    const WIDTH: usize = 1200;
    const HEIGHT: usize = 750;
    const BACKGROUND_COLOR: Color = Color::BLACK;

    fn duration(&self) -> Duration<'_> {
        Duration::Seconds(match self.kind {
            ClipKind::Drag => DRAG.end,
            ClipKind::Extension => TOGGLE.end,
            ClipKind::Installer => INSTALLER.end,
        })
    }

    fn audio(&self) -> AudioMap<'_> {
        AudioMap::none()
    }

    fn render_frame<'a>(&'a self, frame: Frame, _ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
        let d = frame.seconds();
        let content = match self.kind {
            ClipKind::Drag => demo(Mode::Drag, d, &DRAG),
            ClipKind::Extension => demo(Mode::Toggle, d, &TOGGLE),
            ClipKind::Installer => installer_demo(d, &INSTALLER),
        };
        fframes::svgr!(
            <svg xmlns="http://www.w3.org/2000/svg" width={Self::WIDTH} height={Self::HEIGHT} viewBox="0 0 960 600">
                {defs()}
                <rect width={STAGE_W} height={STAGE_H} fill="url(#wall)" />
                {content}
            </svg>
        )
    }
}

// ---------------------------------------------------------------------------------------------
// Installer.

const IX: f32 = 170.0;
const IY: f32 = 72.0;
const IW: f32 = 620.0;
const IH: f32 = 456.0;
// Installer's content area is 418x329 pt.
const BOX_X: f32 = IX + 182.0;
const BOX_Y: f32 = IY + 62.0;
const BOX_W: f32 = 418.0;
const BOX_H: f32 = 329.0;
const BOX_CX: f32 = BOX_X + BOX_W / 2.0;
const CONTINUE: [f32; 2] = [IX + IW - 62.0, IY + IH - 30.0];
const OPEN_SETTINGS: [f32; 2] = [BOX_CX, BOX_Y + 213.0];

fn centered(y: f32, size: f32, weight: &'static str, fill: &'static str, text: &'static str) -> Svgr<'static> {
    fframes::svgr!(<text x={BOX_CX} y={y} text-anchor="middle" font-family={TEXT} font-weight={weight} font-size={size} fill={fill}>{text}</text>)
}

/// "Finish setting up MyApp" and the steps ahead.
fn intro_pane() -> Svgr<'static> {
    let steps: Vec<Svgr> = [("Accessibility", false), ("Example VPN", false), ("Certificate", true)]
        .into_iter()
        .enumerate()
        .map(|(i, (title, optional))| {
            let y = BOX_Y + 212.0 + i as f32 * 22.0;
            let x = BOX_CX - 76.0;
            let tag = if optional {
                fframes::svgr!(<text x={x + 22.0 + tw(title, 13.0) + 10.0} y={y} font-family={TEXT} font-size="11" fill={SECOND}>"Optional"</text>)
            } else {
                Svgr::empty()
            };
            fframes::svgr!(<g>
                <rect x={x} y={y - 11.0} width="13" height="13" rx="3.5" fill={TINT} />
                <text x={x + 22.0} y={y} font-family={TEXT} font-size="13" fill={INK}>{title}</text>
                {tag}
            </g>)
        })
        .collect();
    fframes::svgr!(<g>
        {app_icon(BOX_CX - 28.0, BOX_Y + 44.0, 56.0)}
        {centered(BOX_Y + 132.0, 17.0, "700", INK, "Finish setting up MyApp")}
        {centered(BOX_Y + 156.0, 13.0, "400", SECOND, "MyApp needs a few things from macOS. Optional steps")}
        {centered(BOX_Y + 173.0, 13.0, "400", SECOND, "can be set up later.")}
        {steps}
    </g>)
}

/// The Accessibility step: a button that opens the guide, then a check once it's granted.
fn step_pane(d: f32, b: &Beats) -> Svgr<'static> {
    let done = span(d, b.granted, 0.2);
    let cy = BOX_Y + 86.0;
    fframes::svgr!(<g>
        <circle cx={BOX_CX} cy={cy} r="26" fill={TINT} />
        <circle cx={BOX_CX} cy={cy - 12.0} r="4.2" fill="#fff" />
        <path d={format!("M{} {} h30 M{} {} v11 l-7 13 M{} {} l7 13", BOX_CX - 15.0, cy - 3.0, BOX_CX, cy - 3.0, BOX_CX, cy + 8.0)} fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round" />
        {centered(BOX_Y + 142.0, 17.0, "700", INK, "Allow Accessibility")}
        {centered(BOX_Y + 166.0, 13.0, "400", SECOND, "MyApp needs Accessibility. Click below, then drag MyApp")}
        {centered(BOX_Y + 183.0, 13.0, "400", SECOND, "into the highlighted list in System Settings.")}
        <g opacity={1.0 - done}>
            {button(BOX_CX - 82.0, OPEN_SETTINGS[1] - 13.0, 164.0, 26.0, "Open System Settings", false, true)}
            {centered(BOX_Y + 252.0, 11.0, "400", SECOND, "Required to finish setting up MyApp.")}
        </g>
        <g opacity={done}>
            <g transform={grow([BOX_CX - 22.0, OPEN_SETTINGS[1]], spring(d, b.granted))}>{check(BOX_CX - 22.0, OPEN_SETTINGS[1], 8.0)}</g>
            <text x={BOX_CX - 8.0} y={OPEN_SETTINGS[1] + 4.0} font-family={TEXT} font-size="11.5" fill={SECOND}>"Done"</text>
        </g>
    </g>)
}

fn done_pane(d: f32) -> Svgr<'static> {
    let at = [BOX_CX, BOX_Y + 96.0];
    fframes::svgr!(<g>
        <g transform={grow(at, spring(d, INSTALLER_FINISH))}>{check(at[0], at[1], 26.0)}</g>
        {centered(BOX_Y + 154.0, 17.0, "700", INK, "MyApp is ready")}
        {centered(BOX_Y + 180.0, 13.0, "400", SECOND, "MyApp is opening. You can close the installer.")}
        {centered(BOX_Y + 214.0, 13.0, "400", SECOND, "You skipped Certificate. You can set it up later in MyApp.")}
    </g>)
}

/// Installer's window on the Set Up section.
fn installer_window(d: f32, b: &Beats) -> Svgr<'static> {
    let shown = (1.0 - span(d, b.open, 0.25)).max(ease_out(span(d, b.back, 0.35)));
    if shown <= 0.0 {
        return Svgr::empty();
    }
    let scale = if d < b.back { lerp(1.0, 0.97, span(d, b.open, 0.25)) } else { lerp(0.97, 1.0, spring(d, b.back)) };
    let sections: Vec<Svgr> = ["Introduction", "Destination Select", "Installation Type", "Installation", "Set Up", "Summary"]
        .into_iter()
        .enumerate()
        .map(|(i, name)| {
            let y = IY + 84.0 + i as f32 * 26.0;
            let (dot, ink, weight) = match i {
                4 => (TINT, INK, "700"),
                5 => ("#c2c2c7", SECOND, "400"),
                _ => ("#8e8e93", INK, "400"),
            };
            fframes::svgr!(<g>
                <circle cx={IX + 28.0} cy={y - 4.0} r="4.5" fill={dot} />
                <text x={IX + 42.0} y={y} font-family={TEXT} font-weight={weight} font-size="12.5" fill={ink}>{name}</text>
            </g>)
        })
        .collect();
    let to_step = span(d, INSTALLER_CONTINUE + 0.05, 0.2);
    let to_done = span(d, INSTALLER_FINISH, 0.2);
    let last = d >= INSTALLER_FINISH;
    fframes::svgr!(<g opacity={shown} transform={grow([IX + IW / 2.0, IY + IH / 2.0], scale)}>
        <rect x={IX} y={IY} width={IW} height={IH} rx="12" fill="#ececee" filter="url(#window-shadow)" />
        <rect x={IX + 0.5} y={IY + 0.5} width={IW - 1.0} height={IH - 1.0} rx="11.5" fill="none" stroke="#000" stroke-opacity="0.18" stroke-width="1" />
        {traffic_lights(IX + 20.0, IY + 18.0)}
        <text x={IX + IW / 2.0} y={IY + 23.0} text-anchor="middle" font-family={TEXT} font-weight="600" font-size="13" fill={INK}>"Install MyApp"</text>
        <text x={BOX_X} y={IY + 52.0} font-family={TEXT} font-weight="700" font-size="13" fill={INK}>{if last { "Done" } else { "Set Up" }}</text>
        {sections}
        <rect x={BOX_X} y={BOX_Y} width={BOX_W} height={BOX_H} rx="6" fill="#fff" stroke={LINE} stroke-width="1" />
        <g opacity={1.0 - to_step}>{intro_pane()}</g>
        <g opacity={to_step * (1.0 - to_done)}>{step_pane(d, b)}</g>
        <g opacity={to_done}>{done_pane(d)}</g>
        {button(CONTINUE[0] - 134.0, CONTINUE[1] - 12.0, 82.0, 24.0, "Go Back", false, false)}
        {button(CONTINUE[0] - 42.0, CONTINUE[1] - 12.0, 84.0, 24.0, if last { "Close" } else { "Continue" }, true, d < INSTALLER_CONTINUE || d >= b.granted)}
    </g>)
}

/// A .pkg's Set Up section: the intro, a step that runs the guide, and the last pane.
pub fn installer_demo(d: f32, b: &Beats) -> Svgr<'static> {
    let (at, kind) = if d < b.reach {
        let keys = [(0.2, [CONTINUE[0] - 120.0, CONTINUE[1] - 90.0]), (INSTALLER_CONTINUE - 0.15, CONTINUE), (INSTALLER_CONTINUE + 0.3, CONTINUE), (b.click - 0.15, OPEN_SETTINGS)];
        (track(d, &keys), Pointer::Arrow)
    } else {
        guide_pointer(Mode::Drag, d, b, OPEN_SETTINGS)
    };
    fframes::svgr!(<g>
        {installer_window(d, b)}
        {guide_stage(Mode::Drag, d, b, at)}
        {cursor(d, at, kind, &[INSTALLER_CONTINUE, b.click])}
    </g>)
}
