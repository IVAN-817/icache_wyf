function plru1 icache_rm::plru_tree(bit write, int nways, plru1 plru)
    bit [31:0] tree = plru.tree;
    int i = 1;
    if(write == 1)begin
        for(int layer = 0; layer <$clog(nways); layer++)begin
           if(tree[i] == 1'b0)begin
               tree[i] = 1'b1;
               i = i * 2;
           end else begin
               tree[i] = 1'b0;
               i = i * 2 + 1;
           end
        end
        plru.replace_num = i - nways;
    end else begin
        for(i = plru.read_num + nways; i >= 2; i /= 2)begin
            if(i % 2 === 0) tree[i/2] = 1'b1;
            else tree[i/2] = 1'b0;
        end
    plru.tree = tree;
    end
    return plru;    //返回一个plru1类型变量
endfunction