// tb/tb_nrzi_decode.sv
`timescale 1ns / 1ps

module tb_nrzi_decode;

    // Signals
    logic clk;
    logic rst;
    logic en;
    logic nrzi_in;
    logic d_out;

    // Instantiate ONLY the Decoder (DUT)
    nrzi_decode dut (
        .clk      (clk),
        .rst      (rst),
        .en       (en),
        .nrzi_in  (nrzi_in),
        .d_out    (d_out)
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
        $dumpvars(0, tb_nrzi_decode);
    end

    // Monitor terminal outputs
    initial begin
        $monitor("Time: %4t ns | en: %b | WIRE_IN: %b | DECODED_OUT: %b", 
                 $time, en, nrzi_in, d_out);
    end

    // Stimulus Sequence
    initial begin
        // Initialize (SDLC idle wire state is 1)
        clk = 0; rst = 1; en = 0; nrzi_in = 1;
        #35 rst = 0;
        @(posedge clk);
        
        en = 1;
        
        $display("--- Starting Basic Logic Test ---");
        
        // 1. Send HOLD (Wire stays 1) -> Expect Decoded 1
        nrzi_in = 1; @(posedge clk);
        
        // 2. Send TOGGLE (Wire drops to 0) -> Expect Decoded 0
        nrzi_in = 0; @(posedge clk);
        
        // 3. Send HOLD (Wire stays 0) -> Expect Decoded 1
        nrzi_in = 0; @(posedge clk);
        
        // 4. Send TOGGLE (Wire rises to 1) -> Expect Decoded 0
        nrzi_in = 1; @(posedge clk);
        
        $display("--- Simulating a 0x7E Flag on the Wire ---");
        // To receive 0x7E (01111110) LSB first:
        // We need: 0, 1, 1, 1, 1, 1, 1, 0
        // Starting from wire state = 1:
        
        nrzi_in = 0; @(posedge clk); // Toggle (Decodes 0)
        nrzi_in = 0; @(posedge clk); // Hold   (Decodes 1)
        nrzi_in = 0; @(posedge clk); // Hold   (Decodes 1)
        nrzi_in = 0; @(posedge clk); // Hold   (Decodes 1)
        nrzi_in = 0; @(posedge clk); // Hold   (Decodes 1)
        nrzi_in = 0; @(posedge clk); // Hold   (Decodes 1)
        nrzi_in = 0; @(posedge clk); // Hold   (Decodes 1)
        nrzi_in = 1; @(posedge clk); // Toggle (Decodes 0)
        
        en = 0;
        #40;
        
        $display("NRZI Decoder Simulation Finished!");
        $finish;
    end

endmodule