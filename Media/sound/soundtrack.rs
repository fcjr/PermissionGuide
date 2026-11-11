//! The teaser's soundtrack, synthesized from sine waves and noise: no samples, loops or
//! third-party audio, so there is nothing to license. `build.rs` runs this and writes
//! `media/soundtrack.wav`. The noise is seeded, so the same source always gives the same file.
//!
//! A 100 BPM bed in D major sits under interface sounds placed at the times in
//! `src/timing.rs`: change a time there and the sound follows on the next build.
use crate::timing::*;
use std::f32::consts::TAU;

const SR: usize = 48_000;
const BAR: f32 = BEAT * 4.0;

// Levels.
const MUSIC: f32 = 0.5;
const SFX: f32 = 0.9;

/// The pad's four notes for each bar. Twelve bars: hook, hook, title, demo x4, code and more x3, end x2.
const D: [f32; 4] = [146.83, 220.00, 293.66, 369.99];
const A: [f32; 4] = [164.81, 220.00, 277.18, 329.63];
const BM: [f32; 4] = [123.47, 185.00, 246.94, 293.66];
const G: [f32; 4] = [146.83, 196.00, 246.94, 293.66];
const BARS: [[f32; 4]; 12] = [BM, G, D, D, A, BM, G, D, A, G, D, D];
const ROOTS: [f32; 12] = [61.74, 49.00, 73.42, 73.42, 55.00, 61.74, 49.00, 73.42, 55.00, 49.00, 73.42, 73.42];

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

    /// A soft held chord: each note is two detuned sines with a slow attack and release.
    fn pad(&mut self, start: f32, seconds: f32, notes: [f32; 4], gain: f32) {
        for (i, f) in notes.into_iter().enumerate() {
            let pan = [-0.5, 0.3, -0.2, 0.5][i];
            self.add(start, seconds + 0.6, pan, |_, t| {
                let env = (t / 0.5).min(1.0) * ((seconds + 0.6 - t) / 0.7).clamp(0.0, 1.0);
                let tone = (TAU * f * t).sin() + (TAU * f * 1.004 * t).sin() + 0.25 * (TAU * f * 2.0 * t).sin();
                tone * env * gain * 0.09
            });
        }
    }

    fn pluck(&mut self, start: f32, f: f32, gain: f32, pan: f32) {
        self.add(start, 0.5, pan, |_, t| {
            let env = (t / 0.004).min(1.0) * (-t * 9.0).exp();
            ((TAU * f * t).sin() + 0.3 * (TAU * f * 2.0 * t).sin() + 0.12 * (TAU * f * 3.0 * t).sin()) * env * gain * 0.16
        });
    }

    fn kick(&mut self, start: f32, gain: f32) {
        let mut phase = 0.0_f32;
        self.add(start, 0.3, 0.0, |_, t| {
            let f = 46.0 + 90.0 * (-t * 38.0).exp();
            phase += TAU * f / SR as f32;
            phase.sin() * (-t * 13.0).exp() * gain * 0.5
        });
    }

    fn bass(&mut self, start: f32, f: f32, gain: f32) {
        self.add(start, 0.5, 0.0, |_, t| {
            let env = (t / 0.01).min(1.0) * (-t * 5.0).exp();
            ((TAU * f * t).sin() + 0.3 * (TAU * f * 2.0 * t).sin()) * env * gain * 0.3
        });
    }

    fn hat(&mut self, start: f32, gain: f32) {
        let mut last = 0.0_f32;
        self.add(start, 0.06, 0.25, |m, t| {
            let n = m.noise();
            let high = n - last;
            last = n;
            high * (-t * 90.0).exp() * gain * 0.05
        });
    }

    // --- Interface sounds --------------------------------------------------------------

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
            (m.noise() * 0.5 + (TAU * f * t).sin() * 0.5) * (-t * 420.0).exp() * level * SFX * 0.16
        });
    }

    /// Something appearing: a quick rising blip.
    fn pop(&mut self, at: f32, pitch: f32, gain: f32, pan: f32) {
        let mut phase = 0.0_f32;
        self.add(at, 0.12, pan, |_, t| {
            let f = pitch * (1.0 + 1.1 * (t / 0.06).min(1.0));
            phase += TAU * f / SR as f32;
            phase.sin() * (t / 0.003).min(1.0) * (-t * 38.0).exp() * gain * SFX * 0.4
        });
    }

    /// A window moving: filtered noise that swells and falls.
    fn whoosh(&mut self, at: f32, seconds: f32, gain: f32) {
        let mut low = 0.0_f32;
        self.add(at, seconds, 0.0, |m, t| {
            let p = t / seconds;
            let env = (p * std::f32::consts::PI).sin().powi(2);
            let cutoff = 0.02 + 0.2 * (p * std::f32::consts::PI).sin();
            low += cutoff * (m.noise() - low);
            low * env * gain * SFX * 0.75
        });
    }

    /// Bell-like notes, struck `gap` seconds apart.
    fn chime(&mut self, at: f32, notes: &[f32], gap: f32, gain: f32) {
        for (i, f) in notes.iter().copied().enumerate() {
            let pan = if notes.len() > 1 { -0.3 + 0.6 * i as f32 / (notes.len() - 1) as f32 } else { 0.0 };
            self.add(at + gap * i as f32, 1.4, pan, |_, t| {
                let env = (t / 0.003).min(1.0) * (-t * 4.5).exp();
                ((TAU * f * t).sin() + 0.35 * (TAU * f * 2.0 * t).sin() * (-t * 9.0).exp() + 0.15 * (TAU * f * 3.01 * t).sin() * (-t * 14.0).exp())
                    * env * gain * SFX * 0.2
            });
        }
    }

    /// A low hit under a title.
    fn thud(&mut self, at: f32, gain: f32) {
        let mut phase = 0.0_f32;
        self.add(at, 0.7, 0.0, |m, t| {
            let f = 52.0 + 60.0 * (-t * 22.0).exp();
            phase += TAU * f / SR as f32;
            (phase.sin() * (-t * 6.0).exp() + m.noise() * (-t * 60.0).exp() * 0.15) * gain * SFX * 0.6
        });
    }
}

