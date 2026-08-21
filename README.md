# 53M-DOS 19.0 (Real-Mode x86 OS)

53M-DOS is a lightweight 16-bit real-mode operating system written in x86 Assembly. This repository includes the ready-to-boot `53mdos.img` disk image.

## Features
- **Command Chaining (`&&`):** Execute multiple commands sequentially (e.g., `time && date` or `color green && cls`).
- **Persistent Password Reset:** Change credentials using `passwd reset` — updates write directly back to disk sector 3 and persist across reboots.
- **Built-in Nano Editor (`nano`):** Create and commit files directly to sector storage.
- **Custom System Calls:** Built-in `INT 21h` handler for character and string I/O.
- **Matrix Rain Visual (`matrix`):** BIOS video interrupt rendering for a digital rain effect.
- **Shortcuts & Commands:** Shell commands (`ver`, `echo`, `color`, `beep`, `ls`, `mkdir`, `cd`) and keyboard shortcuts (`Ctrl+L` clear screen, `Ctrl+K` poweroff).

## How to Run

### Option 1: macOS via UTM (Graphical App)
1. Download or clone this repository to get `53mdos.img`.
2. Open **[UTM](https://mac.getutm.app/)** and click **+** (Create Virtual Machine) -> **Emulate**.
3. Choose **Other** -> **Boot Image** -> **Browse** and select `53mdos.img`.
4. Click **Save** and hit **Play**.

### Option 2: macOS / Linux / Windows via QEMU
Run the following command in your terminal:
```bash
qemu-system-x86_64 -drive format=raw,file=53mdos.img
Default Login Credentials
Admin Account: Username admin | Password admin123

Guest Account: Username guest | Password guest123


---

### Quick Git Push

Once you drop `53mdos.img` and `README.md` into your folder, push it live with:

```bash
git init
git add 53mdos.img README.md
git commit -m "Add 53M-DOS 19.0 bootable image and documentation"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
git push -u origin main
