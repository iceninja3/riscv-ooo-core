package pipeline_types;

typedef struct packed {
    logic [31:0] pc;
    logic [31:0] imm;
    logic [2:0]  alu_op;
    logic        alu_src;   // 1 if Second Operand is Immediate
    logic        mem_read;
    logic        mem_write;
    
    // Physical tags
    logic [5:0]  p_src1;
    logic [5:0]  p_src2;
    logic [5:0]  p_dst;
    logic [5:0]  rob_tag;
    
    // Internal State (Not from Dispatch, but tracked in RS)
    logic        src1_ready;
    logic        src2_ready;
} rs_entry_t;


typedef struct packed {
    logic        valid;         // Is this slot occupied?
    logic        done;          // Has execution finished? (Ready to commit?)
    logic [4:0]  rd_log;        // Logical destination (r1, r2...)
    logic [5:0]  rd_phys;       // New physical destination (p32...)
    logic [5:0]  rd_old_phys;   // Old physical destination (stale p5...) to free
    logic        is_branch;     // Is this a branch?
    logic        mispredicted;  // Did this branch mispredict?
    logic [31:0] pc;            // PC for exception/recovery
} rob_entry_t; // for ROB

// 1. Packet sent from Dispatch -> Reservation Stations
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] imm;
    logic [2:0]  alu_op;
    logic        alu_src;
    logic        mem_read;
    logic        mem_write;
    
    // Physical Tags (Rename results)
    logic [5:0]  rs1_p;
    logic [5:0]  rs2_p;
    logic [5:0]  rd_p;      // Physical Destination
    logic [3:0]  rob_tag;   // ROB ID (assuming 16 entries = 4 bits)
} rs_issue_packet_t;

typedef enum logic [1:0] {
        FU_ALU,    // Add, Sub, Logical
        FU_LSU,    // Load, Store
        FU_BRANCH, // Branch, Jump
        FU_OTHER   // System instructions or errors
    } fu_type_t;
    // which FU to use later on

typedef struct packed {
        logic [31:0] pc;
        logic [31:0] imm;
        logic [31:0] inst;    // inst for debugging
        logic        ALUSrc;
        logic [2:0]  ALUOp;
        logic        MemRead;
        logic        MemWrite;
        logic        RegWrite;
        logic        MemToReg;
        fu_type_t    fu_type; // dispatcher needs this to route instructions appropriately
        logic        is_branch;
        logic        is_jump;
    } ctrl_payload_t;
    //payload to go through rename from decode to execute without being touched/modified at all by Rename

typedef struct packed {
    //logic        valid;
    logic [31:0] pc;
    logic [31:0] inst;
} fetch_dec_t;


typedef struct packed {
    logic        valid;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [31:0] imm;

    logic        ALUSrc;
    logic [2:0]  ALUOp;
    logic        branch;
    logic        jump;

    logic        MemRead;
    logic        MemWrite;
    logic        RegWrite;
    logic        MemToReg;
} dec_ren_t;




typedef struct packed {
    logic        valid;
    logic [5:0]  rs1_p;
    logic [5:0]  rs2_p;
    logic [5:0]  rd_new_p;
    logic [5:0]  rd_old_p;
    logic [5:0]  rob_tag;

    logic        ALUSrc;
    logic [2:0]  ALUOp;
    logic        branch;
    logic        jump;
    logic        MemRead;
    logic        RegWrite;
    logic        MemToReg;
    logic [31:0] pc;
    logic [31:0] imm;
} ren_disp_t;

// ... more typedefs here ...

endpackage
