`timescale 1ns / 1ps

module tb_rx_bit_unstuff;

    // Signals
    logic clk, rst;
    logic en_in, d_in;
    logic en_out, d_out;
    logic flag_detect, abort_detect;

    // Instantiate DUT
    rx_bit_unstuff dut (
        .clk          (clk),
        .rst          (rst),
        .en_in        (en_in),
        .d_in         (d_in),
        .en_out       (en_out),
        .d_out        (d_out),
        .flag_detect  (flag_detect),
        .abort_detect (abort_detect)
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
        $dumpvars(0, tb_rx_bit_unstuff);
    end

    // Monitor
    initial begin
        $monitor("Time: %4t ns | en_in: %b | d_in: %b || en_out: %b | d_out: %b | flag: %b | abort: %b | ones: %0d", 
                 $time, en_in, d_in, en_out, d_out, flag_detect, abort_detect, dut.ones_count);
    end

    // Task: Feed a raw bit exactly as the NRZI decoder would
    task send_raw_bit(input logic bit_val);
        @(negedge clk);
        d_in  = bit_val;
        en_in = 1;
    endtask
    
    // Clear the line (idle state)
    task clear_en();
        @(negedge clk);
        en_in = 0;
    endtask

    // Test Sequence
    initial begin
        clk = 0; rst = 1; en_in = 0; d_in = 1;
        
        repeat (2) @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("\n--- Test 1: Stuffed Zero Deletion ---");
        // We send: 1, 1, 1, 1, 1, 0 (stuffed), 1, 1
        send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1);
        send_raw_bit(0); // This should be dropped (en_out = 0)
        send_raw_bit(1); send_raw_bit(1);
        clear_en();
        
        repeat (3) @(negedge clk);

        $display("\n--- Test 2: Flag Detection (0x7E) ---");
        // We send: 0, 1, 1, 1, 1, 1, 1, 0 (Should trigger flag_detect)
        send_raw_bit(0);
        send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1);
        send_raw_bit(0); 
        clear_en();

        repeat (3) @(negedge clk);
        
        $display("\n--- Test 3: Abort Sequence Detection ---");
        // We send: 0, then 7 consecutive 1s
        send_raw_bit(0);
        send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1); send_raw_bit(1);
        clear_en();

        repeat (5) @(negedge clk);
        $display("\nRX Destuffer Simulation Finished!");
        $finish;
    end

endmodule