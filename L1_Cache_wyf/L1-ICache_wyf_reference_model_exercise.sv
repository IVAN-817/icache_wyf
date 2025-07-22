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







module icache_logic_model(
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

    bit             ready=0;
    bit    [7:0]    index;     
    bit    [5:0]    offset;
    bit    [ICACHE_TAG_WIDTH-1:0]   tag;    //physical, rest of the address  
    bit    [1:0]    way;
    bit             hit;

    offset  = addr_from_core[0+:ICACHE_OFFSET_WIDTH];
    index   = addr_from_core[ICACHE_OFFSET_WIDTH+:ICACHE_INDEX_WIDTH];      
    tag     = addr_from_core[ICACHE_OFFSET_WIDTH+ICACHE_INDEX_WIDTH+:ICACHE_TAG_WIDTH];

    reg [3:0]   state;
    reg [3:0]   next_state;
    





task bit compare_tag();
    for(int i = 0; i<4 ;i++)begin
        addr_to_tag_ram = {tag[ICACHE_TAG_WIDTH-1-:5],{2'b00+i} } //burst read 4 cacheline
        req_to_tag_ram = 1;
    //compare tag
        if(rdata_from_tag_ram)begin
            
        end
    end    
endtask


//receive read request and address from core
    always@(posedge clk)begin
        if(req_from_core)begin
            compare_tag(addr_from_core,rdata_from_tag_ram,way,hit); 
        end
    end




//if miss, 
    //read data from L2-Cache

    //pseudo-LRU replcement policy

    //write data ram
        
    //write tag ram





//if hit
    //read data ram

    //give rdata to core




endmodule