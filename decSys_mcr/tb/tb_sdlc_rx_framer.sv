`timescale 1ns / 1ps

module tb_sdlc_rx_framer;

    // System Signals
    logic clk;
    logic rst;

    // Input to DUT (From Physical Layer)
    logic       rx_en_in;
    logic       rx_d_in;

    // Outputs from DUT (To MAC/CPU)
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_end_of_frame;
    logic       rx_crc_error;
    logic       rx_abort;

    // Instantiate the DUT
    sdlc_rx_framer dut (
        .clk(clk),
        .rst(rst),
        .rx_en_in(rx_en_in),
        .rx_d_in(rx_d_in),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_end_of_frame(rx_end_of_frame),
        .rx_crc_error(rx_crc_error),
        .rx_abort(rx_abort)
    );

    // Clock Generation (50MHz)
    always #10 clk = ~clk;

    // Waveform Dumping
    string vcd_filename;
    initial begin
        if ($value$plusargs("vcdfile=%s", vcd_filename)) begin
            $dumpfile(vcd_filename);
        end else begin
            $dumpfile("dump.vcd");
        end
        $dumpvars(0, tb_sdlc_rx_framer);
    end

    // Monitor for terminal output
    initial begin
        $monitor("Time: %6t ns | State: %0d | rx_en: %b | rx_d: %b || valid: %b | data: 0x%02X | EOF: %b | CRC_ERR: %b | ABORT: %b", 
                 $time, dut.state, rx_en_in, rx_d_in, rx_valid, rx_data, rx_end_of_frame, rx_crc_error, rx_abort);
    end

    // --- Physical Layer Simulation Tasks ---
    
    // Task: Send a single bit with a realistic DPLL strobe
    task send_bit(input logic b);
        @(negedge clk);
        rx_en_in = 1;
        rx_d_in  = b;
        @(negedge clk);
        rx_en_in = 0; // Drop enable (simulates asynchronous oversampling)
        @(negedge clk); // Idle cycle between bits
    endtask

    // Task: Send a raw byte (LSB first, NO bit-stuffing applied)
    task send_raw_byte(input logic [7:0] b);
        for (int i = 0; i < 8; i++) begin
            send_bit(b[i]);
        end
    endtask

    // --- Test Sequence ---
    initial begin
        // Initialize
        clk = 0; rst = 1;
        rx_en_in = 0; rx_d_in = 1; // Idle state for SDLC line is '1'

        // Hold reset
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        $display("\n[%8t ns] --- TEST 1: Normal Frame (with intentionally bad CRC) ---", $time);
        
        // 1. Send Opening Flag (0x7E)
        send_raw_byte(8'h7E);
        
        // 2. Send Payload (Chosen specifically so it doesn't trigger bit-stuffing)
        send_raw_byte(8'hAA);
        send_raw_byte(8'h55);
        
        // 3. Send Dummy FCS/CRC 
        send_raw_byte(8'h12);
        send_raw_byte(8'h34);
        
        // 4. Send Closing Flag (0x7E)
        send_raw_byte(8'h7E);

        // Wait a moment between frames
        repeat (10) @(negedge clk);

        $display("\n[%8t ns] --- TEST 2: Abort Sequence Detection ---", $time);
        
        // 1. Send Opening Flag
        send_raw_byte(8'h7E);
        
        // 2. Send a partial payload byte
        send_raw_byte(8'hAA);
        
        // 3. Send Abort Sequence (0xFF is 8 consecutive ones, which triggers the abort)
        send_raw_byte(8'hFF); 

        // Let the simulation settle
        repeat (20) @(negedge clk);
        
        $display("[%8t ns] RX Framer Simulation Complete.\n", $time);
        $finish;
    end

endmodule