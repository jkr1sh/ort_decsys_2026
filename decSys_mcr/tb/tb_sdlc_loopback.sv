// tb/tb_sdlc_loopback.sv
`timescale 1ns / 1ps

module tb_sdlc_loopback;

    // System Signals
    logic clk;
    logic rst;

    // TX Framer Interfaces
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_last;
    logic       tx_ready;
    logic       tx_en_out;
    logic       tx_d_out;

    // The Physical Medium
    logic       nrzi_wire;

    // RX Framer Interfaces
    logic       rx_d_raw;
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_end_of_frame;
    logic       rx_crc_error;
    logic       rx_abort;

    // Clock Recovery Simulation Pipeline
    logic [2:0] en_pipe;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) en_pipe <= 0;
        else     en_pipe <= {en_pipe[1:0], tx_en_out};
    end
    
    wire decode_en = en_pipe[0]; 
    wire framer_en = en_pipe[1]; 

    // --- Instantiations ---
    sdlc_tx_framer tx_framer_inst (
        .clk(clk), .rst(rst),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .tx_en_out(tx_en_out), .tx_d_out(tx_d_out)
    );

    nrzi_encode tx_phy_inst (
        .clk(clk), .rst(rst),
        .en(tx_en_out), .d_in(tx_d_out),
        .nrzi_out(nrzi_wire)
    );

    nrzi_decode rx_phy_inst (
        .clk(clk), .rst(rst),
        .en(decode_en), .nrzi_in(nrzi_wire),
        .d_out(rx_d_raw)
    );

    sdlc_rx_framer rx_framer_inst (
        .clk(clk), .rst(rst),
        .rx_en_in(framer_en), .rx_d_in(rx_d_raw),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_end_of_frame(rx_end_of_frame),
        .rx_crc_error(rx_crc_error), .rx_abort(rx_abort)
    );

    // --- Clock and VCD Setup ---
    always #10 clk = ~clk;

    string vcd_filename;
    initial begin
        if ($value$plusargs("vcdfile=%s", vcd_filename)) begin
            $dumpfile(vcd_filename);
        end else begin
            $dumpfile("dump.vcd");
        end
        $dumpvars(0, tb_sdlc_loopback);
    end

    // --- Test Stimulus ---
    logic [7:0] test_payload [0:5];

    task send_frame(input int len);
        $display("\n[%8t ns] CPU: Injecting %0d bytes into TX...", $time, len);
        for (int i = 0; i < len; i++) begin
            @(negedge clk);
            tx_data  = test_payload[i];
            tx_valid = 1;
            tx_last  = (i == len - 1);
            
            do begin
                @(negedge clk);
            end while (tx_ready == 0);
        end
        tx_valid = 0;
        tx_last  = 0;
    endtask

    // --- RX Monitoring Thread ---
    initial begin
        forever begin
            @(posedge clk);
            if (rx_valid) begin
                $display("[%8t ns] MAC: RX Framer extracted byte: 0x%02X", $time, rx_data);
            end
            if (rx_end_of_frame) begin
                if (rx_crc_error) 
                    $display("[%8t ns] MAC: Frame complete! [CRC FAILED]", $time);
                else 
                    $display("[%8t ns] MAC: Frame complete! [CRC PASSED]", $time);
            end
        end
    end

    // --- Main Sequence ---
    initial begin
        clk = 0; rst = 1; 
        tx_data = 0; tx_valid = 0; tx_last = 0;
        
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);
        
        test_payload[0] = 8'hFF;
        test_payload[1] = 8'hE0;
        
        send_frame(2);
        
        repeat (150) @(negedge clk);
        $display("\n[%8t ns] Loopback Simulation Complete.", $time);
        $finish;
    end
endmodule