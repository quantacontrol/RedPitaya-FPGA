# Vivado build script for rp_minimal
set project_name rp_minimal_proj
set project_dir  "./vivado_project"
set output_dir   "./out"

# Create output directory if it doesn't exist
file mkdir $output_dir

# Create project
create_project -force $project_name $project_dir -part xc7z010clg400-1

# Add source files
add_files [glob ./src/*.sv]
add_files [glob ../modeling/rtl/*.sv]
add_files [glob ../modeling/rtl/*.mem]

# Add constraints
add_files -fileset constrs_1 ./src/red_pitaya.xdc

# Build Block Design
source ./src/build_bd.tcl

# Create BD wrapper
make_wrapper -files [get_files $project_dir/$project_name.srcs/sources_1/bd/ps_system/ps_system.bd] -top
add_files -norecurse $project_dir/$project_name.srcs/sources_1/bd/ps_system/hdl/ps_system_wrapper.v

# Set top-level
set_property top top [current_fileset]

# Run synthesis
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Run implementation
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Check for errors
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}

# Copy bitstream to output directory
file copy -force $project_dir/$project_name.runs/impl_1/top.bit $output_dir/rp_minimal.bit

# Export Hardware Platform (.xsa)
write_hw_platform -fixed -force -include_bit -file $output_dir/rp_minimal.xsa

puts "Build complete! Bitstream and XSA are in $output_dir"
