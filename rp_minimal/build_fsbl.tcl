# XSCT script to generate FSBL
set xsa_file "./out/rp_minimal.xsa"
set output_dir "./out/fsbl"

# Create output directory
file mkdir $output_dir

# Set workspace
setws ./out/ws

# Create platform project
platform create -name hw_platform -hw $xsa_file -proc ps7_cortexa9_0 -os standalone -out $output_dir

# Create FSBL application
app create -name fsbl -platform hw_platform -domain standalone_domain -template {Zynq FSBL}

# Build
app build -name fsbl

# Copy FSBL executable
file copy -force ./out/ws/fsbl/Debug/fsbl.elf $output_dir/fsbl.elf

puts "FSBL generated in $output_dir/fsbl.elf"
