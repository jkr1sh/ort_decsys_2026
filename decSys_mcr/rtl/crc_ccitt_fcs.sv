// rtl/crc_ccitt_fcs.sv
`timescale 1ns / 1ps

module crc_ccitt_fcs (
    input  logic        clk,
    input  logic        rst,       // Active-high reset (assert when opening 0x7E flag is detected)
    input  logic        en,    // High when a valid, unstuffed data bit is present
    input  logic        data_bit,  // The incoming LSB-first data bit
    output logic [15:0] crc_out,   // The inverted CRC to append to TX
    output logic        crc_valid  // High if the RX frame passes the CRC check
);

    logic [15:0] crc_reg;
    logic        feedback;

    // In LSB-first SDLC, feedback is the XOR of incoming bit and LSB of the register
    assign feedback = data_bit ^ crc_reg[0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // SDLC requires the CRC register to be initialized to all 1s
            crc_reg <= 16'hFFFF; 
        end else if (en) begin
            if (feedback)
                // Shift right and XOR with the LSB-reversed CCITT polynomial
                crc_reg <= (crc_reg >> 1) ^ 16'h8408;
            else
                // Just shift right
                crc_reg <= (crc_reg >> 1);
        end
    end

    // For TX: SDLC requires the final CRC to be inverted before transmission
    assign crc_out = ~crc_reg;

    // For RX: The "Magic Residue" Check
    // If run over the payload AND the incoming inverted CRC, it settles at exactly 0xF0B8
    assign crc_valid = (crc_reg == 16'hF0B8);

endmodule