fn music(m: &mut Mix) {
    for (bar, (notes, root)) in BARS.into_iter().zip(ROOTS).enumerate() {
        let start = bar as f32 * BAR;
        // The hook is quiet, the last bar is the chord ringing out.
        let hook = start < TITLE_AT;
        let last = bar == BARS.len() - 1;
        m.pad(start, BAR, notes, MUSIC * if hook { 0.7 } else { 1.0 });
        if hook {
            m.bass(start, root * 2.0, MUSIC * 0.5);
            continue;
        }
        if last {
            m.bass(start, root * 2.0, MUSIC * 0.8);
            m.pluck(start, notes[3] * 2.0, MUSIC * 0.8, 0.0);
            continue;
        }
        for beat in 0..4 {
            let at = start + beat as f32 * BEAT;
            m.kick(at, MUSIC * 0.9);
            m.hat(at + BEAT / 2.0, MUSIC);
            if beat % 2 == 0 {
                m.bass(at, root * 2.0, MUSIC);
            } else {
                m.bass(at + BEAT / 2.0, root * 2.0, MUSIC * 0.6);
            }
        }
        // Eighth notes walking up and down the chord, an octave above the pad.
        for (step, index) in [0, 1, 2, 3, 2, 1, 2, 3].into_iter().enumerate() {
            let pan = if step % 2 == 0 { -0.45 } else { 0.45 };
            m.pluck(start + step as f32 * BEAT / 2.0, notes[index] * 2.0, MUSIC * 0.7, pan);
        }
    }
}

/// The sounds of one guide run that starts at `at`.
fn guide(m: &mut Mix, at: f32, b: Beats) {
    m.click(at + b.click, 1.0);
    m.whoosh(at + b.open - 0.05, 0.5, 0.5);
    m.pop(at + b.guide, 520.0, 0.8, 0.3);
    if b.grab < b.drop {
        m.click(at + b.grab, 0.6);
        m.whoosh(at + b.grab + 0.1, b.drop - b.grab, 0.3);
        m.pop(at + b.drop, 300.0, 1.0, -0.2);
    } else {
        m.click(at + b.drop, 1.0);
    }
    m.pop(at + b.auth_in, 420.0, 0.7, 0.0);
    m.chime(at + b.auth_ok, &[1318.5, 1760.0], 0.07, 0.6);
    m.pop(at + b.done, 620.0, 0.9, -0.2);
    m.whoosh(at + b.back - 0.05, 0.5, 0.5);
    m.chime(at + b.granted, &[587.33, 880.0, 1174.66], 0.08, 1.0);
}

fn effects(m: &mut Mix) {
    // Hook: a tick per step, a touch higher each time, then a low hit under the line.
    for i in 0..HOOK_STEPS.len() {
        m.pop(HOOK_STEPS_AT + i as f32 * HOOK_STEP_EVERY, 300.0 + 40.0 * i as f32, 0.7, -0.3 + 0.12 * i as f32);
    }
    m.thud(HOOK_LINE_AT, 0.8);

    m.whoosh(TITLE_AT - 0.25, 0.5, 0.6);
    m.thud(TITLE_AT + TITLE_POP_AT, 1.0);
    m.chime(TITLE_AT + TITLE_POP_AT, &[587.33, 880.0, 1174.66], 0.05, 0.8);

    guide(m, DEMO_AT, DRAG);

    m.whoosh(CODE_AT - 0.2, 0.4, 0.4);
    for i in 0..CODE_LINE.chars().count() {
        m.key(CODE_AT + CODE_TYPE_AT + i as f32 / CODE_CPS);
    }
    m.chime(CODE_AT + CODE_RESULT_AT, &[880.0, 1174.66], 0.07, 0.7);

    m.whoosh(MORE_AT - 0.2, 0.4, 0.4);
    for i in 0..MORE_CHIPS.len() {
        m.pop(MORE_AT + MORE_CHIPS_AT + i as f32 * MORE_CHIP_EVERY, 380.0 + 45.0 * i as f32, 0.7, -0.4 + 0.11 * i as f32);
    }

    m.whoosh(END_AT - 0.25, 0.5, 0.6);
    m.thud(END_AT + END_POP_AT, 1.0);
    m.chime(END_AT + END_POP_AT, &[587.33, 739.99, 880.0, 1174.66], 0.06, 0.9);
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
            let limited = (s * drive).tanh() / 1.6_f32.tanh() * 0.6 * tail;
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
