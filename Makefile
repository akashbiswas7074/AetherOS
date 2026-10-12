.PHONY: all build check test clean run sim build-image run-vm run-vm-headless

KERNEL_ELF = target/x86_64-unknown-none/debug/aether-kernel
DISK_IMAGE = aetheros.img
QEMU ?= $(shell which qemu-system-x86_64 2>/dev/null || echo /nix/store/gx222l0zm41h4zqrgpb07nc0brwpv3nk-qemu-11.1.0/bin/qemu-system-x86_64)

all: build-image check test

build:
	cargo build --package aether-kernel

check:
	cargo check --package casfs --package aether-manifest --package aether-compat --package aether-security

test:
	cargo test --package casfs --package aether-manifest --package aether-compat --package aether-security

sim:
	cargo run --package aether-manifest --bin boot_sim

# Build the real bootable OS disk image (MBR Bootloader + Protected Mode Graphical GUI Kernel)
build-image:
	nasm -f bin boot/boot.asm -o boot/boot.bin
	nasm -f bin kernel/kernel_gui.asm -o kernel/kernel_gui.bin
	cat boot/boot.bin kernel/kernel_gui.bin > $(DISK_IMAGE)
	truncate -s 1440k $(DISK_IMAGE)
	@echo "=================================================="
	@echo "  Bootable AetherOS Disk Image Ready: $(DISK_IMAGE)"
	@echo "=================================================="

# Run AetherOS inside QEMU Virtual Machine with full Terminal Console
run-vm: build-image
	@echo "=================================================================="
	@echo "  AetherOS Terminal Console Started (VGA 80x25 Mode 03h)!"
	@echo "  Full-screen terminal interface with hardware blinking cursor."
	@echo "  Try commands: ab, ls, cd bin, pwd, uname -a, ps aux, free -m, etc."
	@echo "=================================================================="
	$(QEMU) \
		-name "AetherOS Terminal Console" \
		-drive file=$(DISK_IMAGE),format=raw,if=floppy,file.locking=off \
		-nic user,model=e1000,mac=52:54:00:12:34:56 \
		-vga std \
		-m 512M

run: run-linux

# Run Genuine Linux Environment with Pre-installed GNU nano, GCC, Python 3, and Git
run-linux:
	@echo "=================================================================="
	@echo "  AetherOS Genuine Linux Environment (Kernel 6.6.142 x86_64)!"
	@echo "  Booting directly from Persistent Hard Disk: build/aether-linux.qcow2"
	@echo "  Pre-installed Apps: nano, gcc, python3, git, neofetch"
	@echo "  Login: root (no password)"
	@echo "=================================================================="
	$(QEMU) \
		-name "AetherOS Genuine Linux Environment" \
		-drive file=build/aether-linux.qcow2,format=qcow2,if=virtio,file.locking=off \
		-m 1024M \
		-nic user,model=virtio-net-pci \
		-vga std

# Run AetherOS in VM headlessly and capture boot screenshot
run-vm-headless: build-image
	(sleep 2; echo 'screendump vm_screen.ppm'; sleep 1; echo 'quit') | \
		qemu-system-x86_64 -drive file=$(DISK_IMAGE),format=raw,if=floppy,file.locking=off -nic user,model=e1000,mac=52:54:00:12:34:56 -vga std -monitor stdio -display none
	python3 -c "import struct, zlib; f=open('vm_screen.ppm','rb'); f.readline(); dims=f.readline().strip().split(); w,h=int(dims[0]),int(dims[1]); f.readline(); raw=f.read(); \
		rows=[b'\x00'+raw[y*w*3:(y+1)*w*3] for y in range(h)]; idat=zlib.compress(b''.join(rows)); \
		c=lambda t,d: struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff); \
		open('aetheros_vm_boot.png','wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+c(b'IDAT',idat)+c(b'IEND',b''))"
	@echo "VM Boot Screenshot captured to aetheros_vm_boot.png"

clean:
	cargo clean
	rm -f boot/*.bin kernel/*.bin $(DISK_IMAGE) vm_screen.ppm aetheros_vm_boot.png
