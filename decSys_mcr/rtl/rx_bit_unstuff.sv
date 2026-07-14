// rtl/rx_bit_unstuff.sv
`timescale 1ns / 1ps

module rx_bit_unstuff (
    input  logic clk,
    input  logic rst,
    input  logic en_in,        // High when NRZI decoder outputs a recovered bit
    input  logic d_in,         // The recovered bit from the line
    output logic en_out,       // High to pass valid data to CRC/RX FSM
    output logic d_out,        // The clean, unstuffed bitstream
    output logic flag_detect,  // Pulses high for 1 cycle when 0x7E is found
    output logic abort_detect  // Pulses high if 7+ ones are found
);

    // 4-bit counter prevents overflow during long line idles (15+ ones)
    logic [3:0] ones_count; 

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ones_count   <= 4'd0;
            en_out       <= 1'b0;
            d_out        <= 1'b1;
            flag_detect  <= 1'b0;
            abort_detect <= 1'b0;
        end else begin
            // Default clears for single-cycle pulses
            en_out       <= 1'b0;
            flag_detect  <= 1'b0;
            abort_detect <= 1'b0;

            if (en_in) begin
                if (d_in == 1'b1) begin
                    // Clamp at 15 to prevent wrap-around
                    if (ones_count < 4'd15) begin
                        ones_count <= ones_count + 4'd1;
                    end
                    
                    // SDLC Abort Sequence is 7 or more consecutive 1s
                    if (ones_count >= 4'd6) begin 
                        abort_detect <= 1'b1;
                    end else begin
                        en_out <= 1'b1;
                        d_out  <= 1'b1;
                    end
                end else begin 
                    // We received a 0. Check how many 1s preceded it.
                    if (ones_count == 4'd5) begin
                        // STUFFED ZERO detected. 
                        // Drop it entirely (en_out stays 0).
                    end else if (ones_count == 4'd6) begin
                        // FLAG detected (0 followed by six 1s and a 0)
                        flag_detect <= 1'b1;
                        // Do not send flag bits to the payload/CRC logic
                    end else begin
                        // Normal zero
                        en_out <= 1'b1;
                        d_out  <= 1'b0;
                    end
                    
                    // Reset consecutive ones counter on any zero
                    ones_count <= 4'd0; 
                end
            end
        end
    end

endmodule