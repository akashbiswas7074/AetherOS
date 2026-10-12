#!/usr/bin/env python3
import os
import sys
import json
import subprocess

ESPEAK_BIN = "/nix/store/hxynx1nc925j7p6ijamq9gff0ylx57jw-espeak-ng-1.52.0.1-unstable-2025-09-09/bin/espeak-ng"
FONT_PATH = "/home/akashbiswas/.nix-profile/share/fonts/truetype/JetBrainsMonoNL-Regular.ttf"
OUTPUT_VIDEO = "/home/akashbiswas/Desktop/operating_system/assets/ananta_overview_demo.mp4"
TMP_DIR = "/tmp/ananta_video_build"

os.makedirs(TMP_DIR, exist_ok=True)

SCENES = [
    {
        "id": "scene1_intro",
        "image": "assets/ananta_logo.jpg",
        "category": "PROJECT INTRODUCTION",
        "title": "AnantaOS (अनन्त) - Next-Gen Operating System",
        "subtitle": "Declarative Microkernel Architecture in Rust (no_std) & x86_64 Assembly",
        "voice": (
            "Welcome to AnantaOS, a next-generation declarative microkernel operating system "
            "built from scratch in Rust and x86-64 assembly. Designed to eliminate the vulnerabilities "
            "of monolithic Unix kernels, AnantaOS introduces content-addressed storage, an immutable "
            "blockchain audit ledger, and universal multi-binary execution."
        ),
        "bullets": [
            "• Built from scratch to replace 50-year-old monolithic Unix kernel vulnerabilities.",
            "• Integrates CasFS (Content-Addressable Storage) and Kernel Blockchain Audit Ledger.",
            "• Universal Multi-ABI: Natively runs Linux ELF64, Windows PE32+, and macOS Mach-O."
        ]
    },
    {
        "id": "scene2_arch",
        "image": "assets/ananta_neofetch.png",
        "category": "SYSTEM ARCHITECTURE & HARDWARE",
        "title": "Microkernel Core & 5 Scientific Pillars",
        "subtitle": "Lightweight 71 MB Memory Footprint with SMP Multi-Core Execution",
        "voice": (
            "The architecture is founded on five core scientific pillars. First, a memory-safe Rust "
            "microkernel with lock-free message passing. Second, the CasFS content-addressed filesystem. "
            "Third, a kernel-level blockchain audit ledger. Fourth, declarative system flakes with "
            "instant O of 1 rollback. And fifth, a zero-virtualization multi-ABI runtime supporting "
            "Linux, Windows, and macOS binaries side-by-side."
        ),
        "bullets": [
            "• [1] Pure Rust Microkernel with Lock-Free Ring-Buffer IPC and Zero Ambient Root.",
            "• [2] CasFS Storage Engine replacing Inodes with BLAKE3 Merkle-Tree Addressing.",
            "• [3] Blockchain Audit Ledger preventing log deletion, tampering, and anti-forensics.",
            "• [4] Declarative Flake Generations with sub-50ms atomic pointer rollbacks."
        ]
    },
    {
        "id": "scene3_casfs",
        "image": "assets/ananta_blockchain_casfs.png",
        "category": "STORAGE INNOVATION",
        "title": "CasFS: Content-Addressed Filesystem",
        "subtitle": "BLAKE3 SIMD Tree Hashing with O(1) Hash Array Mapped Trie (HAMT)",
        "voice": (
            "CasFS completely eliminates traditional disk inodes. Every file and directory is "
            "fingerprinted using BLAKE3 cryptographic tree hashing and indexed into a bounded "
            "Hash Array Mapped Trie. Identical data extents are deduplicated automatically, "
            "reducing physical disk consumption by ninety percent in benchmark workloads."
        ),
        "bullets": [
            "• Extent-level deduplication yields 90% physical storage reduction (10x disk savings).",
            "• Every file and folder structure is fingerprinted into a cryptographic Merkle node.",
            "• Automatic extent reuse: identical blocks require zero additional physical disk space."
        ]
    },
    {
        "id": "scene4_gcc",
        "image": "assets/ananta_gcc_compile.png",
        "category": "LIVE DEMO 1: NATIVE DEVELOPMENT",
        "title": "High-Performance C Compilation & Blockchain Seal",
        "subtitle": "Bare-Metal GCC Optimization and Immediate CasFS Ledger Sealing",
        "voice": (
            "Here is our first live demonstration. Running directly on bare metal, we write "
            "high-performance C algorithms and compile them using native GCC with level 3 optimization. "
            "Once compiled, executing casfs commit computes a 256-bit BLAKE3 hash tree root and "
            "permanently seals the binary into Block 15 of our immutable audit blockchain."
        ),
        "bullets": [
            "• Native GCC compiles matrix FFT algorithms with 0 ns translation overhead.",
            "• 'casfs commit' calculates BLAKE3 tree hash (9b2f7a10...) across 4 tree levels.",
            "• The compiled binary is permanently sealed into Block #15 of the Immutable Ledger."
        ]
    },
    {
        "id": "scene5_tamper",
        "image": "assets/ananta_tamper_alert.png",
        "category": "LIVE DEMO 2: INTRUSION PREVENTION",
        "title": "Real-Time Hacker Tamper Detection & Quarantine",
        "subtitle": "Cryptographic Merkle Audit Detects Attack & Halts Binary Execution",
        "voice": (
            "Now, observe what happens when an adversary injects malicious shellcode into a "
            "verified system binary. When casfs verify is executed, it calculates the current hash tree "
            "against sealed Block 15. The cryptographic mismatch immediately triggers a high-priority "
            "TAMPER ALERT, halts execution inside the microkernel capability sandbox, and logs "
            "the forensic incident."
        ),
        "bullets": [
            "• Live Attack: Adversary injects shellcode payload into a verified system binary.",
            "• 'casfs verify' immediately detects hash mismatch against sealed Block #15.",
            "• [TAMPER ALERT] triggered: Execution blocked by Microkernel Capability Sandbox!",
            "• Forensics: Security event permanently logged to /var/log/casfs_audit.log."
        ]
    },
    {
        "id": "scene6_rebuild",
        "image": "assets/ananta_generations_rebuild.png",
        "category": "LIVE DEMO 3: DECLARATIVE RECOVERY",
        "title": "Declarative Generations & Instant O(1) Rollback",
        "subtitle": "Nix-Flake State Machine with Sub-50ms Disaster Recovery",
        "voice": (
            "In our third live demonstration, we inspect system generations using ananta rebuild list. "
            "System configurations are modeled as immutable mathematical flakes. Administrators can "
            "switch between configurations live without rebooting, or trigger an instant O of 1 "
            "atomic rollback to restore a known-good state in just 0.04 seconds."
        ),
        "bullets": [
            "• 'ananta-rebuild list' tracks immutable system generations with Merkle root hashes.",
            "• Live generation switching occurs with zero downtime and no system restart required.",
            "• Instant Rollback: Flips atomic symlink pointer back to Generation 1 in 0.04 seconds!"
        ]
    },
    {
        "id": "scene7_multiabi",
        "image": "assets/ananta_multi_abi_exec.png",
        "category": "LIVE DEMO 4: UNIVERSAL MULTI-ABI",
        "title": "Running Windows PE & macOS Mach-O Natively",
        "subtitle": "Cross-Platform Execution Without Hypervisor or VM Latency",
        "voice": (
            "Our fourth demonstration showcases the Universal Multi-ABI subsystem. Notice how "
            "Windows PE binaries like putty.exe and Apple macOS Mach-O bundles like Calculator.app "
            "execute natively side-by-side with Linux ELF64 processes. Foreign system calls are "
            "translated into microkernel IPC messages with zero virtual machine overhead."
        ),
        "bullets": [
            "• WinApp: Translates Win32 PE32+ (putty.exe) NT APIs directly to microkernel IPC.",
            "• MacApp: Maps 64-bit Mach-O (Calculator.app) segments with Darwin dyld emulation.",
            "• Both execute concurrently alongside native Linux ELF64 processes with 0% VM tax."
        ]
    },
    {
        "id": "scene8_nano",
        "image": "assets/ananta_nano_editor.png",
        "category": "LIVE DEMO 5: USER EXPERIENCE",
        "title": "Interactive GNU nano 8.0 Terminal Editor",
        "subtitle": "Direct Hardware VGA Text Rendering for System Administration",
        "voice": (
            "In our fifth demonstration, we showcase interactive terminal productivity. Using "
            "GNU nano 8.0 over hardware VGA text rendering, administrators can author and modify "
            "declarative manifests live. The changes are immediately validated, compiled, and "
            "cryptographically versioned into new system generations."
        ),
        "bullets": [
            "• Full NCURSES terminal support with hardware accelerated 1280x800 VGA console.",
            "• System administrators edit declarative manifests (/etc/ananta/system.conf) live.",
            "• Changes are validated, compiled, and versioned atomically into system flakes."
        ]
    },
    {
        "id": "scene9_paper",
        "image": "assets/ananta_logo.jpg",
        "category": "RESEARCH & CONCLUSION",
        "title": "Academic Research Paper & Open Source",
        "subtitle": "Published Documentation, Formal Proofs & Complete Repository",
        "voice": (
            "AnantaOS represents a complete paradigm shift for operating system security and "
            "state management. The full academic research paper, formal proofs, and complete Rust "
            "source code are freely available in our GitHub repository. Thank you for exploring AnantaOS."
        ),
        "bullets": [
            "• Official Paper: 'AnantaOS: A Declarative, Content-Addressed Microkernel...' (RESEARCH_PAPER.md).",
            "• GitHub Repository: https://github.com/akashbiswas7074/AetherOS.",
            "• 19 Comprehensive Rust Unit Tests Passing | Complete Bootable QCOW2 Disk Available."
        ]
    }
]

