//! The teaser's soundtrack, synthesized from oscillators and noise: no samples, loops or
//! third-party audio, so there is nothing to license. `build.rs` runs this and writes
//! `media/soundtrack.wav`. The noise is seeded, so the same source always gives the same file.
//!
//! 120 BPM in D minor. The hook is a drone and ticks, a riser leads into the title, and from
//! there a driven bass, kick and clap run under interface sounds placed at the times in
//! `src/timing.rs`: change a time there and the sound follows on the next build.
use crate::timing::*;
use std::f32::consts::{PI, TAU};

const SR: usize = 48_000;

// Levels.
const MUSIC: f32 = 0.55;
const SFX: f32 = 0.9;

const D2: f32 = 73.42;
const C2: f32 = 65.41;
const F2: f32 = 87.31;
const BB1: f32 = 58.27;
/// The bass line, eight eighth notes a bar, alternating between these two bars.
const RIFFS: [[f32; 8]; 2] = [[D2, D2, D2, F2, D2, D2, C2, D2], [D2, D2, D2, BB1, D2, D2, C2, F2]];
/// The lead: sixteenth notes over D minor.
const LEAD: [f32; 8] = [293.66, 349.23, 440.00, 523.25, 440.00, 349.23, 587.33, 440.00];

struct Mix {
    left: Vec<f32>,
    right: Vec<f32>,
    seed: u32,
}

impl Mix {
    fn new(seconds: f32) -> Self {
        let n = (seconds * SR as f32) as usize;
        Self { left: vec![0.0; n], right: vec![0.0; n], seed: 0x2545_f491 }
    }

    /// White noise in -1..1 from a fixed seed.
    fn noise(&mut self) -> f32 {
        self.seed ^= self.seed << 13;
        self.seed ^= self.seed >> 17;
        self.seed ^= self.seed << 5;
        self.seed as f32 / u32::MAX as f32 * 2.0 - 1.0
    }

    /// Adds `sample(seconds since start)` from `start` for `seconds`. `pan` is -1 (left) to 1.
    fn add(&mut self, start: f32, seconds: f32, pan: f32, mut sample: impl FnMut(&mut Self, f32) -> f32) {
        let first = (start.max(0.0) * SR as f32) as usize;
        let count = (seconds * SR as f32) as usize;
        let (l, r) = (((1.0 - pan) * 0.5).sqrt(), ((1.0 + pan) * 0.5).sqrt());
        for i in 0..count {
            let Some(at) = first.checked_add(i).filter(|at| *at < self.left.len()) else { break };
            let s = sample(self, i as f32 / SR as f32);
            self.left[at] += s * l;
            self.right[at] += s * r;
        }
    }

    // --- Music -------------------------------------------------------------------------

    /// A sawtooth through a filter that snaps shut, then driven: the bass.
    fn bass(&mut self, start: f32, seconds: f32, f: f32, gain: f32) {
        let (mut phase, mut low) = (0.0_f32, 0.0_f32);
        self.add(start, seconds, 0.0, |_, t| {
            phase = (phase + f / SR as f32).fract();
            let saw = phase * 2.0 - 1.0 + 0.5 * (TAU * f * 0.5 * t).sin();
            let cutoff = 0.03 + 0.25 * (-t * 14.0).exp();
            low += cutoff * (saw - low);
            let env = (t / 0.004).min(1.0) * ((seconds - t) / 0.03).clamp(0.0, 1.0);
            (low * 3.2).tanh() * env * gain * 0.42
        });
    }

    /// A held low note that opens up slowly, under the hook.
    fn drone(&mut self, start: f32, seconds: f32, f: f32, gain: f32) {
        let (mut phase, mut low) = (0.0_f32, 0.0_f32);
        self.add(start, seconds, 0.0, |_, t| {
            phase = (phase + f / SR as f32).fract();
            let saw = phase * 2.0 - 1.0;
            low += (0.01 + 0.03 * t / seconds) * (saw - low);
            let env = (t / 0.3).min(1.0) * ((seconds - t) / 0.05).clamp(0.0, 1.0);
            (low * 2.0).tanh() * env * gain * 0.4
        });
    }

