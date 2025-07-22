


// ---AX65 icache-memory spec---
// !The width of the address bus (BIU_ADDR_WIDTH) can be any width between 32 and 47 bits
parameter ICACHE_TAG_RAM_AW     = 7;
parameter ICACHE_TAG_RAM_DW     = BIU_ADDR_WDITH-3;
parameter ICACHE_DATA_RAM_AW    = 10;
parameter ICACHE_DATA_RAM_DW    = 72;   //Data Width = 64+8(ECC)bit

// output icache_tag0_cs,
// output icache_tag0_we,
// output [ICACHE_TAG_RAM_AW-1:0] icache_tag0_addr,
// output [ICACHE_TAG_RAM_DW-1:0] icache_tag0_wdata,
// input [ICACHE_TAG_RAM_DW-1:0] icache_tag0_rdata,

// output icache_data0_cs,
// output icache_data0_we,
// output [ICACHE_DATA_RAM_AW-1:0] icache_data0_addr,
// output [ICACHE_DATA_RAM_DW-1:0] icache_data0_wdata,
// input [ICACHE_DATA_RAM_DW-1:0] icache_data0_rdata,

// ---AX65 lcache-logic spec---
// ...



module L1_cache#(
    parameter AW = 64;      // unknown, maybe configurable 
    parameter DW = 64;      // 64 bit by default
//    parameter CL_SIZE = 64*8; // 64 Byte by default
    parameter CLSET_NUMBER = 256;

)(
    input   clk,
    // input   rst,

    //with core
    input   valid_from_core,
    output  ready_to_core,
    input   we_from_core,                          //write_enable signal from  core

    input   logic   [AW-1:0]    address_from_core,   // 
    input   logic   [DW-1:0]    data_from_core, // core can write data to i/d cache
    output  logic   [DW-1:0]    data_to_core,


    //with L2-Cache
    input   ready_from_L2,          // actually the we signal
    output  valid_to_L2,

    // output  we_to_L2, //to be adjsted

    output  logic   [AW-1:0]    address_to_L2,
    output  logic   [DW*8-1:0]    data_to_L2,
    input   logic   [DW*8-1:0]    data_from_L2,        // note that the data width between L1 and L2 could be different(?)
    // input   logic   [AW-15:0]   address_from_L2
);

    integer i,j;

    localparam             IDLE=4'b0001,COMPARE=4'b0010,WB=4'b0100,ALLOCATE=4'b1000;

    reg    hit;
    reg [1:0] way;

    reg [DW-1:0]       data_array      [CLSET_NUMBER][4][8];
    reg [AW-15+2:0]            tag_array       [CLSET_NUMBER][4];      //tag+dirty_bit+valid_bit, dirty_bit is the last one, valid is the 2nd last one


    reg [3:0]   state;
    reg [3:0]   next_state;

    //Pseudo-LRU tree
    reg br1, br2a, br2b;
    reg [2:0] br_ptr = {br1, br2a, br2b};
    //address
    wire    [7:0]   index = address_from_core[6+:8];      //virtual, 8bits
    wire    [5:0]   offset= address_from_core[0+:6];     // 6bits
    wire    [AW-15:0]   tag = address_from_core[14+:AW-14];    //physical, rest of the address
    
    // determine whther hit or miss by tag comparing and valid bit checking
    always@（posedge req_from_core) begin        
        foreach(i) begin        // i: 0~3
            compare_tag(,);
        end    
    end

    //FSM (3 stages)
    //stage-1: state transition
    always@(posedge clk)begin
        state <= next_state;
    end
    //stage-2: transition condition
    always@(*)begin
        case(state)
            IDLE:   next_state = valid_from_core ? COMPARE : IDLE;
            COMPARE: begin
                if(valid_from_core)begin
                    if(hit) 
                        next_state = COMPARE;                       
                    else if(tag_array[index][way][-1:-2]==2'b11) 
                        next_state = WB;                            //如果没有hit，且该cacheline是dirty的，则需要先把它写回给L2-Cache
                    else
                        next_state = ALLOCATE;                      //如果没有hit，且已经写回过了不是脏的(dirty=0)，该cacheline是空的（valid=0），则将L2-Cache的数据更新进来
                end
                else begin                                          //从core那边没有读写信号需求了，返回IDLE
                    next_state = IDLE;
                end
            end
            WB:     next_state = ready_from_L2 ? ALLOCATE : WB;     //如果L2-cache表示ready了，说明写回完成，就进入allocate状态
            ALLOCATE: next_state = ready_from_L2 ? COMPARE : ALLOCATE;
            default: next_state = IDLE;
        endcase
    end

    // stage-3: output
 

    // replacement policy: Pseudo-LRU 
    always@(*)begin
        if(hit)begin       //命中
            case(way)
                2'b00: {br1,br2a} = ~way;
                2'b01: {br1,br2a} = ~way;
                2'b10: {br1,br2b} = ~way;
                2'b11: {br1,br2b} = ~way;
                default: {br1,br2a,br2b} = {br1,br2a,br2b};
            endcase;
        end
        else if(!hit)begin
            way = br1 ? {1'b1,br2b} : {1'b0,br2a};
        end
    end

    // read out to core --or-- write in 
    always@(posedge clk)begin
        if((state == COMPARE) && hit)begin
            if(we_from_core == 1'b0)begin
                data_to_core <= data_array[index][way][offset];
            end
            else begin
                data_array[index][way][offset] <= data_from_core;
                tag_array[index][way][-1:-2] <= 2'b11;
            end
        end
    end

    // cacheline updating (ALLOCATE)
    always@(posedge clk)begin
        if((state ==WB) && ready_from_L2 && valid_to_L2)
            tag_array[index][way][-1] = 1'b0;     //clear dirty bit after write-back
        else if((state == ALLOCATE) && ready_from_L2 && valid_to_L2) begin  
            tag_array[index][way][-2] = 1'b1;          //更新后，该cacheline有效
            data_array[index][way] = data_from_L2;    //cacheline的数据更新的最小单位是cacheline（这里一个cacheline有8个DW）
            tag_array[index][way][AW-15:0] = tag;     //更新tag
        end
    end

    // ready_to_core
    assign ready_to_core  = (state == COMPARE) || hit;

    // 
    assign address_to_L2 = ((state == WB) || (state == ALLOCATE)) ? address_from_core : 0;

    // valid signal (to L2-Cache) control
    always@(posedge clk)begin
        if(state == COMPARE || !hit)
            valid_to_L2 = 1'b1;
        else if(state == WB || ready_from_L2 == 1)
            valid_to_L2 = 1'b0;     //写回完成
        else if(state == ALLOCATE || ready_from_L2 == 1)
            valid_to_L2 = 1'b0;     //更新完成
    end


    // data to L2-Cache
    always@(posedge clk)begin
        if(state == WB)
            data_to_L2 <= data_array[index][way];
    end

endmodule