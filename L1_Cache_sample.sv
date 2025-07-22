`include "macro.v" // 包含宏定义文件，假设该文件定义了一些常用的宏，例如数据总线宽度等。

module I_Cache(
    input             wire             clk,          // 时钟信号
    input             wire             rst,          // 复位信号
    //to mem  与内存交互的信号
    output             reg [`InstAddrBus]        mem_req_addr,  // 内存请求地址
    output             reg [127:0]                mem_wr_data,   // 写入内存的数据 (128位)
    output             reg                     mem_req_valid, // 内存请求有效信号
    output             reg                     mem_req_wr,     // 内存请求类型 (写操作) - 这里只读，所以始终为0
    input             wire [127:0]            mem_req_data,   // 从内存读取的数据 (128位)
    input             wire                     mem_req_ready,  // 内存请求准备好信号
    //to CPU 与CPU交互的信号
    input             wire [`InstAddrBus]        cpu_req_addr,  // CPU请求地址
    input             wire                     cpu_req_valid, // CPU请求有效信号
    input             wire                     cpu_req_wr,     // CPU请求类型 (写操作) - 缓存通常只读指令
    output             reg [`RegBus]            cpu_req_data,  // 返回给CPU的数据
    output             reg                     cpu_req_ready  // CPU请求准备好信号
    );


localparam             IDLE=4'b0001,CompareTag=4'b0010,WriteBack=4'b0100,Allocate=4'b1000; // 状态机状态定义
localparam            V=141,D=140,U=139,TagMSB=138,TagLSB=128,DataMSB=127,DataLSB=0; // 位宽定义，V:有效位，D:脏位，U:未使用，TagMSB/LSB:标签高低位，DataMSB/LSB:数据高低位
wire                 hit,way1hit,way2hit;                                   // 命中标志
wire                 CachelineDirty;                                         // 缓存行脏位
reg                 way;                                                    // 缓存未命中时，选择替换哪一行
wire         [3:0]    cpu_req_index;                                       // CPU请求的索引
wire         [23:0]    cpu_req_tag;                                        // CPU请求的标签
wire         [1:0]    cpu_req_offset;                                      // CPU请求的偏移量
integer             i;                                                      // 循环变量
wire                 mem_ready_valid;                                      // 内存准备好且请求有效的信号
reg     [141:0] cache_data [31:0];                                      // 缓存数据，每行142位 (有效位，脏位，未使用位，标签，数据)
reg     [3:0]    state,next_state;                                        // 状态机当前状态和下一状态


assign way1hit = cache_data[2*cpu_req_index][V]==1'b1 && cache_data[2*cpu_req_index][TagMSB:TagLSB]==cpu_req_tag; // way1命中条件
assign way2hit = cache_data[2*cpu_req_index+1][V]==1'b1 && cache_data[2*cpu_req_index+1][TagMSB:TagLSB]==cpu_req_tag; // way2命中条件

// 字节寻址
assign cpu_req_index = cpu_req_addr[7:4];   // 索引位
assign cpu_req_tag = cpu_req_addr[31:8];  // 标签位
assign cpu_req_offset = cpu_req_addr[3:2]; // 偏移量位

assign mem_ready_valid = mem_req_valid & mem_req_ready; // 内存准备好且请求有效的信号

assign hit = way1hit | way2hit;           // 命中标志
assign CachelineDirty = cache_data[2*cpu_req_index+way][V:D]==2'b11; // 缓存行脏位标志


// 状态机
always @(posedge clk) begin
    if (rst) begin
        state <= IDLE; // 复位时进入IDLE状态
    end
    else begin
        state <= next_state; // 否则进入下一状态
    end
end

always @(*) begin
    case(state)
        IDLE: next_state = cpu_req_valid ? CompareTag : IDLE; // 空闲状态，收到CPU请求则进入比较标签状态
        CompareTag:begin // 比较标签状态
            if (cpu_req_valid) begin
                if (hit) begin
                    next_state = CompareTag; // 命中，保持当前状态
                end
                else if (CachelineDirty) begin
                    next_state = WriteBack; // 未命中且缓存行脏，则先写回内存
                end
                else begin
                    next_state = Allocate; // 未命中且缓存行不脏，则分配新的缓存行
                end
            end
            else begin
                next_state = IDLE; // 没有CPU请求，则返回空闲状态
            end
        end
        WriteBack: next_state = mem_req_ready ? Allocate : WriteBack; // 写回内存，等待内存准备好
        Allocate: next_state = mem_req_ready ? CompareTag : Allocate; // 分配缓存行，等待内存准备好
        default: next_state = IDLE; // 默认返回空闲状态
    endcase
