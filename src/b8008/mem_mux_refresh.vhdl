--------------------------------------------------------------------------------
-- mem_mux_refresh.vhdl
--------------------------------------------------------------------------------
-- Memory Multiplexer and Refresh Amplifiers for Intel 8008
--
-- Handles PC data input and register file data routing
-- - Assembles PC load data from various sources (stack, temp regs, RST)
-- - Routes data between internal bus and register file (scratchpad)
-- - In original 8008, also handled DRAM refresh (not needed for FPGA)
-- - DUMB module: just data routing, no logic
--
-- NOTE: Address selection (PC vs Stack) is now handled by b8008.vhdl.
-- H:L addresses come directly from register file via internal bus during T1/T2.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity mem_mux_refresh is
    port (
        -- PC load data sources (for JMP, CALL, RST)
        reg_a      : in std_logic_vector(7 downto 0);   -- From Temp Register A (high byte)
        reg_b      : in std_logic_vector(7 downto 0);   -- From Temp Register B (low byte)
        rst_vector : in std_logic_vector(2 downto 0);   -- RST instruction AAA field

        -- Register file (scratchpad) data routing
        regfile_data_out : in std_logic_vector(7 downto 0);   -- From register file
        regfile_data_in  : out std_logic_vector(7 downto 0);  -- To register file

        -- Internal data bus (separate in/out for synthesis compatibility)
        internal_bus_in  : in  std_logic_vector(7 downto 0);
        internal_bus_out : out std_logic_vector(7 downto 0);
        internal_bus_oe  : out std_logic;

        -- Control signals from Memory/I/O Control
        pc_load_from_regs  : in std_logic;  -- Load PC from Reg.a + Reg.b (JMP/CALL)
        pc_load_from_rst   : in std_logic;  -- Load PC from RST vector

        regfile_to_bus : in std_logic;  -- Register file drives internal bus
        bus_to_regfile : in std_logic;  -- Internal bus drives register file

        -- Outputs
        pc_data_in  : out address_t   -- To PC data input
    );
end entity mem_mux_refresh;

architecture rtl of mem_mux_refresh is

    signal pc_load_data : address_t;

begin

    -- PC data input - select source based on control signals.
    -- The actual load is controlled by pc_control.load in the PC module.
    -- RET loads nothing (PC-in-stack: the pop IS the return), so the
    -- sources are the RST vector (00000000_AAA_000) or the temp regs.
    pc_data_in <= to_unsigned(0, 8) & unsigned(rst_vector) & to_unsigned(0, 3) when pc_load_from_rst = '1' else
                  unsigned(reg_a(5 downto 0) & reg_b);  -- Default: from temp registers (JMP/CALL)

    -- Register file to internal bus routing
    -- When regfile_to_bus='1', register file drives the bus
    internal_bus_out <= regfile_data_out;
    internal_bus_oe  <= regfile_to_bus;

    -- Internal bus to register file routing
    -- When bus_to_regfile='1', bus data goes to register file
    regfile_data_in <= internal_bus_in when bus_to_regfile = '1' else (others => '0');

end architecture rtl;
