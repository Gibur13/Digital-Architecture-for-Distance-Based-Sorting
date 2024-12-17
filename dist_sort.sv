module dist_sort (
    input logic clk, rst,
    input logic [63:0] query,                    // Query vector
    input logic [63:0] search_0, search_1,       // Individual search vectors
                   search_2, search_3,
                   search_4, search_5,
                   search_6, search_7,
    input logic in_valid,
    output logic [2:0] addr_1st,                 // Address of 1st best match
    output logic [2:0] addr_2nd,                 // Address of 2nd best match
    output logic out_valid                       // Output valid signal
);

    // Intermediate array to hold search vectors
    logic [63:0] search_vectors[7:0];

    // Registering inputs using flip-flops
    logic [63:0] query_r, search_0_r, search_1_r, search_2_r, search_3_r;
    logic [63:0] search_4_r, search_5_r, search_6_r, search_7_r;
    logic in_valid_r;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            query_r <= 64'd0;
            search_0_r <= 64'd0;
            search_1_r <= 64'd0;
            search_2_r <= 64'd0;
            search_3_r <= 64'd0;
            search_4_r <= 64'd0;
            search_5_r <= 64'd0;
            search_6_r <= 64'd0;
            search_7_r <= 64'd0;
            in_valid_r <= 1'b0;
        end else begin
            query_r <= query;
            search_0_r <= search_0;
            search_1_r <= search_1;
            search_2_r <= search_2;
            search_3_r <= search_3;
            search_4_r <= search_4;
            search_5_r <= search_5;
            search_6_r <= search_6;
            search_7_r <= search_7;
            in_valid_r <= in_valid;
        end
    end

    // Assign individual search inputs to array
    assign search_vectors[0] = search_0_r;
    assign search_vectors[1] = search_1_r;
    assign search_vectors[2] = search_2_r;
    assign search_vectors[3] = search_3_r;
    assign search_vectors[4] = search_4_r;
    assign search_vectors[5] = search_5_r;
    assign search_vectors[6] = search_6_r;
    assign search_vectors[7] = search_7_r;

    // Declare the outputs from the distance calculation module
    wire [31:0] distances[7:0];
    wire distances_calculated;

    // Distance Calculation Module Instantiation
    distance_calc distance_calc_inst (
        .clk(clk),
        .rst(rst),
        .query_vector(query_r),
        .search_vectors(search_vectors),           // Array of search vectors
        .in_valid(in_valid_r),
        .distance_results(distances),              // Distance results
        .calculation_complete(distances_calculated) // Calculation complete signal
    );

    // Finding Two Smallest Distances Module
    logic [2:0] addr_1st_internal, addr_2nd_internal;
    logic out_valid_internal;

    find_two_smallest find_two_smallest_inst (
        .clk(clk),
        .rst(rst),
        .in_valid(distances_calculated),
        .distances(distances),                     // Use distances from distance_calc
        .addr_1st(addr_1st_internal),
        .addr_2nd(addr_2nd_internal),
        .out_valid(out_valid_internal)
    );

    // Precompute output valid signal
    logic out_valid_next;
    always_comb begin
        // Precompute the next value for out_valid
        if (out_valid_internal && in_valid_r) begin
            out_valid_next = 1'b1;
        end else begin
            out_valid_next = 1'b0;
        end
    end

    // Registering output signals using flip-flops
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_1st <= 3'd0;
            addr_2nd <= 3'd0;
            out_valid <= 1'b0;
        end else begin
            addr_1st <= addr_1st_internal;  // Directly register precomputed addr_1st_internal
            addr_2nd <= addr_2nd_internal;  // Directly register precomputed addr_2nd_internal
            out_valid <= out_valid_next;    // Use precomputed out_valid_next
        end
    end

endmodule

module distance_calc (
    input logic clk, rst,
    input logic [63:0] query_vector,          // Query vector
    input logic [63:0] search_vectors[7:0],  // Array of 8 search vectors
    input logic in_valid,
    output logic [31:0] distance_results[7:0], // Array to store calculated distances
    output logic calculation_complete
);

    // Registers for input values
    logic [63:0] query_vector_r;
    logic [63:0] search_vectors_r[7:0];
    logic in_valid_r;

    // Temporary variables for squared differences
    logic [31:0] partial_sums[7:0][4]; // Split computation into 4 parallel blocks

    // Register inputs
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            query_vector_r <= 64'd0;
            search_vectors_r <= '{default: 64'd0};
            in_valid_r <= 1'b0;
        end else begin
            query_vector_r <= query_vector;
            search_vectors_r <= search_vectors;
            in_valid_r <= in_valid;
        end
    end

    // Compute squared differences in parallel
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            // Initialize partial sums
            for (int k = 0; k < 4; k++) begin
                partial_sums[i][k] = 32'd0;
            end

            // Compute partial sums in 4 parallel blocks
            for (int j = 0; j < 16; j++) begin
                automatic logic [3:0] query_elem = query_vector_r[j*4 +: 4];
                automatic logic [3:0] search_elem = search_vectors_r[i][j*4 +: 4];
                automatic logic [3:0] abs_diff = (query_elem > search_elem) ? 
                                                 (query_elem - search_elem) : 
                                                 (search_elem - query_elem);

                // Assign to one of the 4 partial sum blocks
                partial_sums[i][j / 4] += abs_diff * abs_diff;
            end
        end
    end

    // Combine partial sums and store in results
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < 8; i++) begin
                distance_results[i] <= 32'd0;
            end
            calculation_complete <= 1'b0;
        end else if (in_valid_r) begin
            for (int i = 0; i < 8; i++) begin
                distance_results[i] <= partial_sums[i][0] +
                                       partial_sums[i][1] +
                                       partial_sums[i][2] +
                                       partial_sums[i][3];
            end
            calculation_complete <= 1'b1;
        end else begin
            calculation_complete <= 1'b0;
        end
    end

