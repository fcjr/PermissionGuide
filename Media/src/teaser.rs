//! The release teaser: 1920x1080 at 60 fps, 28.8 s, with the soundtrack from
//! `sound/soundtrack.rs`. Six scenes: the problem, the name, the drag, the code, what else it
//! covers, and where to get it. Their lengths and events are in `timing.rs`.
use crate::timing::*;
use crate::*;
use fframes::{AudioMap, AudioTimestamp, AudioTrack, Color, Duration, FFramesContext, Frame, Scene, Scenes};

const WHITE: &str = "#ffffff";
const SOFT: &str = "#aeb6e8";
const CARD: &str = "#161c44";
const EDGE: &str = "#2c3476";

pub struct Teaser<'a> {
    pub media: &'a Media,
}

impl<'a> Teaser<'a> {
    pub fn new(media: &'a Media) -> Self {
        Self { media }
    }
}

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
        Scenes::from(vec![&Hook as &dyn Scene, &Title, &Demo, &Code, &More, &End])
    }

    fn render_frame<'a>(&'a self, frame: Frame, ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
        let t = frame.seconds();
        // Two slow halos keep the background from sitting still.
        let (ax, ay) = (500.0 + 160.0 * (t * 0.21).sin(), 300.0 + 90.0 * (t * 0.17).cos());
        let (bx, by) = (1450.0 + 140.0 * (t * 0.19).cos(), 800.0 + 80.0 * (t * 0.23).sin());
        fframes::svgr!(
            <svg xmlns="http://www.w3.org/2000/svg" width={Self::WIDTH} height={Self::HEIGHT} viewBox="0 0 1920 1080">
                {defs()}
                <rect width="1920" height="1080" fill="url(#night)" />
                <circle cx={ax} cy={ay} r="620" fill="url(#halo)" opacity="0.55" />
                <circle cx={bx} cy={by} r="560" fill="url(#halo)" opacity="0.4" />
                {ctx.render_scenes(&frame)}
            </svg>
        )
    }
}

/// Fade a scene in and out over its edges.
fn scene_fade(t: f32, seconds: f32) -> f32 {
    ease_out(span(t, 0.0, 0.3)) * (1.0 - span(t, seconds - 0.25, 0.25))
}

