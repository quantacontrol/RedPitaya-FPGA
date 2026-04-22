# XSCT script using HSI commands to generate FSBL
set xsa_file "./out/rp_minimal.xsa"
set output_dir "./out/fsbl"

# Create output directory
file mkdir $output_dir

# Use HSI commands
hsi::open_hw_design $xsa_file
hsi::create_sw_design fsbl -proc ps7_cortexa9_0 -os standalone
hsi::add_library xilffs
hsi::add_library xilrsa
hsi::generate_app -app zynq_fsbl -dir $output_dir -compile
hsi::close_hw_design [hsi::current_hw_design]

puts "FSBL generated in $output_dir"
