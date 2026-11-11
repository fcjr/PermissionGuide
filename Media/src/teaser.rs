//! The release teaser, cut for a social feed: 1920x1080 at 60 fps, 24 s, with the soundtrack
//! from `sound/soundtrack.rs`. It reads without sound (every beat has a caption), opens on
//! the problem in the first two seconds, and cuts hard on the bar instead of fading.
//!
//! Seven scenes: the instructions nobody follows, the name, the drag, the code, the .pkg
//! installer, what else it covers, and where to get it. Their lengths and events are in
//! `timing.rs`.
use crate::clips::installer_demo;
use crate::timing::*;
use crate::*;
use fframes::{AudioMap, AudioTimestamp, AudioTrack, Color, Duration, FFramesContext, Frame, Scene, Scenes};

const WHITE: &str = "#ffffff";
const BLACK: &str = "#050505";
const ACID: &str = "#c8ff2e";
const HOT: &str = "#ff2e63";
const GREY: &str = "#8b8b8b";

pub struct Teaser<'a> {
    pub media: &'a Media,
}

impl<'a> Teaser<'a> {
    pub fn new(media: &'a Media) -> Self {
        Self { media }
    }
}

/// Where a scene cuts in. Each one gets a white flash.
const CUTS: [f32; 6] = [TITLE_AT, DEMO_AT, CODE_AT, INSTALLER_AT, MORE_AT, END_AT];
/// Hits that shake the frame: the stamp, the title, the drop, the grant, the end card.
const HITS: [f32; 5] = [HOOK_STAMP_AT, TITLE_AT, DEMO_AT + TEASER_DRAG.drop, DEMO_AT + TEASER_DRAG.granted, END_AT];

impl Video for Teaser<'_> {
    const FPS: usize = 60;
    const WIDTH: usize = 1920;
    const HEIGHT: usize = 1080;
    const BACKGROUND_COLOR: Color = Color::BLACK;

    fn duration(&self) -> Duration<'_> {
        Duration::Auto
    }

    /// Music and interface sounds, synthesized to this timeline by `build.rs`.
    fn audio(&self) -> AudioMap<'_> {
        AudioMap::from([AudioTrack::new("soundtrack.wav", AudioTimestamp::Second(0.0)..AudioTimestamp::Eof)])
    }

    fn define_scenes(&self) -> Scenes<'_> {
        Scenes::from(vec![&Hook as &dyn Scene, &Title, &Demo, &Code, &Installer, &More, &End])
    }

    fn render_frame<'a>(&'a self, frame: Frame, ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
        let t = frame.seconds();
        let [dx, dy] = shake(t, &HITS, 16.0);
        let flash = CUTS.iter().map(|cut| if t >= *cut { 1.0 - span(t, *cut, 0.14) } else { 0.0 }).fold(0.0, f32::max);
        // The grid drifts, so even a held frame is moving.
        let drift = (t * 14.0) % 80.0;
        fframes::svgr!(
            <svg xmlns="http://www.w3.org/2000/svg" width={Self::WIDTH} height={Self::HEIGHT} viewBox="0 0 1920 1080">
                {defs()}
                <defs>
                    <pattern id="grid" patternUnits="userSpaceOnUse" width="80" height="80" patternTransform={format!("translate(0 {drift})")}>
                        <path d="M80 0 H0 V80" fill="none" stroke="#fff" stroke-opacity="0.055" stroke-width="1" />
                    </pattern>
                    <radialGradient id="acid-glow" cx="0.5" cy="0.5" r="0.5">
                        <stop offset="0" stop-color={ACID} stop-opacity="0.2" />
                        <stop offset="1" stop-color={ACID} stop-opacity="0" />
                    </radialGradient>
                    <radialGradient id="vignette" cx="0.5" cy="0.5" r="0.75">
                        <stop offset="0.55" stop-color="#000" stop-opacity="0" />
                        <stop offset="1" stop-color="#000" stop-opacity="0.75" />
                    </radialGradient>
                </defs>
                <rect width="1920" height="1080" fill={BLACK} />
                <rect x="-40" y="-120" width="2000" height="1320" fill="url(#grid)" />
                <ellipse cx="960" cy="1180" rx="1100" ry="520" fill="url(#acid-glow)" />
                <g transform={format!("translate({dx} {dy})")}>{ctx.render_scenes(&frame)}</g>
                <rect width="1920" height="1080" fill="url(#vignette)" />
                <rect width="1920" height="1080" fill={WHITE} opacity={flash * 0.85} />
            </svg>
        )
    }
}