end

// 选择替换哪一行 (LRU替换算法的简化版)
always @(*) begin
    if (!hit) begin
        case({cache_data[2*cpu_req_index][V],cache_data[2*cpu_req_index+1][V]})
            2'b00:way=1'b0; // 两行都可，选择way0
            2'b01:way=1'b0; // way0可way1不可，选择way0
            2'b10:way=1'b1; // way1可way0不可，选择way1
            2'b11:way=1'b0; // 两行都不valid，选择way0 (简化LRU)
            default:way=1'b0;
        endcase
    end
end

// 返回给CPU的数据
always @(*) begin
    if (rst) begin
        cpu_req_data <= 'd0; // 复位时，数据为0
    end
    else if (state==CompareTag && hit) begin
        cpu_req_data <= way1hit ? cache_data[2*cpu_req_index][(3-cpu_req_offset)<<5+:31] : // 命中way1，返回way1的数据
                                    cache_data[2*cpu_req_index+1][(3-cpu_req_offset)<<5+:31]; // 命中way2，返回way2的数据
    end
    else begin
        cpu_req_data <= cpu_req_data; // 其他状态，保持数据不变
    end
end

// 缓存行数据更新
always @(posedge clk) begin
    if (rst) begin
        for(i=0;i<32;i=i+1)begin
            cache_data[i] <= 'd0; // 复位时，缓存数据清零
        end
    end
    else if (state==WriteBack && mem_ready_valid==1'b1) begin
        cache_data[2*cpu_req_index+way][D] <= 1'b0; // 写回内存后，清除脏位
    end
    else if (state==CompareTag && CachelineDirty==1'b1) begin
        cache_data[2*cpu_req_index+way][D] <= 1'b1; // 未命中且脏，设置脏位
    end
    else if (state==Allocate && mem_ready_valid==1'b1) begin
        cache_data[2*cpu_req_index+way][V] <= 1'b1; // 分配缓存行，设置有效位
        cache_data[2*cpu_req_index+way][DataMSB:DataLSB] <= mem_req_data; // 将数据写入缓存
        cache_data[2*cpu_req_index+way][TagMSB:TagLSB] <= cpu_req_addr[TagMSB:TagLSB]; // 将标签写入缓存
    end
end

// CPU请求准备好信号
always @(*) begin
    if (state==CompareTag && hit==1'b1) begin
        cpu_req_ready <= 1'b1; // 命中则准备好
    end
    else begin
        cpu_req_ready <= 1'b0; // 未命中则不准备好
    end
end

// 内存请求地址
always @(*) begin
    if (rst) begin
        mem_req_addr <= 'd0; // 复位时，地址为0
    end
    else if (state==WriteBack || state==Allocate) begin
        mem_req_addr <= cpu_req_addr; // 写回或分配时，内存请求地址为CPU请求地址
    end
end

// 内存请求有效信号
always @(posedge clk) begin
    if (rst) begin
        mem_req_valid <= 1'b0; // 复位时，请求无效
    end
    else if (state==CompareTag && hit==1'b0) begin
        mem_req_valid <= 1'b1; // 未命中，则发送内存请求
    end
    else if (state==WriteBack && mem_req_ready==1'b1) begin
        mem_req_valid <= 1'b0; // 写回完成，请求无效
    end
    else if (state==Allocate && mem_req_ready==1'b1) begin
        mem_req_valid <= 1'b0; // 分配完成，请求无效
    end
end

// 写入内存的数据
always @(posedge clk) begin
    if (rst) begin
        mem_wr_data <= 'd0; // 复位时，数据为0
    end
    else if (state==WriteBack) begin
        mem_wr_data <= cache_data[2*cpu_req_index+way][DataMSB:DataLSB]; // 写回数据
    end
end

endmodule