    /// A short hollow pluck for the lead.
    fn pluck(&mut self, start: f32, f: f32, gain: f32, pan: f32) {
        self.add(start, 0.2, pan, |_, t| {
            let env = (t / 0.002).min(1.0) * (-t * 22.0).exp();
            ((TAU * f * t).sin() + 0.33 * (TAU * f * 3.0 * t).sin() + 0.2 * (TAU * f * 5.0 * t).sin()) * env * gain * 0.13
        });
    }

    fn kick(&mut self, start: f32, gain: f32) {
        let mut phase = 0.0_f32;
        self.add(start, 0.28, 0.0, |m, t| {
            let f = 48.0 + 130.0 * (-t * 45.0).exp();
            phase += TAU * f / SR as f32;
            let click = m.noise() * (-t * 500.0).exp() * 0.25;
            ((phase.sin() * 1.8).tanh() * (-t * 11.0).exp() + click) * gain * 0.62
        });
    }

    /// Noise with a little body, on beats two and four.
    fn clap(&mut self, start: f32, gain: f32) {
        let mut last = 0.0_f32;
        self.add(start, 0.18, 0.0, |m, t| {
            let n = m.noise();
            let bright = n - 0.6 * last;
            last = n;
            // Three quick bursts, then the tail.
            let bursts = if t < 0.03 { ((t * 100.0 * PI).sin()).abs() } else { 1.0 };
            (bright * (-t * 28.0).exp() * bursts + (TAU * 190.0 * t).sin() * (-t * 60.0).exp() * 0.4) * gain * 0.3
        });
    }

    fn hat(&mut self, start: f32, gain: f32, pan: f32) {
        let mut last = 0.0_f32;
        self.add(start, 0.05, pan, |m, t| {
            let n = m.noise();
            let high = n - last;
            last = n;
            high * (-t * 110.0).exp() * gain * 0.07
        });
    }

    // --- Hits and interface sounds -----------------------------------------------------

    /// A sub drop with a crash on top, under a title or a stamp.
    fn impact(&mut self, at: f32, gain: f32) {
        let (mut phase, mut low) = (0.0_f32, 0.0_f32);
        self.add(at, 1.2, 0.0, |m, t| {
            let f = 38.0 + 110.0 * (-t * 16.0).exp();
            phase += TAU * f / SR as f32;
            low += 0.35 * (m.noise() - low);
            let crash = (m.noise() - low) * (-t * 5.5).exp() * 0.22;
            ((phase.sin() * 2.2).tanh() * (-t * 3.6).exp() + crash) * gain * SFX * 0.6
        });
    }

    /// Noise and a tone that both climb for `seconds`, ending on the next hit.
    fn riser(&mut self, at: f32, seconds: f32, gain: f32) {
        let (mut phase, mut low) = (0.0_f32, 0.0_f32);
        self.add(at, seconds, 0.0, |m, t| {
            let p = t / seconds;
            low += (0.02 + 0.5 * p * p) * (m.noise() - low);
            phase += TAU * (180.0 + 900.0 * p * p) / SR as f32;
            (low * 0.7 + phase.sin() * 0.18) * p * p * gain * SFX * 0.5
        });
    }

    /// A mouse click: a short tick and a little body.
    fn click(&mut self, at: f32, gain: f32) {
        self.add(at, 0.05, 0.0, |m, t| {
            let tick = m.noise() * (-t * 900.0).exp() * 0.5;
            let body = (TAU * 1900.0 * t).sin() * (-t * 220.0).exp() * 0.4 + (TAU * 320.0 * t).sin() * (-t * 120.0).exp() * 0.5;
            (tick + body) * gain * SFX * 0.5
        });
    }

    /// A key press, a little different each time.
    fn key(&mut self, at: f32) {
        let f = 1500.0 + 900.0 * self.noise().abs();
        let level = 0.6 + 0.4 * self.noise().abs();
        self.add(at, 0.03, 0.0, |m, t| {
            (m.noise() * 0.5 + (TAU * f * t).sin() * 0.5) * (-t * 420.0).exp() * level * SFX * 0.2
        });
    }

