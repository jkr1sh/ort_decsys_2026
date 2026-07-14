// rtl/tx_bit_stuff.sv
`timescale 1ns / 1ps

module tx_bit_stuff (
    input  logic clk,
    input  logic rst,
    input  logic en_in,   // High when top-level FSM has a valid bit (Payload or FCS)
    input  logic d_in,    // The raw bit from the FSM
    output logic ready,   // High = ready for data. Low = FSM MUST hold en_in & d_in
    output logic en_out,  // High when sending a bit to NRZI encoder
    output logic d_out    // The stuffed bitstream
);

    logic [2:0] ones_count;
    logic       stuff_next;

    // If we have seen 5 consecutive ones, we MUST stuff a zero next cycle
    assign stuff_next = (ones_count == 3'd5);

    // Tell upstream FSM to pause its bit shifting while we insert the zero
    assign ready = ~stuff_next;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ones_count <= 3'd0;
            en_out     <= 1'b0;
            d_out      <= 1'b1; // Idle state is high
        end else begin
            if (stuff_next) begin
                // Insert the stuffed zero, overriding incoming data
                en_out     <= 1'b1;
                d_out      <= 1'b0;
                ones_count <= 3'd0; // Reset counter after stuffing
            end else if (en_in) begin
                // Pass the bit through normally
                en_out <= 1'b1;
                d_out  <= d_in;

                // Track consecutive ones
                if (d_in == 1'b1) begin
                    ones_count <= ones_count + 3'd1;
                end else begin
                    ones_count <= 3'd0;
                end
            end else begin
                // Pipeline is idle
                en_out <= 1'b0;
            end
        end
    end

endmodule