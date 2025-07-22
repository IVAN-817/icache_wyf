//! Copyright (C) 2025, Andes Technology Corp. Confidential Proprietary


module nds_ecc_ram_model (
	clk,
	we,
	cs,
	addr,
	din,
	dout
);

parameter  WRITE_WIDTH		= 64;
parameter  ADDR_WIDTH		= 5;
parameter  IN_DELAY		= 0;
parameter  OUT_DELAY		= 0;
parameter  ENABLE		= "yes";
parameter  INJECT_ECC           = 0;
parameter  INJECT_ECC_CORR      = 1;
parameter  INIT_BY_ECC_INJECT	= 0;
parameter  ECC_PROBABILITY	= 30;

localparam MEM_SIZE		= 2 ** ADDR_WIDTH;
localparam DATA_WIDTH           = WRITE_WIDTH;
localparam TABLE_DEPTH          = 16;
localparam TABLE_ADDR_WIDTH     = $clog2(TABLE_DEPTH);
localparam STORE_ADDR_WIDTH	= ADDR_WIDTH - TABLE_ADDR_WIDTH;

`ifdef DO_NOT_KEEP_ECC
localparam KEEP_ECC             = 0;
`else
localparam KEEP_ECC             = 1;
`endif

integer ecc_probability;


input				clk;
input				we;
input				cs;
input [(ADDR_WIDTH-1):0]	addr;
input [(WRITE_WIDTH-1):0]	din;
output [(WRITE_WIDTH-1):0]	dout;

// synthesis translate_off
wire [(WRITE_WIDTH-1):0]	r_dout;
wire [(WRITE_WIDTH-1):0]	p_dout;
reg  [(WRITE_WIDTH-1):0]	mem[0:(MEM_SIZE-1)];
// synthesis translate_on
wire				we_dly;
wire				cs_dly;
wire [(ADDR_WIDTH-1):0]		addr_dly;
wire [(WRITE_WIDTH-1):0]	din_dly;

reg [(ADDR_WIDTH-1):0]		read_addr;

assign #(IN_DELAY) we_dly   = we;
assign #(IN_DELAY) cs_dly   = cs;
assign #(IN_DELAY) addr_dly = addr;
assign #(IN_DELAY) din_dly  = din;

reg				    hit_valid;
reg				    sel_valid;
reg	[(TABLE_ADDR_WIDTH-1):0]    sel_index;
reg				    record_valid;
reg	[(TABLE_ADDR_WIDTH-1):0]    record_index;
reg	[WRITE_WIDTH-1:0]	    flip;
reg	[WRITE_WIDTH-1:0]	    fliped;

reg	[31:0]			    seed;
reg	[128*8-1:0]		    hierarchical_name;

always @(posedge clk) begin
	if (cs_dly) begin
		if (we_dly) begin
			// synthesis translate_off
			mem[addr_dly] <= din_dly;
			// synthesis translate_on
		end
	end
end

always @(posedge clk) begin
	if (cs_dly) begin
		if (we_dly)
			read_addr <= {ADDR_WIDTH{1'bx}};
		else
			read_addr <= addr_dly;
	end
end

// synthesis translate_off

initial begin
	hierarchical_name = $sformatf("%m");
	if ($value$plusargs("seed=%d", seed))
		seed = hierarchical_name % (seed ^ 32'hbf478287);
	else
		seed = hierarchical_name % 32'hbf478287;

	hit_valid	= 1'b0;
	sel_valid	= 1'b0;
	sel_index	= {TABLE_ADDR_WIDTH{1'b0}};
	record_valid	= 1'b0;
	record_index	= {TABLE_ADDR_WIDTH{1'b0}};
	flip            = {WRITE_WIDTH{1'b0}};
	fliped          = {WRITE_WIDTH{1'b0}};

`ifdef NDS_ECC_RAND_INJECT_MORE_CORR_ERROR
	ecc_probability = ECC_PROBABILITY * 2;
`elsif DO_NOT_KEEP_ECC
	ecc_probability = ECC_PROBABILITY / 2;
`else
	ecc_probability = ECC_PROBABILITY;
`endif




`ifndef NDS_INIT_ECC_RAM
	if (INIT_BY_ECC_INJECT) begin