    /// Something landing: a quick blip, falling for a slam or rising for a pop.
    fn blip(&mut self, at: f32, pitch: f32, bend: f32, gain: f32, pan: f32) {
        let mut phase = 0.0_f32;
        self.add(at, 0.12, pan, |_, t| {
            let f = pitch * (1.0 + bend * (t / 0.06).min(1.0));
            phase += TAU * f / SR as f32;
            (phase.sin() * 1.6).tanh() * (t / 0.002).min(1.0) * (-t * 38.0).exp() * gain * SFX * 0.36
        });
    }

    /// A window moving: filtered noise that swells and falls.
    fn whoosh(&mut self, at: f32, seconds: f32, gain: f32) {
        let mut low = 0.0_f32;
        self.add(at, seconds, 0.0, |m, t| {
            let p = t / seconds;
            let env = (p * PI).sin().powi(2);
            low += (0.02 + 0.2 * (p * PI).sin()) * (m.noise() - low);
            low * env * gain * SFX * 0.75
        });
    }

    /// Bell-like notes, struck `gap` seconds apart.
    fn chime(&mut self, at: f32, notes: &[f32], gap: f32, gain: f32) {
        for (i, f) in notes.iter().copied().enumerate() {
            let pan = if notes.len() > 1 { -0.3 + 0.6 * i as f32 / (notes.len() - 1) as f32 } else { 0.0 };
            self.add(at + gap * i as f32, 1.0, pan, |_, t| {
                let env = (t / 0.003).min(1.0) * (-t * 6.0).exp();
                ((TAU * f * t).sin() + 0.35 * (TAU * f * 2.0 * t).sin() * (-t * 9.0).exp()) * env * gain * SFX * 0.2
            });
        }
    }
}

fn music(m: &mut Mix) {
    let bars = (TEASER_SECONDS / BAR).round() as usize;
    let eighth = BEAT / 2.0;
    let sixteenth = BEAT / 4.0;

    // The hook: a drone, ticking hats, and a riser with a roll into the title.
    m.drone(0.0, TITLE_AT, D2 / 2.0, MUSIC);
    for step in 0..(HOOK_STAMP_AT / sixteenth) as usize {
        m.hat(step as f32 * sixteenth, MUSIC * if step % 4 == 0 { 0.9 } else { 0.45 }, 0.3);
    }
    m.riser(TITLE_AT - BEAT * 2.0, BEAT * 2.0, 1.0);
    for step in 0..4 {
        m.clap(TITLE_AT - BEAT + step as f32 * sixteenth, MUSIC * (0.4 + 0.2 * step as f32));
    }

    // From the title on: bass, kick, clap and hats. The lead joins for the demos and drops
    // out for the last bar, which is one long note.
    for bar in (TITLE_AT / BAR) as usize..bars {
        let start = bar as f32 * BAR;
        if bar == bars - 1 {
            m.bass(start, BAR, D2, MUSIC);
            m.kick(start, MUSIC);
            continue;
        }
        for (step, note) in RIFFS[bar % 2].into_iter().enumerate() {
            m.bass(start + step as f32 * eighth, eighth * 0.92, note, MUSIC);
        }
        for beat in 0..4 {
            let at = start + beat as f32 * BEAT;
            m.kick(at, MUSIC);
            if beat % 2 == 1 {
                m.clap(at, MUSIC);
            }
            m.hat(at, MUSIC * 0.5, 0.3);
            m.hat(at + eighth, MUSIC, 0.3);
        }
        if start >= DEMO_AT && start < END_AT {
            for step in 0..16 {
                let pan = if step % 2 == 0 { -0.5 } else { 0.5 };
                m.pluck(start + step as f32 * sixteenth, LEAD[step % 8], MUSIC * 0.8, pan);
            }
        }
    }
}

