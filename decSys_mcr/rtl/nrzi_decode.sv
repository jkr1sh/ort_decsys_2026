// rtl/nrzi_decode.sv
`timescale 1ns / 1ps

module nrzi_decode (
    input  logic clk,
    input  logic rst,
    input  logic en,       // High when DPLL says it's time to sample
    input  logic nrzi_in,  // The encoded bit from the physical wire
    output logic d_out     // The recovered raw bit (goes to SDLC RX Framer)
);

    logic prev_nrzi;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_nrzi <= 1'b1; // SDLC idle state is High
            d_out     <= 1'b1; // Default to outputting 1s (Idle)
        end else if (en) begin
            // If the line toggled, it's a 0. If it held, it's a 1.
            d_out <= (nrzi_in == prev_nrzi) ? 1'b1 : 1'b0;
            
            // Save the current state to compare against the next bit
            prev_nrzi <= nrzi_in;
        end
    end

endmodule