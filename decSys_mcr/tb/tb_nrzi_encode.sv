// tb/tb_nrzi_encode.sv
`timescale 1ns / 1ps

module tb_nrzi_encode;

    // Signals
    logic clk;
    logic rst;
    logic en;
    logic d_in;
    logic nrzi_out;

    // Instantiate DUT
    nrzi_encode dut (
        .clk      (clk),
        .rst      (rst),
        .en       (en),
        .d_in     (d_in),
        .nrzi_out (nrzi_out)
    );

    // Clock generation (50MHz)
    always #10 clk = ~clk;

    // Waveform Dumping
    string vcd_filename;
    initial begin
        if ($value$plusargs("vcdfile=%s", vcd_filename)) begin
            $dumpfile(vcd_filename);
        end else begin
            $dumpfile("dump.vcd");
        end
        $dumpvars(0, tb_nrzi_encode);
    end

    // Terminal Monitor
    initial begin
        $monitor("Time: %4t ns | rst: %b | en: %b | d_in: %b | nrzi_out: %b", 
                 $time, rst, en, d_in, nrzi_out);
    end

    // Task: Serialize and send a byte LSB first (for Data/Flags)
    task send_byte_lsb(input logic [7:0] data_byte);
        for (int i = 0; i < 8; i++) begin
            d_in = data_byte[i]; // Starts at bit 0, goes up to bit 7
            @(posedge clk);
        end
    endtask

    // Task: Serialize and send a byte MSB first (for FCS / CRC)
    task send_byte_msb(input logic [7:0] data_byte);
        for (int i = 7; i >= 0; i--) begin
            d_in = data_byte[i]; // Starts at bit 7, goes down to bit 0
            @(posedge clk);
        end
    endtask

    // Test Sequence
    initial begin
        // Initialize
        clk = 0; rst = 1; en = 0; d_in = 1;
        #35 rst = 0;
        @(posedge clk);
        
        en = 1;
        
        $display("Sending SDLC Flag (0x7E)...");
        send_byte_lsb(8'h7E); 

        $display("Sending Payload Data (0xA5)...");
        send_byte_lsb(8'hA5); 
        
        // SAMPLE CRC
        $display("Sending FCS (0x1234)...");
        send_byte_msb(8'h12); // Send upper byte of FCS MSB first
        send_byte_msb(8'h34); // Send lower byte of FCS MSB first
        
        $display("Sending Closing Flag (0x7E)...");
        send_byte_lsb(8'h7E);
        
        en = 0;
        #40;
        
        $display("NRZI Encode Simulation Finished!");
        $finish;
    end

endmodule