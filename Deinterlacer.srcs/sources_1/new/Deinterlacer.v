`timescale 1ns / 1ps

module Deinterlacer_bob #(
    parameter PIXEL_WIDTH = 24,
    parameter MAX_WIDTH = 1920
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // VPU Input Stream
    input  wire                     vpu_in_valid,
    output wire                     vpu_in_ready,
    input  wire [PIXEL_WIDTH-1:0]   vpu_in_pixel,
    input  wire                     vpu_in_line_start,
    input  wire                     vpu_in_frame_start,
    input  wire                     vpu_in_interlaced,
    input  wire                     vpu_in_field_id,
    input  wire [11:0]              vpu_in_h_active,
    input  wire [11:0]              vpu_in_v_active,

    // VPU Output Stream
    output reg                      vpu_out_valid,
    input  wire                     vpu_out_ready,
    output reg [PIXEL_WIDTH-1:0]    vpu_out_pixel,
    output reg                      vpu_out_line_start,
    output reg                      vpu_out_frame_start,
    output reg                      vpu_out_interlaced,
    output reg                      vpu_out_field_id,
    output reg [11:0]               vpu_out_h_active,
    output reg [11:0]               vpu_out_v_active
);

    // Line buffer
    reg [PIXEL_WIDTH-1:0] line_ram [0:MAX_WIDTH-1];
    reg [$clog2(MAX_WIDTH)-1:0] line_addr;
    reg [$clog2(MAX_WIDTH)-1:0] line_length;  // Store length during first pass

    // State machine
    localparam IDLE         = 2'b00;
    localparam FIRST_PASS   = 2'b01;  // Store to buffer AND output
    localparam SECOND_PASS  = 2'b10;  // Replay from buffer

    reg [1:0] state;
    
    // Latched signals for second pass
    reg latched_frame_start;
    reg latched_line_start;
    reg [PIXEL_WIDTH-1:0] latched_pixel;

    // Handshake signals
    wire handshake_in  = vpu_in_valid && vpu_in_ready;
    wire handshake_out = vpu_out_valid && vpu_out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= IDLE;
            vpu_out_valid       <= 1'b0;
            vpu_out_pixel       <= 0;
            vpu_out_line_start  <= 1'b0;
            vpu_out_frame_start <= 1'b0;
            vpu_out_interlaced  <= 1'b0;
            vpu_out_field_id    <= 1'b0;
            vpu_out_h_active    <= 0;
            vpu_out_v_active    <= 0;
            line_addr           <= 0;
            line_length         <= 0;
            latched_frame_start <= 1'b0;
            latched_line_start  <= 1'b0;
        end else begin
        
            // Progressive passthrough (no deinterlacing needed)
            if (!vpu_in_interlaced) begin
                vpu_out_valid       <= vpu_in_valid;
                vpu_out_pixel       <= vpu_in_pixel;
                vpu_out_line_start  <= vpu_in_line_start;
                vpu_out_frame_start <= vpu_in_frame_start;
                vpu_out_interlaced  <= 1'b0;
                vpu_out_field_id    <= 1'b0;
                vpu_out_h_active    <= vpu_in_h_active;
                vpu_out_v_active    <= vpu_in_v_active;
                state               <= IDLE;
                
            end else begin
                // Interlaced mode - bob deinterlacing
                vpu_out_interlaced <= 1'b0;
                vpu_out_field_id   <= 1'b0;
                vpu_out_h_active   <= vpu_in_h_active;
                vpu_out_v_active   <= vpu_in_v_active << 1; // Double vertical resolution

                case (state)
                    IDLE: begin
                        vpu_out_valid <= 1'b0;
                        line_addr <= 0;
                        
                        // Wait for line_start to begin
                        if (vpu_in_valid && vpu_in_line_start) begin
                            state <= FIRST_PASS;
                            latched_frame_start <= vpu_in_frame_start && !vpu_in_field_id;
                            latched_line_start  <= 1'b1;
                            
                            line_ram[0] <= vpu_in_pixel;
                            latched_pixel <= vpu_in_pixel;
                            line_addr <= 1;
                        end
                    end

                    FIRST_PASS: begin
                        if (!vpu_out_valid || handshake_out) begin
                            if (latched_line_start) begin
                                vpu_out_valid       <= 1'b1;
                                vpu_out_pixel       <= latched_pixel;
                                vpu_out_line_start  <= 1'b1;
                                vpu_out_frame_start <= latched_frame_start;
                                latched_line_start  <= 1'b0;
                                latched_frame_start <= 1'b0;

                            end else if (!vpu_in_valid && line_addr > 0) begin
                                // Input stopped - line complete, switch to replay
                                vpu_out_valid <= 1'b0;
                                line_length   <= line_addr;
                                line_addr     <= 0;
                                state         <= SECOND_PASS;

                            end else if (handshake_in) begin
                                // Store pixel to buffer AND output it
                                line_ram[line_addr] <= vpu_in_pixel;
                                line_addr           <= line_addr + 1;

                                vpu_out_valid       <= 1'b1;
                                vpu_out_pixel       <= vpu_in_pixel;
                                vpu_out_line_start  <= latched_line_start;
                                vpu_out_frame_start <= latched_frame_start;
                                
                                latched_line_start  <= 1'b0;
                                latched_frame_start <= 1'b0;
                            end else begin
                                vpu_out_valid <= 1'b0;
                            end
                        end
                    end

                    SECOND_PASS: begin
                        if (!vpu_out_valid || handshake_out) begin
                            if (line_addr < line_length) begin
                                vpu_out_valid       <= 1'b1;
                                vpu_out_pixel       <= line_ram[line_addr];
                                vpu_out_line_start  <= (line_addr == 0);
                                vpu_out_frame_start <= 1'b0;
                                line_addr           <= line_addr + 1;
                            end else begin
                                // Replay complete
                                vpu_out_valid <= 1'b0;
                                line_addr     <= 0;
                                state         <= IDLE;
                            end
                        end
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

    // Ready signal logic
    assign vpu_in_ready = vpu_in_interlaced ? 
                            (state == FIRST_PASS) && (!vpu_out_valid || handshake_out) && !latched_line_start : 
                            (!vpu_out_valid || handshake_out);

endmodule