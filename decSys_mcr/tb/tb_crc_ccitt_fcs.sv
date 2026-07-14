// tb/tb_crc_ccitt_fcs.sv
`timescale 1ns / 1ps

module tb_crc_ccitt_fcs;

    // Signals
    logic        clk;
    logic        rst;
    logic        en;
    logic        data_bit;
    logic [15:0] crc_out;
    logic        crc_valid;

    // Instantiate DUT
    crc_ccitt_fcs dut (
        .clk       (clk),
        .rst       (rst),
        .en    (en),
        .data_bit  (data_bit),
        .crc_out   (crc_out),
        .crc_valid (crc_valid)
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
        $dumpvars(0, tb_crc_ccitt_fcs);
    end

    // Terminal Monitor
    initial begin
        $monitor("Time: %4t ns | rst: %b | en: %b | data_bit: %b | crc_out: %04X | crc_valid: %b", 
                 $time, rst, en, data_bit, crc_out, crc_valid);
    end

    // Standard SDLC LSB-First serialization task driven safely on negedge
    task send_byte_lsb(input logic [7:0] data_byte);
        for (int i = 0; i < 8; i++) begin
            @(negedge clk);
            data_bit = data_byte[i]; // Bit 0 goes first
            en   = 1;
        end
        @(negedge clk);
        en = 0;
    endtask

    logic [15:0] captured_tx_crc;

    // Test Sequence
    initial begin
        // Initialize everything cleanly on step 0
        clk = 0; rst = 1; en = 0; data_bit = 1;
        
        // Fully synchronous reset release
        repeat (2) @(negedge clk);
        rst = 0;
        @(negedge clk);
        
        $display("--- TX MODE: Generating CRC for Payload 0xFFE0 ---");
        
        // In SDLC, the transmission order is usually lower byte first or sequential buffer order.
        // Let's send 0xE0 then 0xFF (or 0xFF then 0xE0 LSB-first depending on your frame spec).
        // Sending 0xE0 then 0xFF LSB-first:
        send_byte_lsb(8'hFF);
        send_byte_lsb(8'hE0);
        
        @(negedge clk);
        captured_tx_crc = crc_out;
        $display("Payload Sent. Calculated Inverted CRC (FCS): 0x%04X", captured_tx_crc);

        #40;

        $display("--- RX MODE: Verifying the Magic Residue ---");
        
        // Synchronous reset for RX tracking
        rst = 1; 
        @(negedge clk);
        rst = 0;
        @(negedge clk);
        
        // Feed the exact same payload bytes LSB-first
        send_byte_lsb(8'hFF);
        send_byte_lsb(8'hE0);
        
        // Feed the calculated FCS bits. 
        // The LSB of the FCS must hit the engine first!
        send_byte_lsb(captured_tx_crc[7:0]);
        send_byte_lsb(captured_tx_crc[15:8]);
        
        @(negedge clk);

        if (crc_valid)
            $display("SUCCESS! Magic Residue (0xF0B8) detected. RX CRC is Valid.");
        else
            $display("FAILURE! Engine did not reach 0xF0B8. Ended at: 0x%04X", dut.crc_reg);

        #40;
        $display("CRC Simulation Finished!");
        $finish;
    end

endmodule