`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Deinterlacer_bob with proper handshaking
//////////////////////////////////////////////////////////////////////////////////

module tb_Deinterlacer_bob();

    parameter PIXEL_WIDTH = 24;
    parameter MAX_WIDTH = 1920;
    parameter CLK_PERIOD = 10;

    parameter TEST_H_ACTIVE = 12'd64;
    parameter TEST_V_ACTIVE = 12'd240;

    reg clk;
    reg rst_n;

    // VPU Input signals
    reg                   VPU_in_valid;
    wire                  VPU_in_ready;  // Now a wire from DUT
    reg [PIXEL_WIDTH-1:0] VPU_in_pixel;
    reg                   VPU_in_line_start;
    reg                   VPU_in_frame_start;
    reg                   VPU_in_interlaced;
    reg                   VPU_in_field_id;
    reg [11:0]            VPU_in_h_active;
    reg [11:0]            VPU_in_v_active;

    // VPU Output signals
    wire                   VPU_out_valid;
    reg                    VPU_out_ready;  // Testbench controls this
    wire [PIXEL_WIDTH-1:0] VPU_out_pixel;
    wire                   VPU_out_line_start;
    wire                   VPU_out_frame_start;
    wire                   VPU_out_interlaced;
    wire                   VPU_out_field_id;
    wire [11:0]            VPU_out_h_active;
    wire [11:0]            VPU_out_v_active;

    // Test tracking
    integer pixel_count;
    integer line_count;
    integer errors;

    // Instantiate DUT
    Deinterlacer_bob #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .MAX_WIDTH(MAX_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_line_width(12'd1920),
        .cfg_bypass(1'b0),
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

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Output monitoring
    always @(posedge clk) begin
        if (VPU_out_valid && VPU_out_ready) begin
            pixel_count = pixel_count + 1;
        end

        if (VPU_out_line_start && VPU_out_valid && VPU_out_ready) begin
            line_count = line_count + 1;
            $display("[%0t] Output Line %0d started", $time, line_count);
        end

        if (VPU_out_frame_start && VPU_out_valid && VPU_out_ready) begin
            $display("[%0t] ===== OUTPUT FRAME START =====", $time);
        end
    end

    // Task: Reset
    task reset_dut;
        begin
            rst_n = 0;
            VPU_in_valid = 0;
            VPU_in_pixel = 0;
            VPU_in_line_start = 0;
            VPU_in_frame_start = 0;
            VPU_in_interlaced = 0;
            VPU_in_field_id = 0;
            VPU_in_h_active = 0;
            VPU_in_v_active = 0;
            VPU_out_ready = 1;  // Always ready to accept output
            pixel_count = 0;
            line_count = 0;
            errors = 0;
            repeat(5) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // Task: Send one line with handshaking
    task send_line;
        input [11:0] line_num;
        input [11:0] h_active;
        input integer line_start_flag;
        input integer frame_start_flag;
        integer i;
        begin
            // Send first pixel with line_start
            VPU_in_line_start = line_start_flag;
            VPU_in_frame_start = frame_start_flag;
            VPU_in_valid = 1;
            VPU_in_pixel = {line_num[7:0], 16'd0};

            // Wait for handshake
            @(posedge clk);
            while (!VPU_in_ready) @(posedge clk);

            // Send remaining pixels
            for (i = 1; i < h_active; i = i + 1) begin
                VPU_in_line_start = 0;
                VPU_in_frame_start = 0;
                VPU_in_valid = 1;
                VPU_in_pixel = {line_num[7:0], i[15:0]};

                @(posedge clk);
                while (!VPU_in_ready) @(posedge clk);
            end

            // End of line
            VPU_in_valid = 0;
            VPU_in_line_start = 0;
            VPU_in_frame_start = 0;

            // Wait for second pass to complete
            repeat(h_active + 10) @(posedge clk);
        end
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Deinterlacer Bob Testbench (Handshaking)");
        $display("========================================");

        reset_dut();

        //---------------------------------------------------------------------
        // Test 1: Progressive Passthrough
        //---------------------------------------------------------------------
        $display("\n[TEST 1] Progressive Video Passthrough");

        VPU_in_interlaced = 0;
        VPU_in_field_id = 0;
        VPU_in_h_active = TEST_H_ACTIVE;
        VPU_in_v_active = TEST_V_ACTIVE * 2;

        pixel_count = 0;
        line_count = 0;

        send_line(0, TEST_H_ACTIVE, 1, 1);
        send_line(1, TEST_H_ACTIVE, 1, 0);
        send_line(2, TEST_H_ACTIVE, 1, 0);
        send_line(3, TEST_H_ACTIVE, 1, 0);

        repeat(20) @(posedge clk);

        if (line_count !== 4) begin
            $display("ERROR: Expected 4 lines, got %0d", line_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Progressive passthrough (4 lines)");
        end

        //---------------------------------------------------------------------
        // Test 2: Interlaced Bob Deinterlacing
        //---------------------------------------------------------------------
        $display("\n[TEST 2] Interlaced Bob Deinterlacing");

        reset_dut();

        VPU_in_interlaced = 1;
        VPU_in_field_id = 0;
        VPU_in_h_active = TEST_H_ACTIVE;
        VPU_in_v_active = TEST_V_ACTIVE;

        pixel_count = 0;
        line_count = 0;

        send_line(0, TEST_H_ACTIVE, 1, 1);
        send_line(1, TEST_H_ACTIVE, 1, 0);
        send_line(2, TEST_H_ACTIVE, 1, 0);
        send_line(3, TEST_H_ACTIVE, 1, 0);

        repeat(50) @(posedge clk);

        if (line_count !== 8) begin
            $display("ERROR: Expected 8 lines (4 doubled), got %0d", line_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Line doubling correct (4 -> 8 lines)");
        end

        if (pixel_count !== TEST_H_ACTIVE * 8) begin
            $display("ERROR: Expected %0d pixels, got %0d", TEST_H_ACTIVE * 8, pixel_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Pixel count correct (%0d)", pixel_count);
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n========================================");
        if (errors == 0)
            $display("   ALL TESTS PASSED!");
        else
            $display("   FAILED: %0d errors", errors);
        $display("========================================\n");

        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule