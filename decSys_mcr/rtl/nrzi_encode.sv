// rtl/nrzi_encode.sv
`timescale 1ns / 1ps

module nrzi_encode (
    input  logic clk,
    input  logic rst,
    input  logic en,       // High when a new bit is ready to be transmitted
    input  logic d_in,     // The raw serial bit coming from the SDLC frame logic
    output logic nrzi_out  // The encoded bit going to the physical wire
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            nrzi_out <= 1'b1; // Idle State
        end else if (en) begin
            if (d_in == 1'b0) begin
                nrzi_out <= ~nrzi_out; // Toggle on 0
            end
        end
    end

endmodule