endmodule


module find_two_smallest (
    input logic clk, rst,
    input logic in_valid,
    input logic [31:0] distances[7:0],   // Array of distances
    output logic [2:0] addr_1st, addr_2nd, // Addresses of two smallest values
    output logic out_valid
);

    // Stage 1: Pairwise Comparisons
    logic [31:0] stage1_min[3:0], stage1_max[3:0];
    logic [2:0] stage1_min_addr[3:0], stage1_max_addr[3:0];

    compare_and_swap_with_addr_priority u1 (
        .a(distances[0]), .b(distances[1]),
        .addr_a(3'd0), .addr_b(3'd1),
        .min_val(stage1_min[0]), .max_val(stage1_max[0]),
        .min_addr(stage1_min_addr[0]), .max_addr(stage1_max_addr[0])
    );

    compare_and_swap_with_addr_priority u2 (
        .a(distances[2]), .b(distances[3]),
        .addr_a(3'd2), .addr_b(3'd3),
        .min_val(stage1_min[1]), .max_val(stage1_max[1]),
        .min_addr(stage1_min_addr[1]), .max_addr(stage1_max_addr[1])
    );

    compare_and_swap_with_addr_priority u3 (
        .a(distances[4]), .b(distances[5]),
        .addr_a(3'd4), .addr_b(3'd5),
        .min_val(stage1_min[2]), .max_val(stage1_max[2]),
        .min_addr(stage1_min_addr[2]), .max_addr(stage1_max_addr[2])
    );

    compare_and_swap_with_addr_priority u4 (
        .a(distances[6]), .b(distances[7]),
        .addr_a(3'd6), .addr_b(3'd7),
        .min_val(stage1_min[3]), .max_val(stage1_max[3]),
        .min_addr(stage1_min_addr[3]), .max_addr(stage1_max_addr[3])
    );

    // Stage 2: Second Level Comparisons
    logic [31:0] stage2_min[1:0], stage2_max[1:0];
    logic [2:0] stage2_min_addr[1:0], stage2_max_addr[1:0];

    compare_and_swap_with_addr_priority u5 (
        .a(stage1_min[0]), .b(stage1_min[1]),
        .addr_a(stage1_min_addr[0]), .addr_b(stage1_min_addr[1]),
        .min_val(stage2_min[0]), .max_val(stage2_max[0]),
        .min_addr(stage2_min_addr[0]), .max_addr(stage2_max_addr[0])
    );

    compare_and_swap_with_addr_priority u6 (
        .a(stage1_min[2]), .b(stage1_min[3]),
        .addr_a(stage1_min_addr[2]), .addr_b(stage1_min_addr[3]),
        .min_val(stage2_min[1]), .max_val(stage2_max[1]),
        .min_addr(stage2_min_addr[1]), .max_addr(stage2_max_addr[1])
    );

    // Final Stage: Find Smallest and Second Smallest
    logic [31:0] final_min, final_2nd_min;
    logic [2:0] final_min_addr, final_2nd_min_addr;

    always_comb begin
        if (stage2_min[0] < stage2_min[1] || 
           (stage2_min[0] == stage2_min[1] && stage2_min_addr[0] < stage2_min_addr[1])) begin
            final_min = stage2_min[0];
            final_min_addr = stage2_min_addr[0];
        end else begin
            final_min = stage2_min[1];
            final_min_addr = stage2_min_addr[1];
        end

        final_2nd_min = 32'hFFFFFFFF;
        final_2nd_min_addr = 3'd0;
        for (int i = 0; i < 8; i++) begin
            if (i != final_min_addr) begin
                if (distances[i] < final_2nd_min || 
                   (distances[i] == final_2nd_min && i < final_2nd_min_addr)) begin
                    final_2nd_min = distances[i];
                    final_2nd_min_addr = i[2:0];
                end
            end
        end

        // Assign output addresses immediately
        if (in_valid) begin
            addr_1st = final_min_addr;
            addr_2nd = final_2nd_min_addr;
        end else begin
            addr_1st = 3'd0;
            addr_2nd = 3'd0;
        end
    end

    // Sequential logic for output valid signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid <= 1'b0;
        end else begin
            out_valid <= in_valid;
        end
    end

endmodule




module compare_and_swap_with_addr_priority (
    input logic [31:0] a, b,
    input logic [2:0] addr_a, addr_b,
    output logic [31:0] min_val, max_val,
    output logic [2:0] min_addr, max_addr
);
    always_comb begin
        if (a < b) begin
            min_val = a;
            max_val = b;
            min_addr = addr_a;
            max_addr = addr_b;
        end else if (a > b) begin
            min_val = b;
            max_val = a;
            min_addr = addr_b;
            max_addr = addr_a;
        end else begin
            if (addr_a < addr_b) begin
                min_val = a;
                max_val = b;
                min_addr = addr_a;
                max_addr = addr_b;
            end else begin
                min_val = b;
                max_val = a;
                min_addr = addr_b;
                max_addr = addr_a;
            end
        end
    end
endmodule

