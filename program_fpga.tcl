if { $argc > 0 } {
    set bitstream_path [lindex $argv 0]
} else {
    set bitstream_path "prj/v0.94/out/red_pitaya.bit"
}

puts "Programming with bitstream: $bitstream_path"

open_hw_manager
connect_hw_server
set target [lindex [get_hw_targets] 0]
current_hw_target $target
open_hw_target

# Find the FPGA device (starts with xc7z)
set fpga_dev ""
foreach dev [get_hw_devices] {
    if {[string match "xc7z*" $dev]} {
        set fpga_dev $dev
        break
    }
}

if {$fpga_dev eq ""} {
    puts "Error: Could not find Zynq FPGA device in JTAG chain."
    exit 1
}

puts "Programming device: $fpga_dev"
current_hw_device $fpga_dev
set_property PROGRAM.FILE $bitstream_path $fpga_dev
program_hw_devices $fpga_dev
puts "Programming complete."
close_hw_manager