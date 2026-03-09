################################################################################
# HSI tcl script for building RedPitaya FSBL
#
# Usage:
# xsct red_pitaya_hsi_fsbl.tcl projectname
#
# Environment variables:
# EMBEDDEDSW_PATH - Path to embeddedsw repo (default: auto-detect from Vivado)
################################################################################

cd prj/$::argv

set path_sdk sdk

# Set embeddedsw repo path for zynq_fsbl app
# PetaLinux's xsct doesn't include zynq_fsbl, so we need Vivado's embeddedsw
if {[info exists ::env(EMBEDDEDSW_PATH)]} {
    set embeddedsw_path $::env(EMBEDDEDSW_PATH)
} elseif {[info exists ::env(XILINX_VIVADO)]} {
    set embeddedsw_path "$::env(XILINX_VIVADO)/data/embeddedsw"
} else {
    # Try common Vivado installation paths
    set vivado_paths [glob -nocomplain /home/*/tools/Xilinx/Vivado/*/data/embeddedsw /tools/Xilinx/Vivado/*/data/embeddedsw /opt/Xilinx/Vivado/*/data/embeddedsw]
    if {[llength $vivado_paths] > 0} {
        set embeddedsw_path [lindex [lsort -decreasing $vivado_paths] 0]
    } else {
        puts "ERROR: Cannot find Vivado embeddedsw. Set EMBEDDEDSW_PATH or XILINX_VIVADO environment variable."
        exit 1
    }
}
puts "Using embeddedsw from: $embeddedsw_path"
hsi::set_repo_path $embeddedsw_path

hsi open_hw_design $path_sdk/red_pitaya.xsa
hsi generate_app -hw red_pitaya_top -os standalone -proc ps7_cortexa9_0 -app zynq_fsbl -sw fsbl -dir $path_sdk/fsbl

exit
