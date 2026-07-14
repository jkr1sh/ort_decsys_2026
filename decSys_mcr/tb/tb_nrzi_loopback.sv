// tb/tb_nrzi_loopback.sv
`timescale 1ns / 1ps

module tb_nrzi_loopback;

    logic clk;
    logic rst;
    logic en;
    
    // Wire signals
    logic orig_data;       // Data fed into encoder
    logic wire_nrzi;       // The encoded "physical wire"
    logic recovered_data;  // Data coming out of decoder

    // Instantiate Encoder (TX)
    nrzi_encode tx (
        .clk      (clk),
        .rst      (rst),
        .en       (en),
        .d_in     (orig_data),
        .nrzi_out (wire_nrzi)
    );

    // Instantiate Decoder (RX)
    nrzi_decode rx (
        .clk      (clk),
        .rst      (rst),
        .en       (en),
        .nrzi_in  (wire_nrzi),
        .d_out    (recovered_data)
    );

    always #10 clk = ~clk;

    // VCD Dump
    string vcd_filename;
    initial begin
        if ($value$plusargs("vcdfile=%s", vcd_filename)) begin
            $dumpfile(vcd_filename);
        end else begin
            $dumpfile("dump.vcd");
        end
        $dumpvars(0, tb_nrzi_loopback);
    end

    // Monitor
    initial begin
        $monitor("Time: %4t ns | rst: %b | en: %b | ORIG: %b | WIRE: %b | RECOVERED: %b", 
                 $time, rst, en, orig_data, wire_nrzi, recovered_data);
    end

    // Task: Serialize LSB first
    task send_byte_lsb(input logic [7:0] data_byte);
        for (int i = 0; i < 8; i++) begin
            orig_data = data_byte[i];
            @(posedge clk);
        end
    endtask

    // Stimulus
    initial begin
        clk = 0; rst = 1; en = 0; orig_data = 1;
        #35 rst = 0;
        @(posedge clk);
        
        en = 1;
        
        $display("Sending SDLC Flag (0x7E)...");
        send_byte_lsb(8'h7E); 

        $display("Sending Random Payload (0xC3)...");
        send_byte_lsb(8'hC3); // 1100 0011
        
        $display("Sending SDLC Flag (0x7E)...");
        send_byte_lsb(8'h7E);
        
        @(posedge clk);
        
        en = 0;
        #40;
        
        $display("NRZI Loopback Simulation Finished!");
        $finish;
    end

endmodule