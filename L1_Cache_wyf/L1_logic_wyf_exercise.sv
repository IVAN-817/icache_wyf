module L1_logic(
    input clk,
//with core
    input we_from_core,
    input req_from_core,
    input [63:0] addr_from_core,             // 64bit+8bit, including tag, index, offset (ASSUEM NO ECC)
    input [(WRITE_WIDTH-1):0] data_from_core,             // 64bit
    output [(WRITE_WIDTH-1):0] data_to_core,               // 64bit
// with L1-Cache memory tag ram
    output we_to_memory,
    output cs_to_memory,               //selecet which ram* to access
    output [(ADDR_WIDTH-1):0] addr_to_memory,
    output [(WRITE_WIDTH-1):0] wdata_to_memory,
    input [(WRITE_WIDTH-1):0] rdata_from_memory,

// with L1-cache memory data ram
    output we_to_memory,
    output cs_to_memory,               //selecet which ram* to access
    output [(ADDR_WIDTH-1):0] addr_to_memory,
    output [(WRITE_WIDTH-1):0] wdata_to_memory,
    input [(WRITE_WIDTH-1):0] rdata_from_memory,
//with L2-Cache (or SRAM Memory we can preliminarily assume)
    output we_to_L2,
    output req_to_L2,
    output [63:0] addr_to_L2,
    output [(WRITE_WIDTH-1):0] data_to_L2,
    input [(WRITE_WIDTH-1):0] data_from_L2
    
);
    integer i,j;

    parameter  WRITE_WIDTH		= 64;
    parameter  ADDR_WIDTH		= 9;
    parameter  IN_DELAY		= 0;
    parameter  OUT_DELAY		= 0;
    parameter  ENABLE		= "yes";
    parameter  INJECT_ECC           = 0;
    parameter  INJECT_ECC_CORR      = 1;
    parameter  INIT_BY_ECC_INJECT	= 0;
    parameter  ECC_PROBABILITY	= 30;

    localparam             IDLE=4'b0001,COMPARE=4'b0010,WB=4'b0100,ALLOCATE=4'b1000;
    localparam INDEX_WIDTH = 8;
    localparam OFFSET_WIDTH = 3;
    localparam BUS_WIDTH = 64;
    localparam TAG_WIDTH = BUS_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;

    reg    hit;
    reg [1:0] way;

    reg [3:0]   state;
    reg [3:0]   next_state;

    //Pseudo-LRU tree
    reg br1, br2a, br2b;
    reg [2:0] br_ptr = {br1, br2a, br2b};
    //address
    wire    [BUS_WIDTH-1:0]   offset= addr_from_core[0+:OFFSET_WIDTH];  
    wire    [INDEX_WIDTH-1:0]   index = addr_from_core[OFFSET_WIDTH+:INDEX_WIDTH];      
    wire    [TAG_WIDTH-1:0]   tag = addr_from_core[BUS_WIDTH-1:OFFSET_WIDTH+INDEX_WIDTH];    

    //------------------reaction with memory cache------------------
    // suppose only D-cache's 16 rams    


    //data
    cs_to_memory[ index[INDEX_WIDTH-1-:4] ] = 1'b1; //selecet ram


    addr_to_memory = 





    //------------------end reaction with memory cache------------------

    // determine whther hit or miss by tag comparing and valid bit checking
    always@(*) begin
        foreach(i) begin        // i: 0~3
            //if any tag in this set of cachlines equals the one in the address, and its valid bit is also 1, then hit
            if( (tag == tag_array[index][i][AW-15:0] )&& tag_array[index][i][-2])begin          
                hit = 1;
                way = i;
            end
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
