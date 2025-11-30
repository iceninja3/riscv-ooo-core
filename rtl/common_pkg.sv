package common_pkg;
    // Data coming from the Rename Stage
    typedef struct packed {
        logic [31:0] pc;
        logic [6:0]  p_dest;      // Physical Destination Reg
        logic [6:0]  p_src1;      // Physical Source 1 Reg
        logic [6:0]  p_src2;      // Physical Source 2 Reg
        logic        src1_valid;  // Is Source 1 needed?
        logic        src2_valid;  // Is Source 2 needed?
        logic [6:0]  opcode;      // From decode.sv
        logic [2:0]  funct3;
        logic [31:0] imm;
        logic        is_branch;
        logic        is_store;
        logic        is_load;
    } dispatch_packet_t;

    // What we store in the Reservation Station
    typedef struct packed {
        logic        valid;       // Slot is occupied
        logic [3:0]  rob_idx;     // Tag to notify ROB later
        logic [6:0]  p_dest;
        logic [6:0]  p_src1;
        logic        src1_ready;  // Is the value actually in the PRF?
        logic [6:0]  p_src2;
        logic        src2_ready;
        logic [31:0] imm;
        logic [6:0]  opcode;
    } rs_entry_t;
endpackage