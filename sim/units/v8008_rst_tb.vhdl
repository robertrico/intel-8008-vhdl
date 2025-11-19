-------------------------------------------------------------------------------
-- Intel 8008 v8008 All RST Instructions Test
-------------------------------------------------------------------------------
-- Instantiates 8 separate RST tests (RST 0-7) using v8008_rst_single_tb
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_rst_tb is
end v8008_rst_tb;

architecture behavior of v8008_rst_tb is
    
    -- Component declaration for single RST test
    component v8008_rst_single_tb
        generic (
            RST_NUM : integer range 0 to 7;
            TEST_NAME : string
        );
    end component;
    
begin

    -- Test RST 0 (vector 0x0000)
    RST0_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 0,
            TEST_NAME => "RST 0"
        );
    
    -- Test RST 1 (vector 0x0008)
    RST1_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 1,
            TEST_NAME => "RST 1"
        );
    
    -- Test RST 2 (vector 0x0010)
    RST2_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 2,
            TEST_NAME => "RST 2"
        );
    
    -- Test RST 3 (vector 0x0018)
    RST3_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 3,
            TEST_NAME => "RST 3"
        );
    
    -- Test RST 4 (vector 0x0020)
    RST4_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 4,
            TEST_NAME => "RST 4"
        );
    
    -- Test RST 5 (vector 0x0028)
    RST5_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 5,
            TEST_NAME => "RST 5"
        );
    
    -- Test RST 6 (vector 0x0030)
    RST6_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 6,
            TEST_NAME => "RST 6"
        );
    
    -- Test RST 7 (vector 0x0038)
    RST7_TEST: v8008_rst_single_tb
        generic map (
            RST_NUM => 7,
            TEST_NAME => "RST 7"
        );

end behavior;