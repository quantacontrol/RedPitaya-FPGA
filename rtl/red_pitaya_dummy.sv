module red_pitaya_dummy (
  sys_bus_if.s bus
);

always_ff @(posedge bus.clk)
if (!bus.rstn) begin
  bus.ack <= 1'b0;
  bus.err <= 1'b0;
  bus.rdata <= 32'd0;
end else begin
  bus.ack <= bus.wen | bus.ren;
  bus.err <= 1'b0;
  // Keep data valid, do not clear immediately after ren goes low, to work with CDC logic
  if (bus.ren) begin
    bus.rdata <= 32'hDEADBEEF;
  end
end

endmodule