// ---------------------------------------------------------------------------------------------
// Motion and type.

/// A decaying jolt after each of `hits`.
fn shake(t: f32, hits: &[f32], amount: f32) -> [f32; 2] {
    hits.iter().filter(|hit| t >= **hit).fold([0.0, 0.0], |[x, y], hit| {
        let since = t - hit;
        let fall = (-since * 13.0).exp() * amount;
        [x + fall * (since * 95.0).sin(), y + fall * (since * 71.0).cos()]
    })
}

/// Lands hard: starts big and settles on 1.
fn slam(t: f32, at: f32) -> f32 {
    lerp(1.7, 1.0, ease_out(span(t, at, 0.16)))
}

/// Rough width of heavy capitals in SF Pro Display.
fn caps_width(text: &str, size: f32) -> f32 {
    text.chars().count() as f32 * size * 0.64
}

/// Heavy centered type. `split` pulls cyan and magenta copies apart, for a glitch.
fn heavy(x: f32, y: f32, size: f32, fill: &'static str, text: &'static str, split: f32) -> Svgr<'static> {
    let ghosts = if split > 0.3 {
        fframes::svgr!(<g opacity="0.85">
            <text x={x - split} y={y} text-anchor="middle" font-family={DISPLAY} font-weight="900" font-size={size} letter-spacing={-size * 0.03} fill="#00e5ff">{text}</text>
            <text x={x + split} y={y + split * 0.3} text-anchor="middle" font-family={DISPLAY} font-weight="900" font-size={size} letter-spacing={-size * 0.03} fill="#ff2bd6">{text}</text>
        </g>)
    } else {
        Svgr::empty()
    };
    fframes::svgr!(<g>
        {ghosts}
        <text x={x} y={y} text-anchor="middle" font-family={DISPLAY} font-weight="900" font-size={size} letter-spacing={-size * 0.03} fill={fill}>{text}</text>
    </g>)
}

/// The glitch on a title: wide at `at`, gone 0.35 s later, with one late twitch.
fn glitch(t: f32, at: f32) -> f32 {
    let first = 26.0 * (1.0 - span(t, at, 0.35));
    let twitch = if t > at + 0.8 && t < at + 0.86 { 10.0 } else { 0.0 };
    if t < at { 0.0 } else { first.max(twitch) }
}

