# AMDGPU FCLK 800 MHz Floor Patch

A targeted Linux kernel patch for **AMD Ryzen 7000 & 8000 Series APUs (Phoenix / Hawk Point, SMU 13.0.4, Radeon 780M)** to fix initial UI stutter and scroll lag on battery.

---

## The Problem

On modern AMD laptops (such as the Lenovo IdeaPad Pro 5 14AHP9, Slim 7, Yoga, ThinkPad, etc.) equipped with high-refresh displays (e.g., 2880×1800 @ 120 Hz OLED):

1. **Aggressive Battery Downclocking:** When running on battery power in `auto` power mode, the AMD PMFW (Power Management Firmware) and `amdgpu` driver drop the Infinity Fabric clock (`FCLK`) to an idle floor of **400 MHz**.
2. **Initial Stutter / Lag:** When resuming interaction (e.g., scrolling a browser or document after a 2-second pause), 400 MHz fabric bandwidth is insufficient to push 2.8K frames at 120 Hz without dropping frames.
3. **Delayed Ramp-up:** After continuous scrolling, the SMU hardware governor detects load and scales to 1600 MHz (smoothing out the animation), but the initial stutter repeats every time the system idles.
4. **Why manual governor modes don't work:** Setting `manual` mode freezes the clock at a static frequency and disables dynamic scaling up to 1600 MHz under heavy load.

---

## The Solution

This patch clamps the **minimum idle floor of FCLK to 800 MHz** while keeping the dynamic `auto` governor completely intact:

* **Zero Initial Stutter:** 800 MHz provides plenty of memory fabric bandwidth for instant 120 Hz frame delivery.
* **Full Dynamic Boost (1600 MHz):** Heavy scrolling, video decoding, and 3D gaming still ramp up to 1600 MHz automatically.
* **No Sleep Drain Impact:** During suspend/sleep (`s2idle` / S0ix), the clock generator (PLL) is completely gated (0 Hz / off), meaning standby power consumption is unaffected.
* **Negligible Idle Power Difference:** The power difference between 400 MHz and 800 MHz FCLK in idle is less than ~0.2W.

---

## Affected & Tested Hardware

* **CPU / APU:** AMD Ryzen 7 8845HS / 7840HS / 8040 & 7040 series (Phoenix / Hawk Point)
* **SMU Version:** MP1 / SMU 13.0.4 (`smu_v13_0_4_ppt.c`)
* **Display Core:** DCN 3.1.4 (`dcn314_clk_mgr.c`)
* **Tested Machine:** Lenovo IdeaPad Pro 5 14AHP9 (Samsung 2880×1800 120Hz OLED)
* **Linux Kernel:** 7.x (tested on 7.2.5+)

---

## What the Patch Changes

The patch (`amdgpu-fclk-floor.patch`) modifies:

1. **`smu_v13_0_4_ppt.c`**:
   * Initial hardware setup (`smu_v13_0_4_set_default_dpm_tables`): Sends `SetHardMinFclkByFreq(800)` and `SetSoftMaxFclkByFreq(1600)` to the hardware upon driver load.
   * DPM table clamp: Raises DfPstate levels below 800 MHz to 800 MHz so sysfs (`pp_dpm_fclk`) and GPU monitors (MangoHud, amdgpu_top, Mission Center) display valid states instead of `N/A`.
   * Dynamic level clamp (`smu_v13_0_4_set_performance_level` & `smu_v13_0_4_set_soft_freq_limited_range`): Ensures that whenever AC is unplugged or power profiles change, the minimum floor never drops below 800 MHz.
2. **`dcn314_clk_mgr.c`**:
   * Aligns Display Core Next (DCN) bandwidth watermark calculations to assume a guaranteed 800 MHz FCLK floor.
3. **`amdgpu_trace.h`**:
   * Fixes out-of-tree trace header resolution (`TRACE_INCLUDE_PATH .`) for modular compilation.

---

## Quick Start

### Prerequisites
Make sure your kernel headers are installed (e.g. `linux-headers` or `linux-omarchy-headers` on Arch-based systems).

```bash
# On Arch / Omarchy
sudo pacman -S --needed base-devel linux-headers
```

### Installation
```bash
git clone https://github.com/b-lov/amdgpu-800mhz-patch.git
cd amdgpu-800mhz-patch
sudo ./rebuild.sh
```

Then **reboot** your machine.

---

## Verifying the Fix

After rebooting on battery, check the current FCLK state:

```bash
cat /sys/class/drm/card1/device/pp_dpm_fclk
```

**Expected output (on battery, idle):**
```text
0: 800Mhz *
1: 800Mhz *
2: 1600Mhz 
```

The asterisk `*` confirms the hardware is running at 800 MHz (not 400 MHz). When you apply GPU load or plug in AC power, the asterisk dynamically switches to `2: 1600Mhz *`.

Verify the power performance level remains in automatic mode:
```bash
cat /sys/class/drm/card1/device/power_dpm_force_performance_level
# Output: auto
```

---

## Reverting to Factory Stock

If you ever want to remove the patch and restore the original distribution driver:

```bash
sudo ./uninstall.sh
```

Or manually:
```bash
sudo rm -f /usr/lib/modules/$(uname -r)/updates/amdgpu.ko.zst
sudo depmod -a
sudo limine-mkinitcpio   # or: sudo mkinitcpio -P
```

Then reboot. Your system will immediately load the unmodified factory driver.

---

## License

GPL-2.0 (matching the upstream Linux kernel and amdgpu driver).
