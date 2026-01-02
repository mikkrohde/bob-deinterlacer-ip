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
    reg                   VPU_in_valid;
    wire                  VPU_in_ready;  // Now from DUT
    reg [PIXEL_WIDTH-1:0] VPU_in_pixel;
    reg                   VPU_in_line_start;
    reg                   VPU_in_frame_start;
    reg                   VPU_in_interlaced;
    reg                   VPU_in_field_id;
    reg [11:0]            VPU_in_h_active;
    reg [11:0]            VPU_in_v_active;

    // VPU Output
    wire                   VPU_out_valid;
    reg                    VPU_out_ready;  // Testbench controls this
    wire [PIXEL_WIDTH-1:0] VPU_out_pixel;
    wire                   VPU_out_line_start;
    wire                   VPU_out_frame_start;
    wire                   VPU_out_interlaced;
    wire                   VPU_out_field_id;
    wire [11:0]            VPU_out_h_active;
    wire [11:0]            VPU_out_v_active;

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
        .VPU_in_valid(VPU_in_valid),
        .VPU_in_ready(VPU_in_ready),
        .VPU_in_pixel(VPU_in_pixel),
        .VPU_in_line_start(VPU_in_line_start),
        .VPU_in_frame_start(VPU_in_frame_start),
        .VPU_in_interlaced(VPU_in_interlaced),
        .VPU_in_field_id(VPU_in_field_id),
        .VPU_in_h_active(VPU_in_h_active),
        .VPU_in_v_active(VPU_in_v_active),
        .VPU_out_valid(VPU_out_valid),
        .VPU_out_ready(VPU_out_ready),
        .VPU_out_pixel(VPU_out_pixel),
        .VPU_out_line_start(VPU_out_line_start),
        .VPU_out_frame_start(VPU_out_frame_start),
        .VPU_out_interlaced(VPU_out_interlaced),
        .VPU_out_field_id(VPU_out_field_id),
        .VPU_out_h_active(VPU_out_h_active),
        .VPU_out_v_active(VPU_out_v_active)
    );

    // Clock
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Handshake signals for monitoring
    wire handshake_in  = VPU_in_valid && VPU_in_ready;
    wire handshake_out = VPU_out_valid && VPU_out_ready;

    // Monitor output and count
    always @(posedge clk) begin
        if (handshake_out) begin
            output_pixel_count = output_pixel_count + 1;
            $display("[%0t] OUTPUT: pixel=0x%06h (pixel #%0d)", 
                     $time, VPU_out_pixel, output_pixel_count);
        end

        if (VPU_out_line_start && handshake_out) begin
            output_line_count = output_line_count + 1;
            //$display("[%0t] OUTPUT: *** LINE START *** (line #%0d)", $time, output_line_count);
        end

       // if (VPU_out_frame_start && handshake_out)
            //$display("[%0t] OUTPUT: *** FRAME START ***", $time);
    end

    // Monitor internal state
    always @(posedge clk) begin
        $display("[%0t] STATE=%0d, line_addr=%0d, line_length=%0d, in_valid=%b, in_ready=%b, out_valid=%b, out_ready=%b",
                 $time, dut.state, dut.line_addr, dut.line_length, 
                 VPU_in_valid, VPU_in_ready, VPU_out_valid, VPU_out_ready);
    end

    // Test
    integer i;
    initial begin
        $display("=== Simple Debug Test: Send 1 line, expect 2 output lines ===\n");

        // Reset
        rst_n = 0;
        VPU_in_valid = 0;
        VPU_in_pixel = 0;
        VPU_in_line_start = 0;
        VPU_in_frame_start = 0;
        VPU_in_interlaced = 1;  // INTERLACED MODE
        VPU_in_field_id = 0;
        VPU_in_h_active = 12'd8;   // Just 8 pixels
        VPU_in_v_active = 12'd240;
        VPU_out_ready = 1;  // Always ready to accept output
        output_pixel_count = 0;
        output_line_count = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        $display("\n--- Sending first pixel with line_start + frame_start ---");
        
        // First pixel with line_start and frame_start
        @(posedge clk);
        VPU_in_line_start = 1;
        VPU_in_frame_start = 1;
        VPU_in_valid = 1;
        VPU_in_pixel = 24'hAA0000;
        
        // Wait for handshake
        @(posedge clk);
        while (!VPU_in_ready) @(posedge clk);
        
        $display("\n--- Sending remaining 7 pixels ---");
        
        // Send remaining 7 pixels (total 8)
        for (i = 1; i < 8; i = i + 1) begin
            VPU_in_line_start = 0;
            VPU_in_frame_start = 0;
            VPU_in_valid = 1;
            VPU_in_pixel = 24'hAA0000 + i;
            
            @(posedge clk);
            while (!VPU_in_ready) @(posedge clk);
        end

        // End input
        
        VPU_in_valid = 0;
        VPU_in_line_start = 0;
        VPU_in_frame_start = 0;
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