/// The sounds of one guide run that starts at `at`.
fn guide(m: &mut Mix, at: f32, b: Beats) {
    m.click(at + b.click, 1.0);
    m.whoosh(at + b.open - 0.05, 0.35, 0.5);
    m.blip(at + b.guide, 520.0, 1.1, 0.8, 0.3);
    if b.grab < b.drop {
        m.click(at + b.grab, 0.6);
        m.whoosh(at + b.grab + 0.05, b.drop - b.grab, 0.3);
        m.blip(at + b.drop, 300.0, -0.5, 1.0, -0.2);
    } else {
        m.click(at + b.drop, 1.0);
    }
    m.blip(at + b.auth_in, 420.0, 1.1, 0.7, 0.0);
    m.chime(at + b.auth_ok, &[1318.5, 1760.0], 0.05, 0.6);
    m.blip(at + b.done, 620.0, 1.1, 0.9, -0.2);
    m.whoosh(at + b.back - 0.05, 0.35, 0.5);
    m.chime(at + b.granted, &[587.33, 880.0, 1174.66], 0.05, 1.0);
}

fn effects(m: &mut Mix) {
    // Hook: each instruction thuds in lower than the last, then the stamp.
    for i in 0..HOOK_STEPS.len() {
        m.blip(HOOK_STEPS_AT + i as f32 * HOOK_STEP_EVERY, 260.0 - 22.0 * i as f32, -0.5, 0.9, -0.3 + 0.12 * i as f32);
    }
    m.impact(HOOK_STAMP_AT, 1.0);

    m.impact(TITLE_AT, 1.0);
    m.blip(TITLE_AT + TITLE_SUB_AT, 200.0, -0.5, 1.0, 0.0);

    guide(m, DEMO_AT, TEASER_DRAG);

    for i in 0..CODE_LINE.chars().count() {
        m.key(CODE_AT + CODE_TYPE_AT + i as f32 / CODE_CPS);
    }
    m.blip(CODE_AT + CODE_RESULT_AT, 200.0, -0.5, 1.0, 0.0);

    m.click(INSTALLER_AT + TEASER_INSTALLER.cont, 1.0);
    guide(m, INSTALLER_AT, TEASER_INSTALLER.guide);
    m.chime(INSTALLER_AT + TEASER_INSTALLER.finish, &[880.0, 1174.66], 0.05, 0.8);

    for i in 0..MORE_CHIPS.len() {
        m.blip(MORE_AT + MORE_CHIPS_AT + i as f32 * MORE_CHIP_EVERY, 240.0 + 30.0 * i as f32, -0.4, 0.8, -0.4 + 0.11 * i as f32);
    }

    m.impact(END_AT, 1.0);
    m.blip(END_AT + END_LINK_AT, 200.0, -0.5, 1.0, 0.0);
}

/// The whole soundtrack as a 16-bit stereo WAV file.
pub fn wav() -> Vec<u8> {
    let mut m = Mix::new(TEASER_SECONDS);
    music(&mut m);
    effects(&mut m);

    // Fade the tail and soft-limit the mix. The output gain puts it near -14 LUFS.
    let n = m.left.len();
    let fade = (1.5 * SR as f32) as usize;
    let peak = m.left.iter().chain(&m.right).fold(0.0_f32, |p, s| p.max(s.abs())).max(1e-6);
    let drive = 1.6 / peak;
    let mut data = Vec::with_capacity(n * 4);
    for i in 0..n {
        let tail = ((n - i) as f32 / fade as f32).min(1.0);
        for s in [m.left[i], m.right[i]] {
            let limited = (s * drive).tanh() / 1.6_f32.tanh() * 0.5 * tail;
            data.extend_from_slice(&((limited * i16::MAX as f32) as i16).to_le_bytes());
        }
    }

    let mut out = Vec::with_capacity(data.len() + 44);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16_u32.to_le_bytes());
    out.extend_from_slice(&1_u16.to_le_bytes());
    out.extend_from_slice(&2_u16.to_le_bytes());
    out.extend_from_slice(&(SR as u32).to_le_bytes());
    out.extend_from_slice(&(SR as u32 * 4).to_le_bytes());
    out.extend_from_slice(&4_u16.to_le_bytes());
    out.extend_from_slice(&16_u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(&data);
    out
}