/// A line of text that rises into place at `at`.
fn line(t: f32, at: f32, y: f32, size: f32, family: &'static str, weight: &'static str, fill: &'static str, text: &'static str) -> Svgr<'static> {
    let p = ease_out(span(t, at, 0.5));
    if p <= 0.0 {
        return Svgr::empty();
    }
    fframes::svgr!(<g opacity={p} transform={format!("translate(0 {})", (1.0 - p) * 26.0)}>
        <text x="960" y={y} text-anchor="middle" font-family={family} font-weight={weight} font-size={size} letter-spacing={-size * 0.018} fill={fill}>{text}</text>
    </g>)
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
    /// The steps a user takes alone today, one after another.
    fn draw(&self, t: f32) -> Svgr<'static> {
        let steps: Vec<Svgr> = HOOK_STEPS
            .into_iter()
            .enumerate()
            .map(|(i, step)| {
                let at = HOOK_STEPS_AT + i as f32 * HOOK_STEP_EVERY;
                let p = spring(t, at);
                let y = 300.0 + i as f32 * 84.0;
                fframes::svgr!(<g opacity={span(t, at, 0.15)} transform={format!("translate(0 {})", (1.0 - p) * 40.0)}>
                    <rect x="620" y={y} width="680" height="68" rx="34" fill={CARD} stroke={EDGE} stroke-width="2" />
                    <circle cx="664" cy={y + 34.0} r="20" fill={TINT} />
                    <text x="664" y={y + 44.0} text-anchor="middle" font-family={DISPLAY} font-weight="700" font-size="26" fill={WHITE}>{(i + 1).to_string()}</text>
                    <text x="706" y={y + 45.0} font-family={TEXT} font-weight="500" font-size="31" fill={WHITE}>{step}</text>
                </g>)
            })
            .collect();
        fframes::svgr!(<g opacity={scene_fade(t, HOOK_SECONDS)}>
            {line(t, 0.15, 212.0, 78.0, DISPLAY, "700", WHITE, "Asking for a macOS permission")}
            {steps}
            {line(t, HOOK_LINE_AT, 900.0, 44.0, TEXT, "500", SOFT, "Six steps your users have to find on their own.")}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(Title, TITLE_SECONDS);

impl Title {
    fn draw(&self, t: f32) -> Svgr<'static> {
        let pop = spring(t, TITLE_POP_AT);
        fframes::svgr!(<g opacity={scene_fade(t, TITLE_SECONDS)}>
            <circle cx="960" cy="370" r={(520.0 * ease_out(span(t, 0.0, 1.0))).max(1.0)} fill="url(#halo)" />
            <g transform={grow([960.0, 370.0], pop)} filter="url(#window-shadow)">{mark(850.0, 260.0, 220.0)}</g>
            {line(t, 0.35, 680.0, 132.0, DISPLAY, "700", WHITE, "PermissionGuide")}
            {line(t, 0.6, 776.0, 48.0, TEXT, "500", SOFT, "Make it one drag.")}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(Demo, DEMO_SECONDS);

impl Demo {
    /// The drag on the shared stage, 1.5x, with a line under it for each step.
    fn draw(&self, t: f32) -> Svgr<'static> {
        let b = &DRAG;
        let captions = [
            (0.15, b.open + 0.15, "Your app asks once"),
            (b.open + 0.25, b.reach + 0.1, "It opens the right pane and highlights the list"),
            (b.reach + 0.2, b.auth_in, "The user drags your app in"),
            (b.auth_in + 0.1, b.done + 0.05, "It follows the Touch ID prompt"),
            (b.done + 0.15, DEMO_SECONDS, "Then it brings your app back"),
        ];
        let lines: Vec<Svgr> = captions
            .into_iter()
            .map(|(start, end, text)| {
                let a = ease_out(span(t, start, 0.3)) * (1.0 - span(t, end - 0.2, 0.2));
                if a <= 0.0 {
                    return Svgr::empty();
                }
                let w = tw(text, 36.0) + 96.0;
                fframes::svgr!(<g opacity={a} transform={format!("translate(0 {})", (1.0 - a) * 14.0)}>
                    <rect x={960.0 - w / 2.0} y="966" width={w} height="76" rx="38" fill={CARD} stroke={EDGE} stroke-width="2" />
                    <text x="960" y="1017" text-anchor="middle" font-family={TEXT} font-weight="600" font-size="36" fill={WHITE}>{text}</text>
                </g>)
            })
            .collect();
        fframes::svgr!(<g opacity={scene_fade(t, DEMO_SECONDS)}>
            <g transform="translate(240 28) scale(1.5)">{demo(Mode::Drag, t, b)}</g>
            {lines}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(Code, CODE_SECONDS);

impl Code {
    /// The call that does all of it, typed out.
    fn draw(&self, t: f32) -> Svgr<'static> {
        const SIZE: f32 = 42.0;
        const ADVANCE: f32 = SIZE * 0.6;
        let typed = ((t - CODE_TYPE_AT) * CODE_CPS).max(0.0) as usize;
        let total = CODE_LINE.chars().count();
        let mut x = 0;
        let parts: Vec<Svgr> = [("await ", "#ff7ab2"), ("permissions.request(", WHITE), (".accessibility", "#6bdfff"), (")", WHITE)]
            .into_iter()
            .map(|(part, color)| {
                let shown: String = part.chars().take(typed.saturating_sub(x)).collect();
                let at = 380.0 + x as f32 * ADVANCE;
                x += part.chars().count();
                fframes::svgr!(<text x={at} y="586" font-family={MONO} font-size={SIZE} fill={color}>{shown}</text>)
            })
            .collect();
        let caret = 380.0 + typed.min(total) as f32 * ADVANCE;
        let blink = if typed < total || (t * 2.5).fract() < 0.5 { 1.0 } else { 0.0 };
        let result = ease_out(span(t, CODE_RESULT_AT, 0.4));
        fframes::svgr!(<g opacity={scene_fade(t, CODE_SECONDS)}>
            {line(t, 0.1, 270.0, 96.0, DISPLAY, "700", WHITE, "One call.")}
            <g opacity={ease_out(span(t, 0.2, 0.4))}>
                <rect x="310" y="370" width="1300" height="290" rx="28" fill="#0c1030" stroke={EDGE} stroke-width="2" filter="url(#window-shadow)" />
                <circle cx="352" cy="410" r="9" fill="#ff5f57" />
                <circle cx="382" cy="410" r="9" fill="#febc2e" />
                <circle cx="412" cy="410" r="9" fill="#28c840" />
                <text x="380" y="512" font-family={MONO} font-size={SIZE} fill="#7f89c4">"let permissions = PermissionManager()"</text>
                {parts}
                <rect x={caret + 2.0} y="548" width="4" height="48" fill={WHITE} opacity={blink} />
            </g>
            <g opacity={result} transform={format!("translate(0 {})", (1.0 - result) * 20.0)}>
                <g transform={grow([508.0, 778.0], spring(t, CODE_RESULT_AT))}>{check(508.0, 778.0, 22.0)}</g>
                <text x="548" y="792" font-family={TEXT} font-weight="500" font-size="40" fill={SOFT}>"Returns .granted as soon as macOS reports it."</text>
            </g>
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
                let (x, y) = (124.0 + (i % 4) as f32 * 424.0, 400.0 + (i / 4) as f32 * 124.0);
                fframes::svgr!(<g opacity={span(t, at, 0.12)} transform={grow([x + 200.0, y + 46.0], lerp(0.7, 1.0, spring(t, at)))}>
                    <rect x={x} y={y} width="400" height="92" rx="46" fill={CARD} stroke={EDGE} stroke-width="2" />
                    {check(x + 50.0, y + 46.0, 17.0)}
                    <text x={x + 84.0} y={y + 57.0} font-family={TEXT} font-weight="600" font-size="31" fill={WHITE}>{chip}</text>
                </g>)
            })
            .collect();
        fframes::svgr!(<g opacity={scene_fade(t, MORE_SECONDS)}>
            {line(t, 0.1, 270.0, 78.0, DISPLAY, "700", WHITE, "For the permissions macOS makes hard")}
            {chips}
            {line(t, 2.0, 760.0, 40.0, TEXT, "500", SOFT, "It walks users through Touch ID and Quit & Reopen prompts too.")}
        </g>)
    }
}

// ---------------------------------------------------------------------------------------------

scene!(End, END_SECONDS);

impl End {
    fn draw(&self, t: f32) -> Svgr<'static> {
        let pop = spring(t, END_POP_AT);
        let link = ease_out(span(t, 1.0, 0.5));
        fframes::svgr!(<g opacity={ease_out(span(t, 0.0, 0.3))}>
            <circle cx="960" cy="290" r={(460.0 * ease_out(span(t, 0.0, 1.0))).max(1.0)} fill="url(#halo)" />
            <g transform={grow([960.0, 290.0], pop)} filter="url(#window-shadow)">{mark(875.0, 205.0, 170.0)}</g>
            {line(t, 0.4, 540.0, 118.0, DISPLAY, "700", WHITE, "PermissionGuide")}
            {line(t, 0.6, 624.0, 46.0, TEXT, "500", SOFT, "Guided permission setup for macOS apps")}
            <g opacity={link} transform={format!("translate(0 {})", (1.0 - link) * 20.0)}>
                <rect x="560" y="708" width="800" height="92" rx="46" fill={TINT} />
                <text x="960" y="768" text-anchor="middle" font-family={TEXT} font-weight="600" font-size="40" fill={WHITE}>"github.com/fcjr/PermissionGuide"</text>
            </g>
            {line(t, 1.4, 892.0, 32.0, TEXT, "500", SOFT, "Open source  ·  MIT  ·  Swift package  ·  macOS 14+")}
        </g>)
    }
}
