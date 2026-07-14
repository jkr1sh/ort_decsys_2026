// rtl/sdlc_rx_framer.sv
`timescale 1ns / 1ps

module sdlc_rx_framer (
    input  logic       clk,
    input  logic       rst,
    
    input  logic       rx_en_in,
    input  logic       rx_d_in,
    
    output logic [7:0] rx_data,
    output logic       rx_valid,        
    output logic       rx_end_of_frame, 
    output logic       rx_crc_error,    
    output logic       rx_abort         
);

    logic destuff_en, destuff_d;
    logic flag_detect, abort_detect;
    
    rx_bit_unstuff destuff_inst (
        .clk(clk), .rst(rst),
        .en_in(rx_en_in), .d_in(rx_d_in),
        .en_out(destuff_en), .d_out(destuff_d),
        .flag_detect(flag_detect), .abort_detect(abort_detect)
    );

    // --- The 7-Bit CRC Shield ---
    logic [6:0] crc_delay_line;
    logic [2:0] crc_valid_count;
    logic       crc_delay_full;
    logic       crc_en, crc_rst, crc_valid;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            crc_delay_line  <= 7'b0;
            crc_valid_count <= 3'd0;
        end else begin
            if (flag_detect || abort_detect || state == HUNT) begin
                crc_valid_count <= 3'd0; // Reset shield for next frame
            end else if (state == RECEIVE && destuff_en) begin
                crc_delay_line <= {destuff_d, crc_delay_line[6:1]};
                if (!crc_delay_full) begin
                    crc_valid_count <= crc_valid_count + 3'd1;
                end
            end
        end
    end
    
    assign crc_delay_full = (crc_valid_count == 3'd7);
    
    // Only pulse CRC when delay line pushes out a valid payload bit
    assign crc_en = (state == RECEIVE && destuff_en && crc_delay_full);

    crc_ccitt_fcs crc_inst (
        .clk(clk),
        .rst(crc_rst),
        .en(crc_en),
        .data_bit(crc_delay_line[0]), // Feed from the BACK of the delay line
        .crc_out(),
        .crc_valid(crc_valid)
    );

    // --- Bulletproof CRC Reset ---
    // Delay flag_detect by 1 cycle to prevent async reset race conditions
    logic flag_detect_d1;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) flag_detect_d1 <= 1'b0;
        else     flag_detect_d1 <= flag_detect;
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) crc_rst <= 1'b1;
        else     crc_rst <= flag_detect_d1 || (state == HUNT);
    end

    // --- FSM & Shadow Buffers ---
    typedef enum logic [1:0] { HUNT, RECEIVE } state_t;
    state_t state;
    
    logic [2:0]  bit_cnt;
    logic [7:0]  shift_reg;
    logic [15:0] byte_cnt;
    logic [7:0]  byte_history_1;
    logic [7:0]  byte_history_2;

    assign rx_abort = abort_detect;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= HUNT;
            bit_cnt         <= 0;
            byte_cnt        <= 0;
            rx_valid        <= 0;
            rx_end_of_frame <= 0;
            rx_crc_error    <= 0;
            rx_data         <= 0;
            byte_history_1  <= 0;
            byte_history_2  <= 0;
        end else begin
            rx_valid        <= 0;
            rx_end_of_frame <= 0;
            rx_crc_error    <= 0;
            
            if (abort_detect) begin
                state <= HUNT;
            end else if (flag_detect) begin
                if (state == RECEIVE && byte_cnt >= 2) begin
                    rx_end_of_frame <= 1;
                    if (!crc_valid) rx_crc_error <= 1;
                end
                
                state    <= RECEIVE; 
                bit_cnt  <= 0;
                byte_cnt <= 0;
            end else if (state == RECEIVE && destuff_en) begin
                shift_reg <= {destuff_d, shift_reg[7:1]};
                
                if (bit_cnt == 7) begin
                    // SHADOW BUFFER: Hides the 2 CRC bytes from the CPU
                    byte_history_1 <= {destuff_d, shift_reg[7:1]};
                    byte_history_2 <= byte_history_1;
                    rx_data        <= byte_history_2;
                    
                    if (byte_cnt >= 2) rx_valid <= 1;
                    
                    byte_cnt <= byte_cnt + 1;
                    bit_cnt  <= 0;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
    end

endmodule