/// Black capitals on an acid block, slammed in at `at`, centered on (x, y).
fn tag(t: f32, at: f32, x: f32, y: f32, size: f32, text: &'static str) -> Svgr<'static> {
    if t < at {
        return Svgr::empty();
    }
    let w = caps_width(text, size) + size * 1.1;
    let h = size * 1.55;
    fframes::svgr!(<g opacity={span(t, at, 0.05)} transform={grow([x, y], slam(t, at))}>
        <rect x={x - w / 2.0} y={y - h / 2.0} width={w} height={h} fill={ACID} />
        <text x={x} y={y + size * 0.36} text-anchor="middle" font-family={DISPLAY} font-weight="900" font-size={size} letter-spacing={-size * 0.02} fill={BLACK}>{text}</text>
    </g>)
}

/// The one caption out of `captions` (start, end, text) that is up at `t`.
fn caption(t: f32, captions: &[(f32, f32, &'static str)]) -> Svgr<'static> {
    captions
        .iter()
        .find(|(start, end, _)| t >= *start && t < *end)
        .map(|(start, _, text)| tag(t, *start, 960.0, 992.0, 72.0, text))
        .unwrap_or_else(Svgr::empty)
}

macro_rules! scene {
    ($name:ident, $seconds:expr) => {
        #[derive(Debug)]
        struct $name;

        impl Scene for $name {
            fn duration(&self) -> Duration<'_> {
                Duration::Seconds($seconds)
            }

            fn render_frame<'a>(&'a self, frame: Frame, _ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
                self.draw(frame.seconds())
            }
        }
    };
}

// ---------------------------------------------------------------------------------------------

scene!(Hook, HOOK_SECONDS);

impl Hook {
    /// The instructions every app writes, then the verdict stamped across them.
    fn draw(&self, t: f32) -> Svgr<'static> {
        let stamped = t >= HOOK_STAMP_AT;
        let steps: Vec<Svgr> = HOOK_STEPS
            .into_iter()
            .enumerate()
            .map(|(i, step)| {
                let at = HOOK_STEPS_AT + i as f32 * HOOK_STEP_EVERY;
                if t < at {
                    return Svgr::empty();
                }
                let y = 330.0 + i as f32 * 104.0;
                let slide = (1.0 - ease_out(span(t, at, 0.14))) * -70.0;
                let strike = ease_out(span(t, HOOK_STAMP_AT + 0.05 + i as f32 * 0.04, 0.18));
                let width = 96.0 + tw(step, 66.0) * 1.08;
                let line = if strike > 0.0 {
                    fframes::svgr!(<rect x="290" y={y - 26.0} width={(width + 20.0) * strike} height="8" fill={HOT} />)
                } else {
                    Svgr::empty()
                };
                fframes::svgr!(<g transform={format!("translate({slide} 0)")}>
                    <g opacity={if stamped { 0.38 } else { 1.0 }}>
                        <text x="300" y={y} font-family={MONO} font-size="40" fill={ACID}>{format!("0{}", i + 1)}</text>
                        <text x="396" y={y} font-family={DISPLAY} font-weight="700" font-size="66" letter-spacing="-1.2" fill={WHITE}>{step}</text>
                    </g>
                    {line}
                </g>)
            })
            .collect();
        let stamp = if stamped {
            fframes::svgr!(<g transform="rotate(-5 960 600)">{tag(t, HOOK_STAMP_AT, 960.0, 600.0, 168.0, "NOBODY DOES THIS.")}</g>)
        } else {
            Svgr::empty()
        };
        fframes::svgr!(<g>
            <text x="300" y="204" font-family={MONO} font-size="38" letter-spacing="2" fill={GREY}>"HOW YOUR APP GETS A macOS PERMISSION TODAY"</text>
            <rect x="300" y="232" width={(1320.0 * ease_out(span(t, 0.0, 0.5))).max(1.0)} height="4" fill={ACID} />
            {steps}
            {stamp}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(Title, TITLE_SECONDS);

impl Title {
    fn draw(&self, t: f32) -> Svgr<'static> {
        fframes::svgr!(<g>
            <g transform={grow([960.0, 300.0], slam(t, 0.0))}>{mark(860.0, 200.0, 200.0)}</g>
            <g transform={grow([960.0, 600.0], slam(t, 0.0))}>{heavy(960.0, 660.0, 190.0, WHITE, "PermissionGuide", glitch(t, 0.0))}</g>
            {tag(t, TITLE_SUB_AT, 960.0, 850.0, 84.0, "ONE DRAG. DONE.")}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(Demo, DEMO_SECONDS);

impl Demo {
    /// The drag on the shared stage with a caption slammed in for each step.
    fn draw(&self, t: f32) -> Svgr<'static> {
        let b = &TEASER_DRAG;
        let captions = [
            (0.0, b.open + 0.1, "YOUR APP ASKS."),
            (b.open + 0.1, b.reach + 0.2, "RIGHT PANE. LIT UP."),
            (b.reach + 0.2, b.auth_in, "DRAG IT IN."),
            (b.auth_in, b.done, "TOUCH ID."),
            (b.done, b.back + 0.1, "GRANTED."),
            (b.back + 0.1, DEMO_SECONDS, "BACK IN YOUR APP."),
        ];
        fframes::svgr!(<g>
            <g transform="translate(290 18) scale(1.395)">{demo(Mode::Drag, t, b)}</g>
            {caption(t, &captions)}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(Code, CODE_SECONDS);

impl Code {
    /// The call that does all of it, typed out.
    fn draw(&self, t: f32) -> Svgr<'static> {
        const SIZE: f32 = 44.0;
        const ADVANCE: f32 = SIZE * 0.6;
        let typed = ((t - CODE_TYPE_AT) * CODE_CPS).max(0.0) as usize;
        let total = CODE_LINE.chars().count();
        let mut x = 0;
        let parts: Vec<Svgr> = [("await ", HOT), ("permissions.request(", WHITE), (".accessibility", ACID), (")", WHITE)]
            .into_iter()
            .map(|(part, color)| {
                let shown: String = part.chars().take(typed.saturating_sub(x)).collect();
                let at = 370.0 + x as f32 * ADVANCE;
                x += part.chars().count();
                fframes::svgr!(<text x={at} y="640" font-family={MONO} font-size={SIZE} fill={color}>{shown}</text>)
            })
            .collect();
        let caret = 370.0 + typed.min(total) as f32 * ADVANCE;
        fframes::svgr!(<g>
            <g transform={grow([960.0, 240.0], slam(t, 0.0))}>{heavy(960.0, 290.0, 190.0, WHITE, "ONE LINE.", glitch(t, 0.0))}</g>
            <rect x="300" y="430" width="1320" height="290" fill="#0d0d0d" stroke={ACID} stroke-width="3" />
            <rect x="300" y="430" width="1320" height="52" fill={ACID} />
            <text x="324" y="467" font-family={MONO} font-size="26" fill={BLACK}>"MyApp.swift"</text>
            <text x="370" y="566" font-family={MONO} font-size={SIZE} fill={GREY}>"let permissions = PermissionManager()"</text>
            {parts}
            <rect x={caret + 3.0} y="600" width="22" height="50" fill={ACID} />
            {tag(t, CODE_RESULT_AT, 960.0, 860.0, 72.0, "RETURNS .granted")}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(Installer, INSTALLER_SECONDS);

impl Installer {
    /// The same guide from a .pkg: a Set Up section that finishes before the app first opens.
    fn draw(&self, t: f32) -> Svgr<'static> {
        let i = &TEASER_INSTALLER;
        let captions = [
            (0.0, i.guide.open, "IN YOUR .PKG TOO."),
            (i.guide.open, i.guide.granted, "SETUP, INSIDE THE INSTALLER."),
            (i.guide.granted, INSTALLER_SECONDS, "READY BEFORE FIRST LAUNCH."),
        ];
        fframes::svgr!(<g>
            <g transform="translate(290 18) scale(1.395)">{installer_demo(t, i)}</g>
            {caption(t, &captions)}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(More, MORE_SECONDS);

impl More {
    fn draw(&self, t: f32) -> Svgr<'static> {
        let chips: Vec<Svgr> = MORE_CHIPS
            .into_iter()
            .enumerate()
            .map(|(i, chip)| {
                let at = MORE_CHIPS_AT + i as f32 * MORE_CHIP_EVERY;
                if t < at {
                    return Svgr::empty();
                }
                let (x, y) = (116.0 + (i % 4) as f32 * 428.0, 470.0 + (i / 4) as f32 * 150.0);
                // Each one lands filled, then burns down to an outline.
                let hot = 1.0 - span(t, at, 0.3);
                fframes::svgr!(<g transform={grow([x + 202.0, y + 56.0], slam(t, at))}>
                    <rect x={x} y={y} width="404" height="112" fill="#0d0d0d" stroke={ACID} stroke-width="3" />
                    <rect x={x} y={y} width="404" height="112" fill={ACID} opacity={hot} />
                    <text x={x + 202.0} y={y + 68.0} text-anchor="middle" font-family={DISPLAY} font-weight="700" font-size="35" fill={if hot > 0.5 { BLACK } else { WHITE }}>{chip}</text>
                </g>)
            })
            .collect();
        fframes::svgr!(<g>
            <g transform={grow([960.0, 250.0], slam(t, 0.0))}>{heavy(960.0, 300.0, 138.0, WHITE, "EVEN THE ANNOYING ONES.", glitch(t, 0.0))}</g>
            {chips}
            <text x="960" y="900" text-anchor="middle" font-family={MONO} font-size="36" fill={GREY} opacity={span(t, 1.3, 0.1)}>"Touch ID and Quit & Reopen prompts included."</text>
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(End, END_SECONDS);

impl End {
    fn draw(&self, t: f32) -> Svgr<'static> {
        fframes::svgr!(<g>
            <g transform={grow([960.0, 250.0], slam(t, 0.0))}>{mark(880.0, 170.0, 160.0)}</g>
            <g transform={grow([960.0, 520.0], slam(t, 0.0))}>{heavy(960.0, 560.0, 176.0, WHITE, "PermissionGuide", glitch(t, 0.0))}</g>
            <text x="960" y="654" text-anchor="middle" font-family={DISPLAY} font-weight="700" font-size="52" fill={GREY} opacity={span(t, 0.5, 0.1)}>"Guided permission setup for macOS apps"</text>
            {tag(t, END_LINK_AT, 960.0, 800.0, 66.0, "github.com/fcjr/PermissionGuide")}
            <text x="960" y="950" text-anchor="middle" font-family={MONO} font-size="34" letter-spacing="3" fill={WHITE} opacity={span(t, 1.5, 0.1)}>"OPEN SOURCE / MIT / SWIFT PACKAGE / macOS 14+"</text>
        </g>)
    }
}
