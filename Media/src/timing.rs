//! Every time in the clips and the teaser, in seconds. `build.rs` includes this file too, so
//! the soundtrack is synthesized from the same numbers the scenes are drawn from.
#![allow(dead_code)]

/// When things happen while the guide is up, in seconds from the start of a demo.
#[derive(Debug, Clone, Copy)]
pub struct Beats {
    /// The user clicks the button in the app (or the installer).
    pub click: f32,
    /// System Settings opens.
    pub open: f32,
    /// The highlight and the side panel appear.
    pub guide: f32,
    /// The drag hint starts its flight. `NEVER` skips it.
    pub ghost: f32,
    /// The pointer leaves for the icon (or the switch).
    pub reach: f32,
    /// The pointer grabs the icon. For a switch, the same time as `drop`.
    pub grab: f32,
    /// The icon is dropped in the list, or the switch is clicked.
    pub drop: f32,
    /// The Touch ID prompt appears, succeeds and closes.
    pub auth_in: f32,
    pub auth_ok: f32,
    pub auth_out: f32,
    /// The app shows up in the list, switched on.
    pub done: f32,
    /// System Settings closes and the app comes back.
    pub back: f32,
    /// The app shows the permission as granted.
    pub granted: f32,
    pub end: f32,
}

pub const NEVER: f32 = 1.0e9;

/// Dragging the app into a privacy list.
pub const DRAG: Beats = Beats {
    click: 0.9,
    open: 1.0,
    guide: 1.5,
    ghost: 1.7,
    reach: 3.7,
    grab: 4.6,
    drop: 5.7,
    auth_in: 5.9,
    auth_ok: 6.9,
    auth_out: 7.15,
    done: 7.3,
    back: 8.2,
    granted: 8.6,
    end: 9.6,
};

/// Turning on a system extension's switch.
pub const TOGGLE: Beats = Beats {
    click: 0.9,
    open: 1.0,
    guide: 1.5,
    ghost: NEVER,
    reach: 2.3,
    grab: 3.2,
    drop: 3.2,
    auth_in: 3.4,
    auth_ok: 4.4,
    auth_out: 4.65,
    done: 4.8,
    back: 5.7,
    granted: 6.1,
    end: 7.2,
};

/// A run of the guide started from an installer's Set Up section.
#[derive(Debug, Clone, Copy)]
pub struct InstallerBeats {
    /// The guide itself. `click` is the step's button.
    pub guide: Beats,
    /// The pointer clicks Continue on the intro pane.
    pub cont: f32,
    /// The step pane moves on to the last pane by itself, a moment after it shows Done.
    pub finish: f32,
}

pub const INSTALLER: InstallerBeats = InstallerBeats {
    guide: Beats {
        click: 2.7,
        open: 2.8,
        guide: 3.2,
        ghost: NEVER,
        reach: 3.5,
        grab: 4.3,
        drop: 5.3,
        auth_in: 5.5,
        auth_ok: 6.3,
        auth_out: 6.5,
        done: 6.65,
        back: 7.4,
        granted: 7.7,
        end: 10.2,
    },
    cont: 1.4,
    finish: 8.4,
};

// The teaser. One beat is 0.5 s (120 BPM), a bar is 2 s, and every scene starts on a bar.
pub const BEAT: f32 = 0.5;
pub const BAR: f32 = BEAT * 4.0;

/// The drag again, cut down to three bars for the teaser. No hint flight: the pointer goes
/// straight for the icon.
pub const TEASER_DRAG: Beats = Beats {
    click: 0.5,
    open: 0.6,
    guide: 1.0,
    ghost: NEVER,
    reach: 1.25,
    grab: 1.9,
    drop: 2.75,
    auth_in: 2.9,
    auth_ok: 3.5,
    auth_out: 3.7,
    done: 3.8,
    back: 4.5,
    granted: 4.75,
    end: 6.0,
};

/// The installer in two bars: the intro, the step, the guide at speed, and the last pane.
pub const TEASER_INSTALLER: InstallerBeats = InstallerBeats {
    guide: Beats {
        click: 1.0,
        open: 1.1,
        guide: 1.3,
        ghost: NEVER,
        reach: 1.35,
        grab: 1.75,
        drop: 2.25,
        auth_in: 2.3,
        auth_ok: 2.6,
        auth_out: 2.7,
        done: 2.75,
        back: 2.95,
        granted: 3.1,
        end: 4.0,
    },
    cont: 0.45,
    finish: 3.4,
};

pub const HOOK_SECONDS: f32 = 4.0;
pub const TITLE_SECONDS: f32 = 2.0;
pub const DEMO_SECONDS: f32 = TEASER_DRAG.end;
pub const CODE_SECONDS: f32 = 2.0;
pub const INSTALLER_SECONDS: f32 = TEASER_INSTALLER.guide.end;
pub const MORE_SECONDS: f32 = 2.0;
pub const END_SECONDS: f32 = 4.0;

pub const TITLE_AT: f32 = HOOK_SECONDS;
pub const DEMO_AT: f32 = TITLE_AT + TITLE_SECONDS;
pub const CODE_AT: f32 = DEMO_AT + DEMO_SECONDS;
pub const INSTALLER_AT: f32 = CODE_AT + CODE_SECONDS;
pub const MORE_AT: f32 = INSTALLER_AT + INSTALLER_SECONDS;
pub const END_AT: f32 = MORE_AT + MORE_SECONDS;
pub const TEASER_SECONDS: f32 = END_AT + END_SECONDS;

/// Hook: the instructions apps give today land one every `HOOK_STEP_EVERY`, then the stamp
/// comes down on them on the second bar.
pub const HOOK_STEPS: [&str; 6] = [
    "Open System Settings",
    "Click Privacy & Security",
    "Scroll to Full Disk Access",
    "Click +",
    "Find the app in Finder",
    "Enter your password",
];
pub const HOOK_STEPS_AT: f32 = 0.25;
pub const HOOK_STEP_EVERY: f32 = 0.25;
pub const HOOK_STAMP_AT: f32 = BAR;

/// Title: the sub line lands on the second beat.
pub const TITLE_SUB_AT: f32 = BEAT;

/// Code: the second line is typed at `CODE_CPS` characters a second.
pub const CODE_LINE: &str = "await permissions.request(.accessibility)";
pub const CODE_TYPE_AT: f32 = 0.25;
pub const CODE_CPS: f32 = 50.0;
pub const CODE_RESULT_AT: f32 = 1.25;

pub const MORE_CHIPS: [&str; 8] = [
    "Full Disk Access",
    "Screen Recording",
    "Accessibility",
    "Input Monitoring",
    "Bluetooth",
    "System extensions",
    "Background items",
    "Installer .pkg panes",
];
pub const MORE_CHIPS_AT: f32 = 0.25;
pub const MORE_CHIP_EVERY: f32 = 0.125;

/// End: the link lands on the third beat.
pub const END_LINK_AT: f32 = BEAT * 2.0;