`endif
		for (integer i = 0; i < MEM_SIZE; i++) begin
			for (integer j = 0; j < WRITE_WIDTH; j++) begin
				mem[i][j] = $random(seed);
			end
		end
`ifndef NDS_INIT_ECC_RAM
	end
`endif
end

generate
if (INJECT_ECC) begin

	wire	[(WRITE_WIDTH-1):0]	    sel_dout;
	reg	[WRITE_WIDTH-1:0]	    dout_table [0:TABLE_DEPTH];
	reg	[STORE_ADDR_WIDTH-1:0]	    addr_table [0:TABLE_DEPTH];
	reg				    valid_table [0:TABLE_DEPTH];
	wire	[(TABLE_ADDR_WIDTH-1):0]    cmp_index;

	assign cmp_index = addr_dly[(TABLE_ADDR_WIDTH-1):0];

	always @ (posedge clk) begin
		if (cs_dly && we_dly && hit_valid) begin
			valid_table[cmp_index]	<= 1'b0;
			record_valid		<= 1'b0;
			sel_valid		<= 1'b0;
		end
		else if (cs_dly && !we_dly && hit_valid) begin
			record_valid		<= 1'b0;
			sel_valid		<= KEEP_ECC;
			sel_index		<= cmp_index;
		end
		else if (cs_dly && !we_dly && !hit_valid) begin
			valid_table[cmp_index]	<= 1'b1;
			addr_table[cmp_index]	<= addr_dly[(ADDR_WIDTH-1):TABLE_ADDR_WIDTH];
			record_valid		<= 1'b1;
			record_index		<= cmp_index;
			sel_valid		<= 1'b0;
		end
		else begin
			record_valid		<= 1'b0;
			sel_valid		<= 1'b0;
		end
	end

	always @ (posedge clk) begin
		if (record_valid) begin
			dout_table[record_index] <= p_dout;
			fliped <= fliped | flip;
		end
	end
	always @ (*) begin
		if (valid_table[cmp_index] && (addr_dly[(ADDR_WIDTH-1):TABLE_ADDR_WIDTH] == addr_table[cmp_index])) begin
			hit_valid = 1'b1;
		end
		else begin
			hit_valid = 1'b0;
		end
	end

	always @(negedge clk) begin
		if (INJECT_ECC_CORR) begin
			if (({$random(seed)} % 100) < ecc_probability) begin
				if((({$random(seed)} % 100) < 30) & ~(&fliped)) begin
					flip <= (~fliped & (fliped + {{{WRITE_WIDTH-1}{1'b0}}, 1'b1}));
				end else begin
					flip <= {{(WRITE_WIDTH-1){1'b0}}, 1'b1} << ({$random(seed)}%WRITE_WIDTH);
				end
			end
			else begin
				flip <= {WRITE_WIDTH{1'b0}};
			end
		end
		else begin
			if (({$random(seed)} % 100) < ecc_probability) begin
				flip <= flip_num();
			end
			else begin
				flip <= {WRITE_WIDTH{1'b0}};
			end
		end
	end

	assign r_dout   = dout_table[sel_index];
	assign p_dout   = mem[read_addr] ^ flip;
	assign sel_dout = sel_valid ? r_dout : p_dout;
	assign #(OUT_DELAY) dout = sel_dout;
end
else begin
	assign p_dout = mem[read_addr];
	assign #(OUT_DELAY) dout = p_dout;
end
endgenerate

function automatic bit [WRITE_WIDTH-1:0] flip_num ();

	bit [WRITE_WIDTH-1:0] temp_num = 0;
	int index1 = $urandom_range(WRITE_WIDTH);
	int index2 = $urandom_range(WRITE_WIDTH);

	while (index2 == index1) begin
		index2 = $urandom_range(WRITE_WIDTH);
	end

	temp_num[index1] = 1;

	if ($urandom_range(2)) temp_num[index2] = 1;

	return temp_num;
endfunction


`ifdef NDS_INTERNAL_SIM
initial begin
$display ("NDS_MEM_INFO:%m:ADDR_WIDTH = %2d", ADDR_WIDTH);
$display ("NDS_MEM_INFO:%m:DATA_WIDTH = %2d", WRITE_WIDTH);
$display ("NDS_MEM_INFO:%m:WE_WIDTH   = %2d", 1);
$display ("NDS_MEM_INFO:%m:ENABLE     = %3s", ENABLE);
end
`endif

// synthesis translate_on


endmodule
