`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Simple debug testbench - just send ONE line and verify it's doubled
//////////////////////////////////////////////////////////////////////////////////

module tb_Deinterlacer_debug();

    parameter PIXEL_WIDTH = 24;
    parameter MAX_WIDTH = 1920;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst_n;

    // VPU Input
    reg                   vpu_in_valid;
    wire                  vpu_in_ready;  // Now from DUT
    reg [PIXEL_WIDTH-1:0] vpu_in_pixel;
    reg                   vpu_in_line_start;
    reg                   vpu_in_frame_start;
    reg                   vpu_in_interlaced;
    reg                   vpu_in_field_id;
    reg [11:0]            vpu_in_h_active;
    reg [11:0]            vpu_in_v_active;

    // VPU Output
    wire                   vpu_out_valid;
    reg                    vpu_out_ready;  // Testbench controls this
    wire [PIXEL_WIDTH-1:0] vpu_out_pixel;
    wire                   vpu_out_line_start;
    wire                   vpu_out_frame_start;
    wire                   vpu_out_interlaced;
    wire                   vpu_out_field_id;
    wire [11:0]            vpu_out_h_active;
    wire [11:0]            vpu_out_v_active;

    // Test counters
    integer output_pixel_count;
    integer output_line_count;

    // DUT
    Deinterlacer_bob #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .MAX_WIDTH(MAX_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .vpu_in_valid(vpu_in_valid),
        .vpu_in_ready(vpu_in_ready),
        .vpu_in_pixel(vpu_in_pixel),
        .vpu_in_line_start(vpu_in_line_start),
        .vpu_in_frame_start(vpu_in_frame_start),
        .vpu_in_interlaced(vpu_in_interlaced),
        .vpu_in_field_id(vpu_in_field_id),
        .vpu_in_h_active(vpu_in_h_active),
        .vpu_in_v_active(vpu_in_v_active),
        .vpu_out_valid(vpu_out_valid),
        .vpu_out_ready(vpu_out_ready),
        .vpu_out_pixel(vpu_out_pixel),
        .vpu_out_line_start(vpu_out_line_start),
        .vpu_out_frame_start(vpu_out_frame_start),
        .vpu_out_interlaced(vpu_out_interlaced),
        .vpu_out_field_id(vpu_out_field_id),
        .vpu_out_h_active(vpu_out_h_active),
        .vpu_out_v_active(vpu_out_v_active)
    );

    // Clock
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Handshake signals for monitoring
    wire handshake_in  = vpu_in_valid && vpu_in_ready;
    wire handshake_out = vpu_out_valid && vpu_out_ready;

    // Monitor output and count
    always @(posedge clk) begin
        if (handshake_out) begin
            output_pixel_count = output_pixel_count + 1;
            $display("[%0t] OUTPUT: pixel=0x%06h (pixel #%0d)", 
                     $time, vpu_out_pixel, output_pixel_count);
        end

        if (vpu_out_line_start && handshake_out) begin
            output_line_count = output_line_count + 1;
            //$display("[%0t] OUTPUT: *** LINE START *** (line #%0d)", $time, output_line_count);
        end

       // if (vpu_out_frame_start && handshake_out)
            //$display("[%0t] OUTPUT: *** FRAME START ***", $time);
    end

    // Monitor internal state
    always @(posedge clk) begin
        $display("[%0t] STATE=%0d, line_addr=%0d, line_length=%0d, in_valid=%b, in_ready=%b, out_valid=%b, out_ready=%b",
                 $time, dut.state, dut.line_addr, dut.line_length, 
                 vpu_in_valid, vpu_in_ready, vpu_out_valid, vpu_out_ready);
    end

    // Test
    integer i;
    initial begin
        $display("=== Simple Debug Test: Send 1 line, expect 2 output lines ===\n");

        // Reset
        rst_n = 0;
        vpu_in_valid = 0;
        vpu_in_pixel = 0;
        vpu_in_line_start = 0;
        vpu_in_frame_start = 0;
        vpu_in_interlaced = 1;  // INTERLACED MODE
        vpu_in_field_id = 0;
        vpu_in_h_active = 12'd8;   // Just 8 pixels
        vpu_in_v_active = 12'd240;
        vpu_out_ready = 1;  // Always ready to accept output
        output_pixel_count = 0;
        output_line_count = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        $display("\n--- Sending first pixel with line_start + frame_start ---");
        
        // First pixel with line_start and frame_start
        @(posedge clk);
        vpu_in_line_start = 1;
        vpu_in_frame_start = 1;
        vpu_in_valid = 1;
        vpu_in_pixel = 24'hAA0000;
        
        // Wait for handshake
        @(posedge clk);
        while (!vpu_in_ready) @(posedge clk);
        
        $display("\n--- Sending remaining 7 pixels ---");
        
        // Send remaining 7 pixels (total 8)
        for (i = 1; i < 8; i = i + 1) begin
            vpu_in_line_start = 0;
            vpu_in_frame_start = 0;
            vpu_in_valid = 1;
            vpu_in_pixel = 24'hAA0000 + i;
            
            @(posedge clk);
            while (!vpu_in_ready) @(posedge clk);
        end

        // End input
        
        vpu_in_valid = 0;
        vpu_in_line_start = 0;
        vpu_in_frame_start = 0;
        @(posedge clk);

        $display("\n--- Waiting for SECOND_PASS to complete ---");
        repeat(50) @(posedge clk);

        // Verify results
        $display("\n=== Test Results ===");
        $display("Output pixels: %0d (expected 16)", output_pixel_count);
        $display("Output lines:  %0d (expected 2)", output_line_count);
        
        if (output_pixel_count == 16 && output_line_count == 2)
            $display("PASS: Line doubling works correctly!");
        else
            $display("FAIL: Line doubling incorrect!");

        $display("\n=== Test Complete ===");
        $finish;
    end

    initial begin
        #50000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule