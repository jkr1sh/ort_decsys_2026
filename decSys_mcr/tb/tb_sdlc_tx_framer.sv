`timescale 1ns / 1ps

module tb_sdlc_tx_framer;

    // System Signals
    logic clk;
    logic rst;

    // User Interface (Inputs to DUT)
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_last;
    
    // User Interface (Outputs from DUT)
    logic       tx_ready;

    // Physical Layer (Outputs to NRZI)
    logic       tx_en_out;
    logic       tx_d_out;

    // Instantiate the DUT
    sdlc_tx_framer dut (
        .clk(clk),
        .rst(rst),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_last(tx_last),
        .tx_ready(tx_ready),
        .tx_en_out(tx_en_out),
        .tx_d_out(tx_d_out)
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
        $dumpvars(0, tb_sdlc_tx_framer);
    end

    // Monitor for physical output
    initial begin
        $monitor("Time: %6t ns | State: %0d | valid: %b | ready: %b || en_out: %b | d_out: %b", 
                 $time, dut.state, tx_valid, tx_ready, tx_en_out, tx_d_out);
    end

    // Declare the payload array at the module level for iverilog compatibility
    logic [7:0] test_payload [0:3];

    // Task: Feed an entire frame. Reads directly from module-level test_payload array.
    task send_frame(input int len);
        $display("[%8t ns] Starting frame transmission of %0d bytes...", $time, len);
        
        for (int i = 0; i < len; i++) begin
            @(negedge clk);
            tx_data  = test_payload[i];
            tx_valid = 1;
            tx_last  = (i == len - 1); // Assert tx_last on the final byte
            
            // Wait for the FSM to consume this byte (tx_ready pulses high)
            do begin
                @(negedge clk);
            end while (tx_ready == 0);
            
            $display("[%8t ns] FSM consumed byte %0d: 0x%02X", $time, i, tx_data);
        end
        
        // Drop valid immediately after the last byte is consumed by the FSM
        tx_valid = 0;
        tx_last  = 0;
    endtask

    // Test Sequence
    initial begin
        // Initialize
        clk = 0; rst = 1; 
        tx_data = 0; tx_valid = 0; tx_last = 0;
        
        // Hold reset
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        
        // Define a test payload. 
        test_payload[0] = 8'hFF;
        test_payload[1] = 8'hE0;
        
        // Send the frame (passing only the length argument)
        send_frame(2);
        
        // Wait for the FSM to finish shifting out the payload, the FCS, and the Closing Flag
        repeat (100) @(negedge clk);
        
        $display("[%8t ns] TX Framer Simulation Complete.", $time);
        $finish;
    end

endmodule