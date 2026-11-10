// Build configuration of the VG93 model for the physical floppy drives of the MSX core on the Karabas Go
// (msx_fdc_phys.v): replaces the empty default of the upstream rtl/vg93_config.vh
// (github.com/demyanenko-d/FD1793_1818VG93). The macros are described in vg93_top.v.
// SYSCLK is clk_sys (42.857 MHz), the clock of the machine: one clock domain with the bus of the VY-0010, no clock
// from logic. CLK is 1 MHz (the WD2793 of the MSX disk interfaces): the step rates 6 / 12 / 20 / 30 ms.
`ifndef VG93_CONFIG_VH
`define VG93_CONFIG_VH
`define VG93_ROM_FILE "rtl/vg93/vg93-microcode-rom.hex"   // from src/, as the other ROM images
`define VG93_EMBEDDED                 // DRQ / INTRQ push-pull inside the FPGA
`define VG93_MFM_ONLY                 // DDEN_n tied low
`define VG93_NO_TEST                  // TEST_n tied high
`define VG93_NO_RG                    // RG is not used (the separator is free running)
`define VG93_NO_PIN33                 // /VFOE is not used
`define VG93_FAST_SYSCLK              // SYSCLK >= 40 MHz; the separator gives /RAWREAD pulses of one SYSCLK
`endif
