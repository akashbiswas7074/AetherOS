{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    cargo
    rustc
    nasm
    qemu
    xorriso
    mtools
    gdb
    pkg-config
  ];

  shellHook = ''
    echo "=================================================="
    echo "  AetherOS Declarative Microkernel Environment    "
    echo "  Rust: $(rustc --version)"
    echo "  QEMU: $(qemu-system-x86_64 --version | head -n 1)"
    echo "=================================================="
  '';
}
