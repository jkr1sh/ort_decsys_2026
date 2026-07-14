// rtl/sdlc_tx_framer
`timescale 1ns / 1ps

module sdlc_tx_framer (
    input  logic       clk,
    input  logic       rst,
    
    // User Interface (Byte Stream from your CPU/Memory)
    input  logic [7:0] tx_data,
    input  logic       tx_valid,    // High when you have a payload byte to send
    input  logic       tx_last,     // Assert High alongside the very LAST byte of the payload
    output logic       tx_ready,    // FSM pulses high when it consumes the byte
    
    // Output to Physical Layer (To NRZI Encoder)
    output logic       tx_en_out,
    output logic       tx_d_out
);

    typedef enum logic [2:0] {
        IDLE,
        TX_OPEN_FLAG,
        TX_PAYLOAD,
        TX_FCS,
        TX_CLOSE_FLAG
    } state_t;
    
    state_t state;
    
    logic [3:0]  bit_cnt;
    logic [7:0]  shift_reg;
    logic        is_last;
    
    // --- Sub-Module Instantiations ---
    logic        crc_rst, crc_en;
    logic [15:0] crc_out;
    
    logic stuffer_en_in, stuffer_d_in;
    logic stuffer_ready, stuffer_en_out, stuffer_d_out;
    logic flag_en_out, flag_d_out;
    
    crc_ccitt_fcs crc_inst (
        .clk(clk),
        .rst(crc_rst),
        .en(crc_en),
        .data_bit(stuffer_d_in), // Read the exact bit going into the stuffer
        .crc_out(crc_out),
        .crc_valid()
    );

    tx_bit_stuff stuffer_inst (
        .clk(clk),
        .rst(rst),
        .en_in(stuffer_en_in),
        .d_in(stuffer_d_in),
        .ready(stuffer_ready),
        .en_out(stuffer_en_out),
        .d_out(stuffer_d_out)
    );

// --- Combinatorial Routing (The Multiplexer) ---
    logic [7:0] flag_val = 8'h7E;
    assign crc_rst = (state == IDLE);
    
// --- Pipeline Alignment Registers (2-Stage for Stuffer Latency) ---
    logic   flag_en_comb, flag_d_comb;
    logic   flag_en_pipe, flag_d_pipe;
    state_t state_pipe;

    always_comb begin
        // Default internal routing
        stuffer_en_in = 0;
        stuffer_d_in  = 0;
        crc_en        = 0;
        flag_en_comb  = 0;
        flag_d_comb   = 0;
        
        case (state)
            TX_OPEN_FLAG, TX_CLOSE_FLAG: begin
                // Bypass stuffer and CRC entirely
                flag_en_comb = 1;
                flag_d_comb  = (8'h7E >> bit_cnt[2:0]) & 1'b1; // LSB first
            end
            
            TX_PAYLOAD: begin
                // Route Payload to Stuffer and CRC
                stuffer_en_in = 1;
                stuffer_d_in  = (shift_reg >> bit_cnt[2:0]) & 1'b1; // LSB first
                crc_en        = stuffer_ready;           // Only pulse CRC when stuffer accepts bit
            end
            
            TX_FCS: begin
                // Route frozen CRC to Stuffer
                stuffer_en_in = 1;
                stuffer_d_in  = (crc_out >> bit_cnt[3:0]) & 1'b1;
                crc_en        = 0; // Freeze the math!
            end
            
            default: begin end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin  
        if (rst) begin
            flag_en_pipe <= 0; 
            flag_d_pipe  <= 0; 
            state_pipe   <= IDLE;
        end else begin
            // Single stage delay!
            flag_en_pipe <= flag_en_comb;
            flag_d_pipe  <= flag_d_comb;
            state_pipe   <= state;
        end
    end

    // --- The Final Output Multiplexer (using aligned pipelines) ---
    assign tx_en_out = (state_pipe == TX_OPEN_FLAG || state_pipe == TX_CLOSE_FLAG) ? flag_en_pipe : stuffer_en_out;
    assign tx_d_out  = (state_pipe == TX_OPEN_FLAG || state_pipe == TX_CLOSE_FLAG) ? flag_d_pipe  : stuffer_d_out;



    // --- Sequential FSM (The Controller) ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            bit_cnt <= 0;
            tx_ready <= 0;
            is_last <= 0;
            shift_reg <= 0;
        end else begin
            tx_ready <= 0; // Default off (pulse behavior)
            
            case (state)
                IDLE: begin
                    if (tx_valid) begin
                        shift_reg <= tx_data;
                        is_last   <= tx_last;
                        tx_ready  <= 1; // Consume the first byte
                        state     <= TX_OPEN_FLAG;
                        bit_cnt   <= 0;
                    end
                end
                
                TX_OPEN_FLAG: begin
                    if (bit_cnt == 4'd7) begin
                        state   <= TX_PAYLOAD;
                        bit_cnt <= 0;
                    end else bit_cnt <= bit_cnt + 1;
                end
                
                TX_PAYLOAD: begin
                    if (stuffer_ready) begin
                        if (bit_cnt == 4'd7) begin
                            if (is_last) begin
                                state   <= TX_FCS;
                                bit_cnt <= 0;
                            end else if (tx_valid) begin
                                shift_reg <= tx_data;
                                is_last   <= tx_last;
                                tx_ready  <= 1; // Consume next byte
                                bit_cnt   <= 0;
                            end else begin
                                state <= IDLE; // TX Underflow error fallback
                            end
                        end else bit_cnt <= bit_cnt + 1;
                    end
                end
                
                TX_FCS: begin
                    if (stuffer_ready) begin
                        if (bit_cnt == 4'd15) begin
                            state   <= TX_CLOSE_FLAG;
                            bit_cnt <= 0;
                        end else bit_cnt <= bit_cnt + 1;
                    end
                end
                
                TX_CLOSE_FLAG: begin
                    if (bit_cnt == 4'd7) begin
                        state <= IDLE;
                    end else bit_cnt <= bit_cnt + 1;
                end
            endcase
        end
    end
endmodule