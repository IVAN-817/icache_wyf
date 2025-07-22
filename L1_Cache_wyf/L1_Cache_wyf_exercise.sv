



module L1_cache#(
//Virtual Address
parameter VALEN = 44
//Physical tag+...
parameter PALEN = 41


parameter ICACHE_TAG_RAM_AW = 7
parameter ICACHE_TAG_RAM_DW = 41
parameter ICACHE_TAG_WIDTH = 32
parameter ICACHE_OFFSET_WIDTH=3
parameter ICACHE_INDEX_WIDTH=8


parameter ICACHE_DATA_RAM_AW = 10
parameter ICACHE_DATA_RAM_DW = 72


parameter DW=64

)(
    input clk,

    //interaction with core
    input req_from_core,
    input [VALEN-1:0] addr_from_core,          
    output [DW-1:0] rdata_to_core,

    ////START:interaction with L1-memory domain////
    //interaction with tag rams
    output req_to_tag_ram,
    output we_to_tag_ram,
    output [ICACHE_TAG_RAM_AW-1:0] addr_to_tag_ram,
    output [ICACHE_TAG_RAM_DW-1:0] wdata_to_tag_ram,          
    input [ICACHE_TAG_RAM_DW-1:0] rdata_from_tag_ram,
    //interaction with data rams
    output reg_to_data_ram,
    output we_to_data_ram,
    output [ICACHE_DATA_RAM_DW-1:0] addr_to_data_ram,
    output [ICACHE_DATA_RAM_DW-1:0] wdata_to_data_ram,          
    input [ICACHE_DATA_RAM_DW-1:0] rdata_from_data_ram,
    ////END: interaction with L1-memory domain/////


    //interaction with next level of cache or Main Memory
    output req_to_L2,
    output [VALEN-1:0] addr_to_L2,          
    input [DW-1:0] rdata_from_L2,

);

    integer i,j;
    bit             ready=0;
    bit    [7:0]    index;     
    bit    [5:0]    offset;
    bit    [ICACHE_TAG_WIDTH-1:0]   tag;    //physical, rest of the address  
    bit    [1:0]    way;
    bit             hit;

    localparam             IDLE=4'b0001,COMPARE=4'b0010,WB=4'b0100,ALLOCATE=4'b1000;

    reg [3:0]   state;
    reg [3:0]   next_state;

    //Pseudo-LRU tree
    // reg br1, br2a, br2b;
    // reg [2:0] br_ptr = {br1, br2a, br2b};
    //address
    assign offset  = addr_from_core[0+:ICACHE_OFFSET_WIDTH];
    assign index   = addr_from_core[ICACHE_OFFSET_WIDTH+:ICACHE_INDEX_WIDTH];      
    assign tag     = addr_from_core[ICACHE_OFFSET_WIDTH+ICACHE_INDEX_WIDTH+:ICACHE_TAG_WIDTH];

    
    // determine whther hit or miss by tag comparing and valid bit checking
    always@（posedge req_from_core) begin        
        foreach(i) begin        // i: 0~3
            compare_tag();
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