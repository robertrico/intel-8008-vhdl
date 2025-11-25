--------------------------------------------------------------------------------
-- register_file.vhdl
--------------------------------------------------------------------------------
-- Register File (Scratchpad) for Intel 8008
--
-- Seven 8-bit registers: A, B, C, D, E, H, L
-- - A: Accumulator (special purpose for ALU operations)
-- - B, C, D, E: General purpose
-- - H, L: High and Low bytes for memory addressing (H:L pair)
-- - Connects to internal data bus via Memory Multiplexer block
-- - Individual register enables from scratchpad decoder
-- - DUMB module: just storage registers
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity register_file is
    port (
        -- Clock (phi2 from clock generator - data latched on phi2)
        phi2 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- Data input/output (to/from Memory Multiplexer)
        data_in  : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0);

        -- Individual register enables (from scratchpad decoder)
        enable_a : in std_logic;
        enable_b : in std_logic;
        enable_c : in std_logic;
        enable_d : in std_logic;
        enable_e : in std_logic;
        enable_h : in std_logic;
        enable_l : in std_logic;

        -- Read/Write control (from scratchpad decoder)
        read_enable  : in std_logic;
        write_enable : in std_logic;

        -- Direct outputs for H and L (to AHL pointer)
        h_reg_out : out std_logic_vector(7 downto 0);
        l_reg_out : out std_logic_vector(7 downto 0)
    );
end entity register_file;

architecture rtl of register_file is

    -- Internal register storage
    signal reg_a : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_b : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_c : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_d : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_e : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_h : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_l : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Write to registers on phi2 rising edge
    process(phi2, reset)
    begin
        if reset = '1' then
            reg_a <= (others => '0');
            reg_b <= (others => '0');
            reg_c <= (others => '0');
            reg_d <= (others => '0');
            reg_e <= (others => '0');
            reg_h <= (others => '0');
            reg_l <= (others => '0');
        elsif rising_edge(phi2) then
            if write_enable = '1' then
                if enable_a = '1' then reg_a <= data_in; end if;
                if enable_b = '1' then reg_b <= data_in; end if;
                if enable_c = '1' then reg_c <= data_in; end if;
                if enable_d = '1' then reg_d <= data_in; end if;
                if enable_e = '1' then reg_e <= data_in; end if;
                if enable_h = '1' then reg_h <= data_in; end if;
                if enable_l = '1' then reg_l <= data_in; end if;
            end if;
        end if;
    end process;

    -- Read from registers (combinational, multiplexed output)
    data_out <= reg_a when (read_enable = '1' and enable_a = '1') else
                reg_b when (read_enable = '1' and enable_b = '1') else
                reg_c when (read_enable = '1' and enable_c = '1') else
                reg_d when (read_enable = '1' and enable_d = '1') else
                reg_e when (read_enable = '1' and enable_e = '1') else
                reg_h when (read_enable = '1' and enable_h = '1') else
                reg_l when (read_enable = '1' and enable_l = '1') else
                (others => '0');

    -- Direct outputs for H and L (always available to AHL pointer)
    h_reg_out <= reg_h;
    l_reg_out <= reg_l;

end architecture rtl;
