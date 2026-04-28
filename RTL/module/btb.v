`timescale 1ns / 1ps

module BTB #(
    parameter ENTRY_COUNT = 16,
    parameter INDEX_BITS = 4,
    parameter TAG_BITS   = 26
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] pc_search,
    output wire        hit,
    output wire [31:0] target,
    input  wire        update,
    input  wire [31:0] update_pc,
    input  wire [31:0] update_target
);

    localparam TAG_WIDTH = TAG_BITS;

    wire [INDEX_BITS-1:0] search_index = pc_search[INDEX_BITS+1:2];
    wire [TAG_WIDTH-1:0]  search_tag   = pc_search[31:INDEX_BITS+2];

    reg [TAG_WIDTH-1:0] tag_array [0:ENTRY_COUNT-1];
    reg [31:0]          target_array [0:ENTRY_COUNT-1];
    reg                 valid_array [0:ENTRY_COUNT-1];

    wire [INDEX_BITS-1:0] update_index = update_pc[INDEX_BITS+1:2];
    wire [TAG_WIDTH-1:0]  update_tag   = update_pc[31:INDEX_BITS+2];

    assign hit = valid_array[search_index] && (tag_array[search_index] == search_tag);
    assign target = target_array[search_index];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ENTRY_COUNT; i = i + 1) begin
                valid_array[i]  <= 1'b0;
                tag_array[i]    <= {TAG_WIDTH{1'b0}};
                target_array[i] <= 32'b0;
            end
        end else begin
            if (update) begin
                valid_array[update_index]  <= 1'b1;
                tag_array[update_index]    <= update_tag;
                target_array[update_index] <= update_target;
            end
        end
    end

endmodule
