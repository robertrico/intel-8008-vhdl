--------------------------------------------------------------------------------
-- Generic I/O Controller for Intel 8008
--------------------------------------------------------------------------------
-- Reusable I/O peripheral handler supporting both input and output ports
--
-- Intel 8008 I/O Architecture:
--   - Input ports:  0-7   (3-bit addressing, INP instruction)
--   - Output ports: 8-31  (5-bit addressing, OUT instruction)
--
-- Operation:
--   Output (OUT instruction):
--     1. T2 state: Cycle type "11" + port address on data bus bits[4:0]
--     2. T3 state: Output data on data bus bits[7:0]
--     3. Controller latches data into appropriate port register
--
--   Input (INP instruction):
--     1. T2 state: Cycle type "01" + port address on data bus bits[2:0]
--     2. T3 state: Controller drives data bus with port data
--
-- Generic Parameters:
--   NUM_OUTPUT_PORTS: Number of output ports to implement (8-31)
--   NUM_INPUT_PORTS:  Number of input ports to implement (0-7)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity io_controller is
    generic (
        NUM_OUTPUT_PORTS : integer := 24;  -- Ports 8-31 (default: all 24)
        NUM_INPUT_PORTS  : integer := 8    -- Ports 0-7 (default: all 8)
    );
    port (
        -- Clock and reset
        phi1      : in  std_logic;
        reset_n   : in  std_logic;

        -- CPU state signals
        S2        : in  std_logic;
        S1        : in  std_logic;
        S0        : in  std_logic;

        -- Data bus input (for reading during output operations and address capture)
        data_bus_in : in std_logic_vector(7 downto 0);

        -- Data bus output (for input operations - top-level handles tri-state)
        data_bus_out : out std_logic_vector(7 downto 0);
        data_bus_enable : out std_logic;  -- High when this controller should drive bus

        -- Output port registers (array of 8-bit ports)
        -- port_out(0) = port 8, port_out(1) = port 9, etc.
        port_out  : out std_logic_vector((NUM_OUTPUT_PORTS * 8) - 1 downto 0);

        -- Input port data (array of 8-bit ports)
        -- port_in(0) = port 0, port_in(1) = port 1, etc.
        port_in   : in  std_logic_vector((NUM_INPUT_PORTS * 8) - 1 downto 0);

        -- Interrupt controller integration (optional, can be left unconnected)
        -- Output Port 9: Interrupt mask register (write-only)
        int_mask_out    : out std_logic_vector(7 downto 0);
        -- Input Port 1: Interrupt status register (read-only)
        int_status_in   : in  std_logic_vector(7 downto 0);
        -- Input Port 2: Active interrupt source (read-only)
        int_active_in   : in  std_logic_vector(7 downto 0)
    );
end entity io_controller;

architecture rtl of io_controller is
    -- State detection signals
    signal is_t2 : std_logic;
    signal is_t3 : std_logic;

    -- Captured I/O cycle information from T2
    signal cycle_type : std_logic_vector(1 downto 0);
    signal port_addr  : std_logic_vector(4 downto 0);

    -- I/O cycle type detection
    signal is_output_cycle : std_logic;  -- OUT instruction (cycle type "11")
    signal is_input_cycle  : std_logic;  -- INP instruction (cycle type "01")

    -- Output port registers
    type output_port_array is array (0 to NUM_OUTPUT_PORTS - 1) of std_logic_vector(7 downto 0);
    signal output_ports : output_port_array;

    -- Internal signals for data bus output
    signal data_bus_out_int : std_logic_vector(7 downto 0);
    signal data_bus_enable_int : std_logic;

    -- Interrupt controller integration
    signal int_mask_reg : std_logic_vector(7 downto 0);

begin
    -- Detect CPU states
    is_t2 <= '1' when (S2 = '1' and S1 = '0' and S0 = '0') else '0';
    is_t3 <= '1' when (S2 = '0' and S0 = '1' and S1 = '0') else '0';

    -- I/O cycle type detection
    is_output_cycle <= '1' when cycle_type = "11" else '0';  -- PCC (output)
    is_input_cycle  <= '1' when cycle_type = "01" else '0';  -- PCI (input)

    -- Pack output port registers into output vector
    gen_port_out: for i in 0 to NUM_OUTPUT_PORTS - 1 generate
        port_out((i * 8) + 7 downto (i * 8)) <= output_ports(i);
    end generate;

    -- Connect internal signals to output ports (top-level handles tri-state)
    data_bus_out <= data_bus_out_int;
    data_bus_enable <= data_bus_enable_int;

    -- Interrupt controller integration outputs
    int_mask_out <= int_mask_reg;

    -- Main I/O control process
    process(phi1, reset_n)
        variable output_port_index : integer;
        variable input_port_index  : integer;
    begin
        if reset_n = '0' then
            -- Reset all output ports to 0x00 (safe default)
            for i in 0 to NUM_OUTPUT_PORTS - 1 loop
                output_ports(i) <= (others => '0');
            end loop;

            -- Reset interrupt mask to all enabled
            int_mask_reg <= (others => '1');

            cycle_type <= "00";
            port_addr <= (others => '0');
            data_bus_enable_int <= '0';
            data_bus_out_int <= (others => '0');

        elsif rising_edge(phi1) then
            -- Default: don't drive bus
            data_bus_enable_int <= '0';

            -- T2 state: Capture cycle type and port address from data bus
            if is_t2 = '1' then
                cycle_type <= data_bus_in(7 downto 6);  -- Bits [7:6] = cycle type
                port_addr  <= data_bus_in(4 downto 0);  -- Bits [4:0] = port address
            end if;

            -- T3 state: Handle I/O operation
            if is_t3 = '1' then
                -- I/O cycle (PCC cycle type "11")
                -- Intel 8008 uses same cycle type for both IN and OUT
                -- Port address determines operation type:
                --   0-7: Input ports (INP instruction)
                --   8-31: Output ports (OUT instruction)
                if cycle_type = "11" then
                    -- Check port address to determine operation type
                    if unsigned(port_addr) <= 7 then
                        -- INPUT operation (INP 0-7)
                        input_port_index := to_integer(unsigned(port_addr(2 downto 0)));

                        -- Special ports for interrupt controller
                        if input_port_index = 1 then
                            -- INP 1: Interrupt status register
                            data_bus_out_int <= int_status_in;
                            data_bus_enable_int <= '1';
                        elsif input_port_index = 2 then
                            -- INP 2: Active interrupt source
                            data_bus_out_int <= int_active_in;
                            data_bus_enable_int <= '1';
                        elsif input_port_index < NUM_INPUT_PORTS then
                            -- Normal input port (port 0, 3-7)
                            data_bus_out_int <= port_in((input_port_index * 8) + 7 downto (input_port_index * 8));
                            data_bus_enable_int <= '1';
                        else
                            -- Invalid port: return 0xFF
                            data_bus_out_int <= (others => '1');
                            data_bus_enable_int <= '1';
                        end if;
                    else
                        -- OUTPUT operation (OUT 8-31)
                        output_port_index := to_integer(unsigned(port_addr)) - 8;

                        -- Special port: OUT 9 = interrupt mask register
                        if to_integer(unsigned(port_addr)) = 9 then
                            int_mask_reg <= data_bus_in;
                        elsif output_port_index >= 0 and output_port_index < NUM_OUTPUT_PORTS then
                            output_ports(output_port_index) <= data_bus_in;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