def get_audio_duration(file_path):
    cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", file_path
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    info = json.loads(res.stdout)
    return float(info["format"]["duration"])

def generate_voice(idx, text):
    raw_wav = os.path.join(TMP_DIR, f"voice_{idx:02d}_raw.wav")
    clean_wav = os.path.join(TMP_DIR, f"voice_{idx:02d}.wav")
    
    # 1. Synthesize with espeak-ng (en-us+m3 gives a clear, authoritative deep tech voice)
    cmd = [
        ESPEAK_BIN,
        "-v", "en-us+m3",
        "-s", "142",  # Natural speech cadence
        "-p", "45",   # Natural vocal pitch
        "-g", "5",    # Subtle pause length
        text,
        "-w", raw_wav
    ]
    subprocess.run(cmd, check=True)
    
    # 2. Process with ffmpeg audio filters for studio clarity & compression
    filter_chain = (
        "highpass=f=100,lowpass=f=7500,"
        "equalizer=f=3000:t=q:w=1:g=2.5,"
        "equalizer=f=250:t=q:w=1:g=2.0,"
        "acompressor=threshold=-16dB:ratio=3.5:attack=20:release=150,"
        "volume=1.4"
    )
    cmd_proc = [
        "ffmpeg", "-y", "-i", raw_wav,
        "-af", filter_chain,
        clean_wav
    ]
    subprocess.run(cmd_proc, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return clean_wav

def render_scene(idx, scene):
    out_file = os.path.join(TMP_DIR, f"scene_{idx:02d}.mp4")
    if os.path.exists(out_file) and os.path.getsize(out_file) > 10000:
        print(f"[CACHE] Scene {idx+1}/{len(SCENES)} already rendered. Reusing.")
        return out_file
    img_path = os.path.abspath(scene["image"])
    
    # 1. Generate Voice
    voice_wav = generate_voice(idx, scene["voice"])
    voice_dur = get_audio_duration(voice_wav)
    
    # Pad duration: 0.6s intro lead-in, voice, and 1.2s outro pause
    lead_in = 0.6
    total_scene_dur = round(lead_in + voice_dur + 1.2, 2)
    
    print(f"[*] Scene {idx+1}/{len(SCENES)}: '{scene['title']}' (Voice: {voice_dur:.1f}s, Total: {total_scene_dur:.1f}s)...")
    
    def esc(text):
        return text.replace("'", "").replace("%", " percent").replace("#", "Number ").replace(":", "\\:")
    
    cat_text = esc(scene["category"])
    title_text = esc(scene["title"])
    sub_text = esc(scene["subtitle"])
    
    # Bottom bullet annotations
    bullet_draws = []
    start_y = 905
    for i, b in enumerate(scene["bullets"]):
        b_esc = esc(b)
        y_pos = start_y + (i * 38)
        color = "0x58a6ff" if "[" in b or "ALERT" in b else "0xc9d1d9"
        bullet_draws.append(
            f"drawtext=fontfile='{FONT_PATH}':text='{b_esc}':fontcolor={color}:fontsize=22:x=60:y={y_pos}"
        )
    bullets_filter = ",".join(bullet_draws)
    
    # Subtle ambient synth pad for background music
    ambient_synth = (
        f"aevalsrc="
        f"'0.025*sin(2*PI*130.81*t)*sin(0.3*t) + "
        f"0.020*sin(2*PI*196.00*t)*cos(0.2*t) + "
        f"0.018*sin(2*PI*261.63*t) + "
        f"0.015*sin(2*PI*392.00*t)*sin(0.15*t)'"
        f":d={total_scene_dur}:s=44100[bg_music];"
        f"[bg_music]afade=t=in:st=0:d=1.0,afade=t=out:st={total_scene_dur-1.0}:d=1.0[bg_faded];"
        f"[1:a]adelay={int(lead_in*1000)}|{int(lead_in*1000)}[delayed_voice];"
        f"[bg_faded][delayed_voice]amix=inputs=2:weights=1 3:dropout_transition=2[aout]"
    )
    
    # Video layout & compositing filter
    filter_complex = (
        f"[2:v]scale=1240:680:force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2[scaled_img];"
        f"[0:v][scaled_img]overlay=(W-w)/2:190[ov1];"
        f"[ov1]"
        f"drawbox=x=0:y=0:w=1920:h=60:color=0x161b22@1.0:t=fill,"
        f"drawbox=x=0:y=60:w=1920:h=2:color=0x388bfd@1.0:t=fill,"
        f"drawtext=fontfile='{FONT_PATH}':text='ANANTAOS ARCHITECTURAL & LIVE WORKFLOW DEMONSTRATION':fontcolor=0x79c0ff:fontsize=20:x=60:y=20,"
        f"drawtext=fontfile='{FONT_PATH}':text='{cat_text}':fontcolor=0xff7b72:fontsize=20:x=1920-text_w-60:y=20,"
        f"drawtext=fontfile='{FONT_PATH}':text='{title_text}':fontcolor=0xffffff:fontsize=36:x=60:y=80,"
        f"drawtext=fontfile='{FONT_PATH}':text='{sub_text}':fontcolor=0x8b949e:fontsize=22:x=60:y=130,"
        f"drawbox=x=40:y=885:w=1840:h=175:color=0x161b22@0.9:t=fill,"
        f"drawbox=x=40:y=885:w=1840:h=175:color=0x30363d@1.0:t=2,"
        f"{bullets_filter},"
        f"fade=t=in:st=0:d=0.5,fade=t=out:st={total_scene_dur-0.5}:d=0.5[vout];"
        f"{ambient_synth}"
    )
    
    cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", f"color=c=0x0d1117:s=1920x1080:d={total_scene_dur}",
        "-i", voice_wav,
        "-i", img_path,
        "-filter_complex", filter_complex,
        "-map", "[vout]",
        "-map", "[aout]",
        "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        out_file
    ]
    
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"[ERROR] Scene {idx+1} failed:", res.stderr[-500:])
        sys.exit(1)
        
    print(f"[OK] Scene {idx+1} rendered with synchronized voice narration.")
    return out_file

