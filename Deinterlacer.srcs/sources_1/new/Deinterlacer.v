`timescale 1ns / 1ps

module Deinterlacer_bob #(
    parameter PIXEL_WIDTH = 24,
    parameter MAX_WIDTH = 1920
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [11:0]              cfg_line_width,  // Runtime configurable buffer depth
    input  wire                     cfg_bypass,

    // VPU Input Stream
    input  wire                     VPU_in_valid,
    output wire                     VPU_in_ready,
    input  wire [PIXEL_WIDTH-1:0]   VPU_in_pixel,
    input  wire                     VPU_in_line_start,
    input  wire                     VPU_in_frame_start,
    input  wire                     VPU_in_interlaced,
    input  wire                     VPU_in_field_id,
    input  wire [11:0]              VPU_in_h_active,
    input  wire [11:0]              VPU_in_v_active,

    // VPU Output Stream
    output reg                      VPU_out_valid,
    input  wire                     VPU_out_ready,
    output reg [PIXEL_WIDTH-1:0]    VPU_out_pixel,
    output reg                      VPU_out_line_start,
    output reg                      VPU_out_frame_start,
    output reg                      VPU_out_interlaced,
    output reg                      VPU_out_field_id,
    output reg [11:0]               VPU_out_h_active,
    output reg [11:0]               VPU_out_v_active
);

    // Line buffer
    //(* ram_style = "block" *)
    reg [PIXEL_WIDTH-1:0] line_ram [0:MAX_WIDTH-1];
    
    // RAM read/write signals
    reg [$clog2(MAX_WIDTH)-1:0]  ram_wr_addr;
    reg [PIXEL_WIDTH-1:0]        ram_wr_data;
    reg                          ram_wr_en;
    reg [$clog2(MAX_WIDTH)-1:0]  ram_rd_addr;
    reg [PIXEL_WIDTH-1:0]        ram_rd_data;

    reg [$clog2(MAX_WIDTH)-1:0] line_length;  // Store length during first pass

    // State machine
    localparam IDLE         = 3'b00;
    localparam FIRST_PASS   = 3'b01;  // Store to buffer AND output
    localparam SECOND_PASS  = 3'b10;  // Replay from buffer

    reg [1:0] state;
    
    // Latched signals for second pass
    reg latched_frame_start;
    reg latched_line_start;
    reg [PIXEL_WIDTH-1:0] latched_pixel;

    // Handshake signals
    wire handshake_in  = VPU_in_valid && VPU_in_ready;
    wire handshake_out = VPU_out_valid && VPU_out_ready;
    wire passthrough = cfg_bypass || !VPU_in_interlaced;
    wire frame_start = VPU_in_frame_start && !VPU_in_field_id;
    
    always @(posedge clk) begin
        // Synchronous write
        if (ram_wr_en) begin
            line_ram[ram_wr_addr] <= ram_wr_data;
        end
        
        // Synchronous read (data available NEXT cycle)
        ram_rd_data <= line_ram[ram_rd_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= IDLE;
            VPU_out_valid       <= 1'b0;
            VPU_out_pixel       <= 0;
            VPU_out_line_start  <= 1'b0;
            VPU_out_frame_start <= 1'b0;
            VPU_out_interlaced  <= 1'b0;
            VPU_out_field_id    <= 1'b0;
            VPU_out_h_active    <= 0;
            VPU_out_v_active    <= 0;
            ram_rd_addr         <= 0;
            ram_wr_addr         <= 0;
            ram_wr_data         <= 0;
            ram_wr_en           <= 1'b0;
            line_length         <= 0;
            latched_frame_start <= 1'b0;
            latched_line_start  <= 1'b0;
        end else begin
        
            // Progressive passthrough (no deinterlacing needed)
            if (passthrough) begin
                if (VPU_in_valid && VPU_in_ready) begin
                    VPU_out_valid       <= VPU_in_valid;
                    VPU_out_pixel       <= VPU_in_pixel;
                    VPU_out_line_start  <= VPU_in_line_start;
                    VPU_out_frame_start <= VPU_in_frame_start;
                    VPU_out_interlaced  <= cfg_bypass ? VPU_in_interlaced : 1'b0;
                    VPU_out_field_id    <= cfg_bypass ? VPU_in_field_id : 1'b0;
                    VPU_out_h_active    <= VPU_in_h_active;
                    VPU_out_v_active    <= VPU_in_v_active;
                end
                state     <= IDLE;
                ram_rd_addr <= 0;
                ram_wr_addr <= 0;
            end else begin
                // Interlaced mode - bob deinterlacing
                VPU_out_interlaced <= 1'b0;
                VPU_out_field_id   <= 1'b0;
                VPU_out_h_active   <= VPU_in_h_active;
                VPU_out_v_active   <= VPU_in_v_active << 1; // Double vertical resolution

                case (state)
                    IDLE: begin
                        ram_rd_addr     <= 0;
                        ram_wr_addr     <= 0;

                        // Wait for line_start to begin
                        if (VPU_in_valid && VPU_in_line_start) begin
                            state <= FIRST_PASS;
                            latched_frame_start <= frame_start;
                            latched_line_start  <= 1'b1;
                            
                            ram_wr_en   <= 1'b1;
                            ram_wr_addr <= 0;
                            ram_wr_data <= VPU_in_pixel;
                            latched_pixel <= VPU_in_pixel;
                        end else begin
                            ram_wr_en   <= 1'b0;
                        end
                    end

                    FIRST_PASS: begin
                        if (!VPU_out_valid || handshake_out) begin
                            if (latched_line_start) begin
                                VPU_out_valid       <= 1'b1;
                                VPU_out_pixel       <= latched_pixel;
                                VPU_out_line_start  <= 1'b1;
                                VPU_out_frame_start <= latched_frame_start;
                                latched_line_start  <= 1'b0;
                                latched_frame_start <= 1'b0;
                            end else
                            if (!VPU_in_valid && ram_wr_addr > 0) begin
                                VPU_out_valid      <= 1'b0;
                                line_length        <= ram_wr_addr;
                                ram_rd_addr        <= 0;
                                ram_wr_addr        <= 0;
                                latched_line_start <= 1'b0; // Signal to output line_start on first pixel
                                state              <= SECOND_PASS;

                            end else if (VPU_in_valid) begin
                                // Store pixel to buffer AND output it
                                if (ram_wr_addr < cfg_line_width) begin
                                    ram_wr_en   <= 1'b1;
                                    ram_wr_data <= VPU_in_pixel;
                                    ram_wr_addr <= ram_wr_addr + 1;
                                end else begin
                                    ram_wr_en   <= 1'b0;
                                end

                                VPU_out_valid       <= 1'b1;
                                VPU_out_pixel       <= VPU_in_pixel;
                                VPU_out_line_start  <= latched_line_start;
                                VPU_out_frame_start <= latched_frame_start;
                                
                                latched_line_start  <= 1'b0;
                                latched_frame_start <= 1'b0;
                            end else begin
                                VPU_out_valid <= 1'b0;
                                ram_wr_en     <= 1'b0;
                            end
                        end
                    end

                    SECOND_PASS: begin
                        if (!VPU_out_valid || handshake_out) begin
                            if (ram_rd_addr < line_length) begin
                                VPU_out_valid       <= 1'b1;
                                VPU_out_pixel       <= ram_rd_data;
                                VPU_out_line_start  <= (ram_rd_addr == 0);
                                VPU_out_frame_start <= 1'b0;
                                ram_rd_addr         <= ram_rd_addr + 1;
                            end else begin
                                // Replay complete
                                VPU_out_valid <= 1'b0;
                                ram_rd_addr   <= 0;
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
    assign VPU_in_ready = passthrough ? (!VPU_out_valid || handshake_out) : (state == FIRST_PASS) && (!VPU_out_valid || handshake_out) && !latched_line_start;
endmodule