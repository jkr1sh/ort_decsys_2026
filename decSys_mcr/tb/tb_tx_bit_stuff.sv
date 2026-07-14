`timescale 1ns / 1ps

module tb_tx_bit_stuff;

    // Signals
    logic clk, rst;
    logic en_in, d_in;
    logic ready, en_out, d_out;

    // Instantiate DUT
    tx_bit_stuff dut (
        .clk    (clk),
        .rst    (rst),
        .en_in  (en_in),
        .d_in   (d_in),
        .ready  (ready),
        .en_out (en_out),
        .d_out  (d_out)
    );

    // Clock generation (50MHz)
    always #10 clk = ~clk;

    // VCD Dump
    string vcd_filename;
    initial begin
        if ($value$plusargs("vcdfile=%s", vcd_filename)) begin
            $dumpfile(vcd_filename);
        end else begin
            $dumpfile("dump.vcd");
        end
        $dumpvars(0, tb_tx_bit_stuff);
    end

    // Monitor
    initial begin
        $monitor("Time: %4t ns | en_in: %b | d_in: %b || ready: %b | en_out: %b | d_out: %b | ones: %0d", 
                 $time, en_in, d_in, ready, en_out, d_out, dut.ones_count);
    end

    // Task: Serialize with backpressure handling (FSM simulation)
    task send_byte_lsb(input logic [7:0] data_byte);
        for (int i = 0; i < 8; i++) begin
            @(negedge clk);
            d_in  = data_byte[i];
            en_in = 1;
            
            // FSM Handshake: If ready is 0, the stuffer is inserting a 0.
            // We MUST hold en_in and d_in steady and wait for the next clock.
            while (ready == 0) begin
                @(negedge clk);
            end
        end
        @(negedge clk);
        en_in = 0;
    endtask

    // Test Sequence
    initial begin
        clk = 0; rst = 1; en_in = 0; d_in = 0;
        
        repeat (2) @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("\n--- Sending 0xFF (8 consecutive ones) ---");
        // Expectation: 1 1 1 1 1 (stuffed 0) 1 1 1
        send_byte_lsb(8'hFF);

        repeat (3) @(negedge clk);

        $display("\n--- Sending 0x7E (Inside Payload) ---");
        // Expectation: 0 1 1 1 1 1 (stuffed 0) 1 0 
        // This proves that if a flag pattern accidentally appears in the payload, 
        // the stuffer correctly destroys it by stuffing a 0.
        send_byte_lsb(8'h7E);

        repeat (5) @(negedge clk);
        $display("\nTX Stuffer Simulation Finished!");
        $finish;
    end

endmodule