def main():
    scene_files = []
    for idx, scene in enumerate(SCENES):
        scene_files.append(render_scene(idx, scene))
        
    concat_txt = os.path.join(TMP_DIR, "concat.txt")
    with open(concat_txt, "w") as f:
        for sf in scene_files:
            f.write(f"file '{sf}'\n")
            
    print(f"[*] Concatenating all scenes into master video: {OUTPUT_VIDEO}...")
    final_cmd = [
        "ffmpeg", "-y",
        "-f", "concat", "-safe", "0", "-i", concat_txt,
        "-c:v", "copy",
        "-c:a", "copy",
        "-movflags", "+faststart",
        OUTPUT_VIDEO
    ]
    res = subprocess.run(final_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print("[ERROR] Final concat failed:", res.stderr[-500:])
        sys.exit(1)
        
    size_mb = os.path.getsize(OUTPUT_VIDEO) / (1024 * 1024)
    total_duration = get_audio_duration(OUTPUT_VIDEO)
    print(f"\n=======================================================")
    print(f" [SUCCESS] Master Explainer Video Rendered!")
    print(f" File: {OUTPUT_VIDEO}")
    print(f" Duration: {total_duration:.1f} seconds (~{total_duration/60:.1f} minutes)")
    print(f" Size: {size_mb:.2f} MB")
    print(f" Resolution: 1920x1080 (1080p Full HD)")
    print(f" Audio: Voiceover Narration + Ambient Electronic Synth")
    print(f"=======================================================")

if __name__ == "__main__":
    main()
