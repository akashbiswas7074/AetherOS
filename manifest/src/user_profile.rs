//! Declarative User Profile Engine (Native Home-Manager Paradigm).
//! Sandboxed capability projections per-user without Unix root or SUID.

use casfs::blake3::Blake3Hash;

pub const MAX_USER_CAPABILITIES: usize = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UserCapability {
    ReadObject(Blake3Hash),
    WriteObject,
    DisplaySurface,
    NetworkSocket(u16), // Bound to specific port
    DirectMemoryAccess,
}

/// Declarative Home-Manager Configuration for Hyprland Desktop
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HyprlandHomeConfig {
    pub compositor: &'static str,
    pub bar: &'static str,
    pub terminal: &'static str,
    pub launcher: &'static str,
    pub animation_bezier: &'static str,
    pub border_size: u8,
    pub active_border_color: &'static str,
    pub inactive_border_color: &'static str,
}

impl HyprlandHomeConfig {
    pub const fn default_config() -> Self {
        Self {
            compositor: "hyprland-0.42.0",
            bar: "waybar",
            terminal: "kitty",
            launcher: "wofi",
            animation_bezier: "myBezier, 0.05, 0.9, 0.1, 1.05",
            border_size: 2,
            active_border_color: "rgba(33ccffee) rgba(00ff99ee) 45deg",
            inactive_border_color: "rgba(595959aa)",
        }
    }
}

/// Declarative User Environment Profile
pub struct UserProfile {
    pub username: &'static str,
    pub uid: u32,
    pub config_merkle_root: Blake3Hash,
    pub hyprland: Option<HyprlandHomeConfig>,
    pub capability_count: usize,
    pub capabilities: [Option<UserCapability>; MAX_USER_CAPABILITIES],
}

impl UserProfile {
    pub const fn new(username: &'static str, uid: u32) -> Self {
        const NONE_CAP: Option<UserCapability> = None;
        Self {
            username,
            uid,
            config_merkle_root: Blake3Hash::ZERO,
            hyprland: None,
            capability_count: 0,
            capabilities: [NONE_CAP; MAX_USER_CAPABILITIES],
        }
    }

    pub fn enable_hyprland(&mut self, cfg: HyprlandHomeConfig) {
        self.hyprland = Some(cfg);
        // Grant Wayland display surface capability automatically
        self.grant_capability(UserCapability::DisplaySurface);
    }

    pub fn grant_capability(&mut self, cap: UserCapability) -> bool {
        if self.capability_count < MAX_USER_CAPABILITIES {
            self.capabilities[self.capability_count] = Some(cap);
            self.capability_count += 1;
            true
        } else {
            false
        }
    }

    pub fn has_capability(&self, cap: &UserCapability) -> bool {
        for i in 0..self.capability_count {
            if let Some(ref c) = self.capabilities[i] {
                if c == cap {
                    return true;
                }
            }
        }
        false
    }
}
