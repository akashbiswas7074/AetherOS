#![no_std]

pub mod system_flake;
pub mod user_profile;

pub use system_flake::{
    DriverKind, DriverManifest, GenerationManager, GenerationRecord, SystemFlake,
};
pub use user_profile::{HyprlandHomeConfig, UserCapability, UserProfile};

#[cfg(test)]
mod tests {
    use super::*;
    use casfs::blake3::hash;

    #[test]
    fn test_system_flake_generation_hash() {
        let mut flake = SystemFlake::new(1);
        let drv = DriverManifest {
            name: "uart_16550",
            kind: DriverKind::SerialConsole,
            binary_hash: hash(b"drv_serial_test"),
            memory_limit_pages: 4,
        };
        assert!(flake.add_driver(drv));
        assert_eq!(flake.driver_count, 1);

        let root_hash = flake.compute_generation_hash();
        assert_ne!(root_hash, casfs::blake3::Blake3Hash::ZERO);
    }

    #[test]
    fn test_user_profile_capabilities() {
        let mut profile = UserProfile::new("akash", 1000);
        let test_hash = hash(b"user_shell_binary");
        let cap_read = UserCapability::ReadObject(test_hash);
        let cap_display = UserCapability::DisplaySurface;

        assert!(profile.grant_capability(cap_read));
        assert!(profile.grant_capability(cap_display));

        assert!(profile.has_capability(&cap_read));
        assert!(profile.has_capability(&cap_display));
        assert!(!profile.has_capability(&UserCapability::WriteObject));
    }

    #[test]
    fn test_hyprland_home_manager() {
        let mut profile = UserProfile::new("akash", 1000);
        let hypr_cfg = HyprlandHomeConfig::default_config();
        profile.enable_hyprland(hypr_cfg);

        assert!(profile.hyprland.is_some());
        assert_eq!(profile.hyprland.unwrap().terminal, "kitty");
        assert_eq!(profile.hyprland.unwrap().bar, "waybar");
        // Must automatically grant DisplaySurface capability
        assert!(profile.has_capability(&UserCapability::DisplaySurface));
    }

    #[test]
    fn test_generation_manager_rollback_and_switch() {
        let mut mgr = GenerationManager::new();

        // 1. Record Generation 1 and Generation 2
        let hash1 = hash(b"gen1_root");
        let hash2 = hash(b"gen2_root");
        assert!(mgr.record_generation(1, hash1, 100));
        assert!(mgr.record_generation(2, hash2, 200));

        assert_eq!(mgr.count, 2);
        assert_eq!(mgr.active_index, 1);
        assert_eq!(mgr.generations[1].unwrap().id, 2);
        assert!(mgr.generations[1].unwrap().active);

        // 2. Rollback to Generation 1
        let prev = mgr.rollback();
        assert!(prev.is_some());
        assert_eq!(prev.unwrap().id, 1);
        assert_eq!(prev.unwrap().root_hash, hash1);
        assert!(prev.unwrap().active);
        assert_eq!(mgr.active_index, 0);

        // 3. Switch back forward to Generation 2
        let switched = mgr.switch_to(2);
        assert!(switched.is_some());
        assert_eq!(switched.unwrap().id, 2);
        assert_eq!(switched.unwrap().root_hash, hash2);
        assert!(switched.unwrap().active);
    }
}
